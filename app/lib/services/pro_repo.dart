import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import '../models.dart';
import '../models_pro.dart';
import 'repo.dart';

/// Acceso a datos de los módulos "Negocio Pro" (migración 20261101_negocio_pro.sql). Todo pasa por RLS.
class ProRepo {
  static SupabaseClient get _db => Supabase.instance.client;

  static String get _org {
    final o = Repo.activeOrgId;
    if (o == null) throw AppException('Elige una empresa primero.');
    return o;
  }

  static String get _uid {
    final u = _db.auth.currentUser;
    if (u == null) throw AppException('Sesión caducada');
    return u.id;
  }

  /// ¿Falta ejecutar la migración? (tabla o función inexistente)
  static bool isMissingMigration(Object e) =>
      e is PostgrestException && const {'42P01', 'PGRST205', 'PGRST202', '42883', 'PGRST200'}.contains(e.code);

  // ───────────── Cotizaciones ─────────────
  static const _quoteSelect =
      'id, number, status, issue_date, valid_until, currency, tax_rate, notes, public_token, invoice_id, responder_name, response_note, responded_at, clients(name, tax_id), quote_items(description, quantity, unit_price, position)';

  // Con origen (tienda) y celular del cliente: migración 20261102. Si falta, se usa la versión anterior.
  static const _quoteSelectStore = '$_quoteSelect, source, contact_phone';

