import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../models.dart';

/// Acceso a datos. Todo pasa por RLS: el usuario solo ve y modifica lo suyo.
class Repo {
  static SupabaseClient get _db => Supabase.instance.client;
  static String get _uid {
    final u = _db.auth.currentUser;
    if (u == null) throw AppException('Sesión caducada');
    return u.id;
  }

  /// Empresa activa (null = migración multi-empresa aún no aplicada: funciona como antes).
  static String? activeOrgId;

  static Future<List<Org>> listOrgs() async {
    try {
      final rows = await _db.from('organization_members').select('role, organizations(id, name, tax_id)').eq('user_id', _uid);
      final out = <Org>[];
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final o = m['organizations'];
        if (o is! Map) continue;
        out.add(Org(
          id: o['id'] as String,
          name: (o['name'] ?? '') as String,
          taxId: (o['tax_id'] ?? '') as String,
          role: (m['role'] ?? 'member') as String,
        ));
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } on PostgrestException {
      return const [];
    }
  }

  static Future<String> createOrg(String name, String taxId) async {
    final id = await _db.rpc('create_organization', params: {'p_name': name.trim(), 'p_tax_id': taxId.trim().isEmpty ? null : taxId.trim()});
    return id as String;
  }

  static Future<void> addMember(String orgId, String email, String role) async {
    await _db.rpc('add_org_member', params: {'p_org': orgId, 'p_email': email.trim(), 'p_role': role});
  }

  static Future<void> removeMember(String orgId, String userId) async {
    await _db.rpc('remove_org_member', params: {'p_org': orgId, 'p_user': userId});
  }

