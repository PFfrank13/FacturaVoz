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

  static Future<Profile> loadProfile() async {
    final row = await _db.from('profiles').select().eq('id', _uid).maybeSingle();
    return row == null ? Profile() : Profile.fromJson(row);
  }

  static Future<void> saveProfile(Profile p) async {
    await _db.from('profiles').upsert({'id': _uid, ...p.toJson()});
  }

  static const _invoiceSelect =
      'id, number, issue_date, status, currency, tax_rate, notes, clients(name, tax_id, doc_type), fiscal_documents(status, series, correlative, doc_type), invoice_items(description, quantity, unit_price, position)';

  // Versión mínima: sirve aunque aún no existan las tablas/columnas fiscales (migración 2).
  static const _invoiceSelectBasic =
      'id, number, issue_date, status, currency, tax_rate, notes, clients(name, tax_id), invoice_items(description, quantity, unit_price, position)';

  static Future<List<InvoiceRecord>> listInvoices() async {
    Future<dynamic> q(String sel) => _db
        .from('invoices')
        .select(sel)
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
    });
    final rows = res as List;
    if (rows.isEmpty) throw AppException('No se pudo crear la factura');
    return (rows.first as Map)['invoice_id'] as String;
  }

  /// Clientes anteriores (sin duplicados) para autocompletar. Si falla, simplemente no hay sugerencias.
  static Future<List<({String name, String taxId})>> recentClients() async {
    try {
      final rows = await _db.from('clients').select('name, tax_id').order('created_at', ascending: false).limit(300);
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
    final row = await _db
        .from('invoices')
        .select(_invoiceSelect)
        .eq('id', id)
        .order('position', referencedTable: 'invoice_items', ascending: true)
        .single();
    return InvoiceRecord.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<void> setStatus(String id, String status) async {
    await _db.from('invoices').update({'status': status}).eq('id', id);
  }

  static Future<void> deleteDraft(String id) async {
    await _db.from('invoices').delete().eq('id', id).eq('status', 'draft');
  }

  /// Empresa habilitada para emitir (la escribe solo el servidor). null = aún no configurada.
  static Future<FiscalCompany?> loadFiscalCompany() async {
    final row = await _db.from('fiscal_companies').select('ruc, env').eq('user_id', _uid).maybeSingle();
    return row == null ? null : FiscalCompany(ruc: row['ruc'] as String, env: row['env'] as String);
  }

  static Future<FiscalDoc?> getFiscalDoc(String invoiceId) async {
    final row = await _db
        .from('fiscal_documents')
        .select('doc_type, series, correlative, env, status, legend, sunat_code, sunat_message, hash, payload, totals')
        .eq('invoice_id', invoiceId)
        .maybeSingle();
    return row == null ? null : FiscalDoc.fromJson(row);
  }

  /// Nota de crédito (anulación) del comprobante, si existe.
  static Future<FiscalDoc?> getCreditNote(String invoiceId, String legend) async {
    final row = await _db
        .from('fiscal_notes')
        .select('series, correlative, env, status, sunat_code, sunat_message, hash, payload, totals')
        .eq('invoice_id', invoiceId)
        .maybeSingle();
    return row == null ? null : fiscalNoteFromJson(row, legend);
  }

  /// Derecho de supresión: borra la cuenta y todos sus datos.
  static Future<void> deleteAccount() async {
    await _db.rpc('delete_my_account');
    try {
      await _db.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
}