  static Future<List<QuoteRecord>> listQuotes({int limit = 200}) async {
    Future<dynamic> run(String sel) => _db
        .from('quotes')
        .select(sel)
        .eq('org_id', _org)
        .order('created_at', ascending: false)
        .order('position', referencedTable: 'quote_items', ascending: true)
        .limit(limit);
    dynamic rows;
    try {
      rows = await run(_quoteSelectStore);
    } on PostgrestException {
      rows = await run(_quoteSelect);
    }
    return (rows as List).map((r) => QuoteRecord.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  static Future<QuoteRecord> getQuote(String id) async {
    Future<Map<String, dynamic>> run(String sel) async =>
        Map<String, dynamic>.from(await _db.from('quotes').select(sel).eq('id', id).order('position', referencedTable: 'quote_items', ascending: true).single());
    Map<String, dynamic> row;
    try {
      row = await run(_quoteSelectStore);
    } on PostgrestException {
      row = await run(_quoteSelect);
    }
    return QuoteRecord.fromJson(row);
  }

  static Future<String> createQuote(InvoiceDraft d, {String? validUntil}) async {
    final res = await _db.rpc('create_quote', params: {
      'p_org': _org,
      'p_client_name': d.clientName.trim(),
      'p_client_tax_id': d.clientTaxId.trim().isEmpty ? null : d.clientTaxId.trim(),
      'p_tax_rate': round2(d.taxRate),
      'p_currency': d.currency,
      'p_notes': d.notes.trim().isEmpty ? null : d.notes.trim(),
      'p_transcript': d.transcript,
      'p_items': d.items.map((i) => i.toJson()).toList(),
      'p_valid_until': validUntil,
    });
    final rows = res as List;
    if (rows.isEmpty) throw AppException('No se pudo crear la cotización');
    return (rows.first as Map)['quote_id'] as String;
  }

  /// Guarda el correo del cliente de una cotización (best-effort).
  static Future<void> setQuoteClientEmail(String quoteId, String email) async {
    try {
      final row = await _db.from('quotes').select('client_id').eq('id', quoteId).maybeSingle();
      final cid = row?['client_id'] as String?;
      if (cid != null) await _db.from('clients').update({'email': email.trim().toLowerCase()}).eq('id', cid);
    } catch (_) {}
  }

  static Future<void> setQuoteStatus(String id, String status) async {
    await _db.from('quotes').update({'status': status}).eq('id', id);
  }

  /// Convierte la cotización en factura (borrador) y devuelve el id de la factura.
  static Future<String> convertQuote(String id, {String? dueDate}) async {
    final res = await _db.rpc('convert_quote', params: {'p_quote': id, 'p_due_date': dueDate});
    return res as String;
  }

  static Future<void> deleteQuote(String id) async {
    final rows = await _db.from('quotes').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) throw AppException('Solo se pueden borrar cotizaciones en borrador o rechazadas.');
  }

  static String quoteUrl(String token) => '${Config.apiBase}/cotizacion/$token';

  // ───────────── Cobros ─────────────
  static Future<String> payLinkUrl(String invoiceId) async {
    final token = await _db.rpc('invoice_pay_link', params: {'p_invoice': invoiceId});
    return '${Config.apiBase}/pagar/$token';
  }

  static Future<PaySettings> loadPaySettings() async {
    final row = await _db.from('org_pay_settings').select().eq('org_id', _org).maybeSingle();
    return row == null ? PaySettings() : PaySettings.fromJson(row);
  }

  static Future<void> savePaySettings(PaySettings s) async {
    await _db.from('org_pay_settings').upsert(s.toRow(_org), onConflict: 'org_id');
  }

  static Future<List<PaymentClaim>> listClaims({bool pendingOnly = true}) async {
    var q = _db.from('payment_claims').select('id, invoice_id, amount, method, operation_code, payer_name, status, created_at, invoices(number, currency, clients(name))').eq('org_id', _org);
    if (pendingOnly) q = q.eq('status', 'pending');
    final rows = await q.order('created_at', ascending: false).limit(100);
    return (rows as List).map((r) => PaymentClaim.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  static Future<int> countPendingClaims() async {
    try {
      final res = await _db.from('payment_claims').select('id').eq('org_id', _org).eq('status', 'pending').count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  static Future<String> resolveClaim(String id, bool accept) async {
    final r = await _db.rpc('resolve_payment_claim', params: {'p_claim': id, 'p_accept': accept});
    return r as String;
  }

  /// Facturas con saldo por cobrar (emitidas, no pagadas) de la empresa activa.
  static Future<List<InvoiceRecord>> listReceivables() async {
    const sel =
        'id, number, issue_date, status, currency, tax_rate, notes, due_date, clients(name, tax_id, doc_type, email), fiscal_documents(status, series, correlative, doc_type), invoice_items(description, quantity, unit_price, position), payments(amount)';
    final rows = await _db
        .from('invoices')
        .select(sel)
        .eq('org_id', _org)
        .eq('status', 'sent')
        .order('due_date', ascending: true, nullsFirst: false)
        .order('position', referencedTable: 'invoice_items', ascending: true)
        .limit(1000);
    return (rows as List).map((r) => InvoiceRecord.fromJson(Map<String, dynamic>.from(r as Map))).where((i) => i.receivable).toList();
  }

  static Future<Map<String, ClientPayStats>> clientStats() async {
    final rows = await _db.rpc('client_payment_stats', params: {'p_org': _org});
    final out = <String, ClientPayStats>{};
    for (final r in rows as List) {
      final s = ClientPayStats.fromJson(Map<String, dynamic>.from(r as Map));
      out[s.key] = s;
    }
    return out;
  }

  /// Últimos recordatorios enviados por factura (para mostrar "recordado hace X días").
  static Future<Map<String, String>> lastReminders(Iterable<String> invoiceIds) async {
    final ids = invoiceIds.toList();
    if (ids.isEmpty) return const {};
    try {
      final rows = await _db.from('reminder_log').select('invoice_id, sent_at').inFilter('invoice_id', ids.take(300).toList()).order('sent_at', ascending: false);
      final out = <String, String>{};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        out.putIfAbsent(m['invoice_id'] as String, () => (m['sent_at'] as String).substring(0, 10));
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Registra que se envió un recordatorio por WhatsApp (best-effort).
  static Future<void> logWhatsAppReminder(InvoiceRecord inv, String today) async {
    try {
      final stage = inv.dueDate == null ? 0 : DateTime.parse(today).difference(DateTime.parse(inv.dueDate!)).inDays;
      await _db.from('reminder_log').upsert(
        {'org_id': _org, 'invoice_id': inv.id, 'stage': stage, 'channel': 'whatsapp'},
        onConflict: 'invoice_id,stage,channel',
        ignoreDuplicates: true,
      );
    } catch (_) {}
  }

  /// Cobros con fecha en [from, toExclusive) para el flujo de caja.
  static Future<List<DatedPayment>> listPaymentsBetween(String from, String toExclusive) async {
    final rows = await _db
        .from('payments')
        .select('amount, paid_on, invoices(currency)')
        .eq('org_id', _org)
        .gte('paid_on', from)
        .lt('paid_on', toExclusive)
        .limit(5000);
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      final inv = m['invoices'] is Map ? Map<String, dynamic>.from(m['invoices'] as Map) : const <String, dynamic>{};
      return DatedPayment(amount: (m['amount'] as num).toDouble(), paidOn: m['paid_on'] as String, currency: (inv['currency'] ?? 'PEN') as String);
    }).toList();
  }

  // ───────────── Gastos ─────────────
  static Future<List<Expense>> listExpenses(String from, String toExclusive) async {
    final rows = await _db
        .from('expenses')
        .select('id, spent_on, category, description, total, tax, currency, supplier_name, supplier_tax_id, doc_number, source')
        .eq('org_id', _org)
        .gte('spent_on', from)
        .lt('spent_on', toExclusive)
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(3000);
    return (rows as List).map((r) => Expense.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  static Future<void> addExpense(Expense e) async {
    await _db.from('expenses').insert(e.toInsert(_org, _uid));
  }

  static Future<void> deleteExpense(String id) async {
    final rows = await _db.from('expenses').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) throw AppException('Solo quien lo registró o un administrador puede borrarlo.');
  }

  // ───────────── Stock ─────────────
  static Future<List<ProductVelocity>> productVelocity({int days = 30}) async {
    final rows = await _db.rpc('product_velocity', params: {'p_org': _org, 'p_days': days});
    return (rows as List).map((r) => ProductVelocity.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  static Future<double?> stockAdjust(String productId, double delta) async {
    final r = await _db.rpc('stock_adjust', params: {'p_product': productId, 'p_delta': round2(delta)});
    if (r == null) return null;
    return (r as num).toDouble();
  }

  static Future<void> setStockConfig(String productId, {double? stock, double? reorderPoint}) async {
    await _db.from('products').update({'stock': stock == null ? null : round2(stock), 'reorder_point': reorderPoint == null ? null : round2(reorderPoint)}).eq('id', productId);
  }
}