  static Future<List<OrgMember>> listMembers(String orgId) async {
    final rows = await _db.rpc('list_org_members', params: {'p_org': orgId});
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return OrgMember(userId: m['user_id'] as String, email: (m['email'] ?? '') as String, role: (m['role'] ?? 'member') as String);
    }).toList();
  }

  static Future<void> renameOrg(String orgId, String name) async {
    await _db.from('organizations').update({'name': name.trim()}).eq('id', orgId);
  }

  static const _orgIssuerCols =
      'name, tax_id, address, trade_name, ubigeo, department, province, district, series_factura, series_boleta, currency, tax_label, default_tax_rate';

  /// Datos del emisor = los de la empresa activa (si la migración multi-empresa está aplicada).
  static Future<Profile> loadProfile() async {
    final row = await _db.from('profiles').select().eq('id', _uid).maybeSingle();
    final base = row == null ? Profile() : Profile.fromJson(row);
    final org = activeOrgId;
    if (org == null) return base;
    try {
      final o = await _db.from('organizations').select(_orgIssuerCols).eq('id', org).maybeSingle();
      if (o == null) return base;
      return Profile.fromJson({
        'business_name': o['name'],
        'tax_id': o['tax_id'],
        'address': o['address'],
        'trade_name': o['trade_name'],
        'ubigeo': o['ubigeo'],
        'department': o['department'],
        'province': o['province'],
        'district': o['district'],
        'series_factura': o['series_factura'],
        'series_boleta': o['series_boleta'],
        'currency': o['currency'],
        'tax_label': o['tax_label'],
        'default_tax_rate': o['default_tax_rate'],
      });
    } on PostgrestException {
      return base;
    }
  }

  static Future<void> saveProfile(Profile p) async {
    final org = activeOrgId;
    if (org != null) {
      final j = p.toJson();
      final updated = await _db
          .from('organizations')
          .update({
            'name': j['business_name'],
            'tax_id': j['tax_id'],
            'address': j['address'],
            'trade_name': j['trade_name'],
            'ubigeo': j['ubigeo'],
            'department': j['department'],
            'province': j['province'],
            'district': j['district'],
            'series_factura': j['series_factura'],
            'series_boleta': j['series_boleta'],
            'currency': j['currency'],
            'tax_label': j['tax_label'],
            'default_tax_rate': j['default_tax_rate'],
          })
          .eq('id', org)
          .select('id');
      if ((updated as List).isEmpty) {
        throw AppException('Solo el propietario o un administrador puede cambiar los datos de la empresa.');
      }
    }
    await _db.from('profiles').upsert({'id': _uid, ...p.toJson()});
  }

  static const _invoiceSelect =
      'id, number, issue_date, status, currency, tax_rate, notes, clients(name, tax_id, doc_type), fiscal_documents(status, series, correlative, doc_type), invoice_items(description, quantity, unit_price, position)';

  // Versión mínima: sirve aunque aún no existan las tablas/columnas fiscales (migración 2).
  static const _invoiceSelectBasic =
      'id, number, issue_date, status, currency, tax_rate, notes, clients(name, tax_id), invoice_items(description, quantity, unit_price, position)';

  static Future<List<InvoiceRecord>> listInvoices() async {
    Future<dynamic> q(String sel) => (activeOrgId == null ? _db.from('invoices').select(sel) : _db.from('invoices').select(sel).eq('org_id', activeOrgId!))
        .order('created_at', ascending: false)
        .order('position', referencedTable: 'invoice_items', ascending: true)
        .limit(100);
    dynamic rows;
    try {
      rows = await q(_invoiceSelect);
    } on PostgrestException {
      rows = await q(_invoiceSelectBasic);
    }
    return (rows as List).map((r) => InvoiceRecord.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Facturas con fecha en [from, toExclusive) ('yyyy-MM-dd') de la empresa activa, para reportes.
  static Future<List<InvoiceRecord>> listInvoicesBetween(String from, String toExclusive) async {
    Future<dynamic> q(String sel) {
      var b = _db.from('invoices').select(sel).gte('issue_date', from).lt('issue_date', toExclusive);
      if (activeOrgId != null) b = b.eq('org_id', activeOrgId!);
      return b
          .order('issue_date', ascending: true)
          .order('position', referencedTable: 'invoice_items', ascending: true)
          .limit(5000);
    }

    dynamic rows;
    try {
      rows = await q(_invoiceSelect);
    } on PostgrestException {
      rows = await q(_invoiceSelectBasic);
    }
    return (rows as List).map((r) => InvoiceRecord.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Crea cliente + factura + líneas en UNA transacción (RPC create_invoice).
  static Future<String> createInvoice(InvoiceDraft d) async {
    final res = await _db.rpc('create_invoice', params: {
      'p_client_name': d.clientName.trim(),
      'p_client_tax_id': d.clientTaxId.trim().isEmpty ? null : d.clientTaxId.trim(),
      'p_tax_rate': round2(d.taxRate),
      'p_currency': d.currency,
      'p_notes': d.notes.trim().isEmpty ? null : d.notes.trim(),
      'p_transcript': d.transcript,
      'p_items': d.items.map((i) => i.toJson()).toList(),
      if (activeOrgId != null) 'p_org_id': activeOrgId,
    });
    final rows = res as List;
    if (rows.isEmpty) throw AppException('No se pudo crear la factura');
    return (rows.first as Map)['invoice_id'] as String;
  }

  /// Clientes anteriores (sin duplicados) para autocompletar. Si falla, simplemente no hay sugerencias.
  static Future<List<({String name, String taxId})>> recentClients() async {
    try {
      final base = _db.from('clients').select('name, tax_id');
      final rows = await (activeOrgId == null ? base : base.eq('org_id', activeOrgId!)).order('created_at', ascending: false).limit(300);
      final seen = <String>{};
      final out = <({String name, String taxId})>[];
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final name = ((m['name'] ?? '') as String).trim();
        if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
        out.add((name: name, taxId: ((m['tax_id'] ?? '') as String).trim()));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<InvoiceRecord> getInvoice(String id) async {
    Future<Map<String, dynamic>> q(String sel) async {
      final row = await _db
          .from('invoices')
          .select(sel)
          .eq('id', id)
          .order('position', referencedTable: 'invoice_items', ascending: true)
          .single();
      return Map<String, dynamic>.from(row);
    }

    Map<String, dynamic> row;
    try {
      row = await q(_invoiceSelect);
    } on PostgrestException {
      row = await q(_invoiceSelectBasic);
    }
    return InvoiceRecord.fromJson(row);
  }

  static Future<void> setStatus(String id, String status) async {
    await _db.from('invoices').update({'status': status}).eq('id', id);
  }

  static Future<void> deleteDraft(String id) async {
    await _db.from('invoices').delete().eq('id', id).eq('status', 'draft');
  }

  /// Empresa habilitada para emitir (la escribe solo el servidor). null = aún no configurada.
  static Future<FiscalCompany?> loadFiscalCompany() async {
    try {
      final q = _db.from('fiscal_companies').select('ruc, env');
      final row = await (activeOrgId == null ? q.eq('user_id', _uid) : q.eq('org_id', activeOrgId!)).maybeSingle();
      return row == null ? null : FiscalCompany(ruc: row['ruc'] as String, env: row['env'] as String);
    } on PostgrestException {
      return null; // migración fiscal pendiente
    }
  }

  static Future<FiscalDoc?> getFiscalDoc(String invoiceId) async {
    try {
      final row = await _db
          .from('fiscal_documents')
          .select('doc_type, series, correlative, env, status, legend, sunat_code, sunat_message, hash, payload, totals')
          .eq('invoice_id', invoiceId)
          .maybeSingle();
      return row == null ? null : FiscalDoc.fromJson(row);
    } on PostgrestException {
      return null;
    }
  }

  /// Nota de crédito (anulación) del comprobante, si existe.
  static Future<FiscalDoc?> getCreditNote(String invoiceId, String legend) async {
    try {
      final row = await _db
          .from('fiscal_notes')
          .select('series, correlative, env, status, sunat_code, sunat_message, hash, payload, totals')
          .eq('invoice_id', invoiceId)
          .maybeSingle();
      return row == null ? null : fiscalNoteFromJson(row, legend);
    } on PostgrestException {
      return null;
    }
  }

  /// Derecho de supresión: borra la cuenta y todos sus datos.
  static Future<void> deleteAccount() async {
    await _db.rpc('delete_my_account');
    try {
      await _db.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
}
