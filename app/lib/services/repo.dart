import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../logic/financial_intent.dart';
import '../logic/idempotent.dart';
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
    // Normalmente basta la fila de la empresa activa (1 llamada). El perfil de usuario solo se pide si no hay empresa
    // o si la migración multi-empresa no está aplicada.
    final org = activeOrgId;
    if (org != null) {
      try {
        final o = await _db.from('organizations').select(_orgIssuerCols).eq('id', org).maybeSingle();
        if (o != null) {
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
        }
      } on PostgrestException {
        // cae al perfil de usuario
      }
    }
    final row = await _db.from('profiles').select().eq('id', _uid).maybeSingle();
    return row == null ? Profile() : Profile.fromJson(row);
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
      'id, number, issue_date, created_at, status, currency, tax_rate, notes, clients(name, tax_id, doc_type, email), fiscal_documents(status, series, correlative, doc_type), invoice_items(description, quantity, unit_price, position)';

  // Con cobros (migración 20261030); si aún no existe, se usa la versión anterior.
  static const _invoiceSelectPay = '$_invoiceSelect, due_date, payments(amount)';

  // v3 (migración 20261113): tipo, anulado, importado y montos guardados.
  static const _invoiceSelectV3 = '$_invoiceSelectPay, doc_kind, voided_at, import_job_id, totals_locked, amt_base, amt_tax, amt_total';

  // Versión mínima: sirve aunque aún no existan las tablas/columnas fiscales (migración 2).
  static const _invoiceSelectBasic =
      'id, number, issue_date, status, currency, tax_rate, notes, clients(name, tax_id), invoice_items(description, quantity, unit_price, position)';

  static Future<List<InvoiceRecord>> listInvoices({int limit = 100}) async {
    Future<dynamic> q(String sel) => (activeOrgId == null ? _db.from('invoices').select(sel) : _db.from('invoices').select(sel).eq('org_id', activeOrgId!))
        .order('created_at', ascending: false)
        .order('position', referencedTable: 'invoice_items', ascending: true)
        .limit(limit);
    dynamic rows;
    try {
      rows = await q(_invoiceSelectV3);
    } on PostgrestException {
      try {
        rows = await q(_invoiceSelectPay);
      } on PostgrestException {
        try {
          rows = await q(_invoiceSelect);
        } on PostgrestException {
          rows = await q(_invoiceSelectBasic);
        }
      }
    }
    return (rows as List).map((r) => InvoiceRecord.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Guarda el correo del cliente de una factura (para no volver a escribirlo). Best-effort.
  static Future<void> setClientEmail(String invoiceId, String email) async {
    try {
      final row = await _db.from('invoices').select('client_id').eq('id', invoiceId).maybeSingle();
      final cid = row?['client_id'] as String?;
      if (cid != null) await _db.from('clients').update({'email': email.trim().toLowerCase()}).eq('id', cid);
    } catch (_) {}
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
      rows = await q(_invoiceSelectV3);
    } on PostgrestException {
      try {
        rows = await q(_invoiceSelectPay);
      } on PostgrestException {
        try {
          rows = await q(_invoiceSelect);
        } on PostgrestException {
          rows = await q(_invoiceSelectBasic);
        }
      }
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
    final id = (rows.first as Map)['invoice_id'] as String;
    // Venta al crédito: guarda la fecha de vencimiento (con reintentos; si fallara, se puede fijar desde el detalle).
    if (d.dueDate != null) {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await setDueDate(id, d.dueDate);
          break;
        } catch (_) {
          await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    return id;
  }


  static bool _isDuplicate(Object e) => e is PostgrestException && e.code == '23505';
  static bool _isTransient(Object e) => e is! PostgrestException && e is! AuthException && e is! AppException;

  /// Intentos financieros guardados en el teléfono hasta conocer su estado final (logic/financial_intent.dart).
  static final financialIntents = FinancialIntents(_SecureIntentStorage());

  /// Registra un cobro, abono o movimiento de caja EXACTAMENTE una vez, aunque falle la red, se cierre la app o el
  /// usuario lo repita. [target] = objetivo lógico (misma factura, mismo cliente, misma caja): mientras un intento
  /// previo para ese objetivo no esté confirmado, no se crea otro.
  static Future<void> insertOnce(String table, Map<String, dynamic> row, {required String target}) async {
    final org = row['org_id'] as String?;
    final user = _db.auth.currentUser?.id;
    if (org == null || user == null) throw AppException('Tu sesión o empresa no está lista. Vuelve a intentarlo.');
    final outcome = await financialIntents.record(
      orgId: org,
      userId: user,
      table: table,
      target: target,
      row: row,
      newId: newRequestId,
      send: (t, r) => runIdempotent(() => _db.from(t).insert(r), isDuplicate: _isDuplicate, isTransient: _isTransient),
      exists: (t, id) async => (await _db.from(t).select('id').eq('id', id).maybeSingle()) != null,
      isDuplicate: _isDuplicate,
      isTransient: _isTransient,
    );
    if (outcome == IntentOutcome.previousConfirmed) {
      throw AppException('La operación anterior SÍ se registró. No se creó otra para no duplicarla: revisa el historial y, si de verdad hace falta otra, repítela.');
    }
  }

  /// Intentos sin confirmar de esta empresa (para mostrar "Pendiente de confirmar" y resolverlos al reconectar).
  static Future<List<FinancialIntent>> pendingFinancial() async {
    final org = activeOrgId;
    final user = _db.auth.currentUser?.id;
    if (org == null || user == null) return const [];
    return financialIntents.list(user, org);
  }

  /// Resuelve los intentos pendientes (al volver la conexión): comprueba en el servidor y reenvía con el MISMO id.
  static Future<int> resolvePendingFinancial() async {
    var done = 0;
    for (final i in await pendingFinancial()) {
      try {
        if (await financialIntents.resolve(i,
            send: (t, r) => runIdempotent(() => _db.from(t).insert(r), isDuplicate: _isDuplicate, isTransient: _isTransient),
            exists: (t, id) async => (await _db.from(t).select('id').eq('id', id).maybeSingle()) != null,
            isDuplicate: _isDuplicate,
            isTransient: _isTransient)) {
          done++;
        }
      } on IntentUnknown {
        break; // sigue sin conexión
      } catch (_) {
        // rechazado por la base: el intento se descartó (definitivo)
      }
    }
    return done;
  }

  /// UUIDv4 generated with a cryptographic source. Reuse this ID on every retry.
  static String newRequestId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Creates invoice, issues it, decrements SKU stock and registers payment in ONE DB transaction.
  /// Requires migration 20261123. Never fall back to three separate requests.
  static Future<String> fastCheckoutAtomic({
    required InvoiceDraft draft, required String method, required String requestId,
  }) async {
    final org = activeOrgId;
    if (org == null) throw AppException('Selecciona una empresa antes de vender.');
    final result = await _db.rpc('fast_checkout_atomic', params: {
      'p_org_id': org, 'p_request_id': requestId,
      'p_items': draft.items.map((e) => e.toJson()).toList(),
      'p_tax_rate': round2(draft.taxRate), 'p_currency': draft.currency,
      'p_method': method, 'p_notes': draft.notes,
    });
    if (result is! List || result.isEmpty || result.first is! Map) {
      throw AppException('El servidor no confirmó el cobro. Comprueba el estado antes de repetirlo.');
    }
    final data = Map<String, dynamic>.from(result.first as Map);
    final id = data['invoice_id'] as String?;
    if (id == null) throw AppException('No se recibió un identificador de venta.');
    return id;
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

  /// Clientes de la empresa activa, sin duplicados (cada factura puede haber creado una fila: se agrupan por documento o nombre).
  static Future<List<ClientCard>> listClients() async {
    final base = _db.from('clients').select('id, name, tax_id, email, address, doc_type');
    final rows = await (activeOrgId == null ? base : base.eq('org_id', activeOrgId!)).order('created_at', ascending: false).limit(2000);
    final groups = <String, ClientCard>{};
    for (final r in rows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final name = ((m['name'] ?? '') as String).trim();
      if (name.isEmpty) continue;
      final tax = ((m['tax_id'] ?? '') as String).trim();
      final key = tax.isNotEmpty ? 'd:$tax' : 'n:${name.toLowerCase()}';
      final g = groups[key];
      if (g == null) {
        groups[key] = ClientCard(
          ids: [m['id'] as String],
          name: name,
          taxId: tax,
          email: ((m['email'] ?? '') as String).trim(),
          address: ((m['address'] ?? '') as String).trim(),
        );
      } else {
        g.ids.add(m['id'] as String);
        if (g.email.isEmpty) g.email = ((m['email'] ?? '') as String).trim();
        if (g.address.isEmpty) g.address = ((m['address'] ?? '') as String).trim();
      }
    }
    final out = groups.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Actualiza todas las filas de un mismo cliente (datos de contacto; no cambia facturas ya emitidas).
  static Future<void> updateClient(ClientCard c, {required String name, required String taxId, required String email, required String address}) async {
    await _db.from('clients').update({
      'name': name.trim(),
      'tax_id': taxId.trim().isEmpty ? null : taxId.trim(),
      'email': email.trim().isEmpty ? null : email.trim().toLowerCase(),
      'address': address.trim().isEmpty ? null : address.trim(),
    }).inFilter('id', c.ids);
  }

  // ---------------- Catálogo ----------------
  static Future<List<Product>> listProducts({bool activeOnly = false}) async {
    Future<dynamic> run(String cols) {
      var q = _db.from('products').select(cols);
      if (activeOrgId != null) q = q.eq('org_id', activeOrgId!);
      if (activeOnly) q = q.eq('active', true);
      return q.order('name', ascending: true).limit(1000);
    }

    dynamic rows;
    try {
      rows = await run('id, name, unit_price, unit, active, stock, reorder_point, unit_cost, in_store');
    } on PostgrestException {
      try {
        rows = await run('id, name, unit_price, unit, active, stock, reorder_point'); // migración 20261102 pendiente
      } on PostgrestException {
        rows = await run('id, name, unit_price, unit, active'); // migración de stock aún no aplicada
      }
    }
    return (rows as List).map((r) => Product.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Crea o actualiza; devuelve el id del producto.
  static Future<String> saveProduct({String? id, required String name, required double unitPrice, required String unit}) async {
    final data = {'name': name.trim(), 'unit_price': round2(unitPrice), 'unit': unit};
    if (id != null) {
      await _db.from('products').update(data).eq('id', id);
      return id;
    }
    final org = activeOrgId;
    if (org == null) throw AppException('Elige una empresa primero.');
    final row = await _db.from('products').insert({...data, 'org_id': org, 'user_id': _uid}).select('id').single();
    return row['id'] as String;
  }

  static Future<void> setProductActive(String id, bool active) async {
    await _db.from('products').update({'active': active}).eq('id', id);
  }

  /// Solo propietarios/administradores (lo exige la base de datos).
  static Future<void> deleteProduct(String id) async {
    final rows = await _db.from('products').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) throw AppException('Solo un administrador de la empresa puede borrar productos. Puedes archivarlo.');
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
      row = await q(_invoiceSelectV3);
    } on PostgrestException {
      try {
        row = await q(_invoiceSelectPay);
      } on PostgrestException {
        try {
          row = await q(_invoiceSelect);
        } on PostgrestException {
          row = await q(_invoiceSelectBasic);
        }
      }
    }
    return InvoiceRecord.fromJson(row);
  }

  /// Crea un borrador nuevo con los mismos datos que [inv] (cliente, líneas, impuesto, notas y correo del cliente).
  static Future<String> duplicateInvoice(InvoiceRecord inv) async {
    final id = await createInvoice(InvoiceDraft(
      clientName: inv.clientName,
      clientTaxId: inv.clientTaxId,
      taxRate: inv.taxRate,
      currency: inv.currency,
      notes: inv.notes,
      items: inv.items.map((i) => LineItem(description: i.description, quantity: i.quantity, unitPrice: i.unitPrice)).toList(),
    ));
    if (inv.clientEmail.isNotEmpty) await setClientEmail(id, inv.clientEmail);
    return id;
  }

  // ---------------- Cobros ----------------
  static Future<List<Payment>> listPayments(String invoiceId) async {
    final rows = await _db
        .from('payments')
        .select('id, amount, paid_on, method, note')
        .eq('invoice_id', invoiceId)
        .order('paid_on', ascending: true)
        .order('created_at', ascending: true);
    return (rows as List).map((r) => Payment.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  static Future<void> addPayment({
    required String invoiceId,
    required double amount,
    required String method,
    String note = '',
    String? paidOn,
  }) async {
    final org = activeOrgId;
    final inv = await _db.from('invoices').select('org_id').eq('id', invoiceId).single();
    await insertOnce(target: 'invoice:$invoiceId', 'payments', {
      'org_id': (inv['org_id'] as String?) ?? org,
      'invoice_id': invoiceId,
      'user_id': _uid,
      'amount': round2(amount),
      'method': method,
      if (note.trim().isNotEmpty) 'note': note.trim(),
      if (paidOn != null) 'paid_on': paidOn,
    });
  }

  /// Solo administradores y solo mientras la factura no esté marcada como pagada (lo exige la base de datos).
  static Future<void> deletePayment(String id) async {
    final rows = await _db.from('payments').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) throw AppException('No se pudo anular el cobro. Solo un administrador puede hacerlo y solo mientras la factura no esté pagada.');
  }

  static Future<void> setDueDate(String invoiceId, String? isoDate) async {
    await _db.from('invoices').update({'due_date': isoDate}).eq('id', invoiceId);
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


/// Almacén cifrado del teléfono (mismo mecanismo que el cobro pendiente del POS).
class _SecureIntentStorage implements IntentStorage {
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions());
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}
