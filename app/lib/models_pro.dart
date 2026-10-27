import 'models.dart';

double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? _numOrNull(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
String _s(dynamic v) => (v ?? '').toString();

// ───────────────────────── Cotizaciones ─────────────────────────

String quoteStatusLabel(String s) => switch (s) {
      'draft' => 'Borrador',
      'sent' => 'Enviada',
      'accepted' => 'Aceptada',
      'rejected' => 'Rechazada',
      'converted' => 'Facturada',
      _ => s,
    };

class QuoteRecord {
  QuoteRecord({
    required this.id,
    required this.number,
    required this.status,
    required this.issueDate,
    required this.validUntil,
    required this.currency,
    required this.taxRate,
    required this.notes,
    required this.clientName,
    required this.clientTaxId,
    required this.publicToken,
    required this.items,
    this.invoiceId,
    this.responderName = '',
    this.responseNote = '',
    this.respondedAt,
  });

  final String id;
  final String number;
  final String status; // draft | sent | accepted | rejected | converted
  final String issueDate;
  final String? validUntil;
  final String currency;
  final double taxRate;
  final String notes;
  final String clientName;
  final String clientTaxId;
  final String publicToken;
  final List<LineItem> items;
  final String? invoiceId;
  final String responderName;
  final String responseNote;
  final String? respondedAt;

  Totals get totals => computeTotals(items, taxRate);

  bool isExpired(String today) => (status == 'draft' || status == 'sent') && validUntil != null && validUntil!.compareTo(today) < 0;
  bool get canConvert => status != 'converted' && status != 'rejected';

  factory QuoteRecord.fromJson(Map<String, dynamic> j) {
    final c = j['clients'] is Map ? Map<String, dynamic>.from(j['clients'] as Map) : const <String, dynamic>{};
    return QuoteRecord(
      id: j['id'] as String,
      number: _s(j['number']),
      status: _s(j['status']),
      issueDate: _s(j['issue_date']),
      validUntil: j['valid_until'] as String?,
      currency: _s(j['currency']).isEmpty ? 'PEN' : _s(j['currency']),
      taxRate: _num(j['tax_rate']),
      notes: _s(j['notes']),
      clientName: c['name'] == null ? '—' : _s(c['name']),
      clientTaxId: _s(c['tax_id']),
      publicToken: _s(j['public_token']),
      invoiceId: j['invoice_id'] as String?,
      responderName: _s(j['responder_name']),
      responseNote: _s(j['response_note']),
      respondedAt: j['responded_at'] as String?,
      items: ((j['quote_items'] ?? []) as List).map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }
}

// ───────────────────────── Gastos ─────────────────────────

const expenseCategories = <String, String>{
  'mercaderia': 'Mercadería',
  'insumos': 'Insumos',
  'servicios': 'Servicios (luz, agua, internet)',
  'alquiler': 'Alquiler',
  'planilla': 'Sueldos',
  'transporte': 'Transporte',
  'marketing': 'Publicidad',
  'impuestos': 'Impuestos',
  'equipos': 'Equipos',
  'otros': 'Otros',
};

class Expense {
  Expense({
    this.id,
    required this.spentOn,
    required this.category,
    required this.description,
    required this.total,
    this.tax = 0,
    this.currency = 'PEN',
    this.supplierName = '',
    this.supplierTaxId = '',
    this.docNumber = '',
    this.source = 'manual',
  });

  final String? id;
  final String spentOn; // yyyy-MM-dd
  final String category;
  final String description;
  final double total;
  final double tax;
  final String currency;
  final String supplierName;
  final String supplierTaxId;
  final String docNumber;
  final String source; // manual | voice | scan

  /// Gasto sin IGV (lo que realmente cuesta si el IGV se recupera como crédito fiscal).
  double get base => round2(total - tax);

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String?,
        spentOn: _s(j['spent_on']),
        category: _s(j['category']).isEmpty ? 'otros' : _s(j['category']),
        description: _s(j['description']),
        total: _num(j['total']),
        tax: _num(j['tax']),
        currency: _s(j['currency']).isEmpty ? 'PEN' : _s(j['currency']),
        supplierName: _s(j['supplier_name']),
        supplierTaxId: _s(j['supplier_tax_id']),
        clientName: _s(j['client_name']),
        clientTaxId: _s(j['client_tax_id']),
        docNumber: _s(j['doc_number']),
        source: _s(j['source']).isEmpty ? 'manual' : _s(j['source']),
      );

  Map<String, dynamic> toInsert(String orgId, String userId) => {
        'org_id': orgId,
        'user_id': userId,
        'spent_on': spentOn,
        'category': expenseCategories.containsKey(category) ? category : 'otros',
        'description': description.trim().isEmpty ? 'Gasto' : description.trim(),
        'total': round2(total),
        'tax': round2(tax),
        'currency': currency,
        'source': source,
        if (supplierName.trim().isNotEmpty) 'supplier_name': supplierName.trim(),
        if (supplierTaxId.trim().isNotEmpty) 'supplier_tax_id': supplierTaxId.trim(),
        if (docNumber.trim().isNotEmpty) 'doc_number': docNumber.trim(),
      };
}

// ───────────────────────── Cobros ─────────────────────────

class PaymentClaim {
  PaymentClaim({
    required this.id,
    required this.invoiceId,
    required this.amount,
    required this.method,
    required this.operationCode,
    required this.payerName,
    required this.status,
    required this.createdAt,
    this.invoiceNumber = '',
    this.clientName = '',
    this.currency = 'PEN',
  });

  final String id;
  final String invoiceId;
  final double amount;
  final String method;
  final String operationCode;
  final String payerName;
  final String status;
  final String createdAt;
  final String invoiceNumber;
  final String clientName;
  final String currency;

  factory PaymentClaim.fromJson(Map<String, dynamic> j) {
    final inv = j['invoices'] is Map ? Map<String, dynamic>.from(j['invoices'] as Map) : const <String, dynamic>{};
    final c = inv['clients'] is Map ? Map<String, dynamic>.from(inv['clients'] as Map) : const <String, dynamic>{};
    return PaymentClaim(
      id: j['id'] as String,
      invoiceId: _s(j['invoice_id']),
      amount: _num(j['amount']),
      method: _s(j['method']),
      operationCode: _s(j['operation_code']),
      payerName: _s(j['payer_name']),
      status: _s(j['status']),
      createdAt: _s(j['created_at']),
      invoiceNumber: _s(inv['number']),
      clientName: _s(c['name']),
      currency: _s(inv['currency']).isEmpty ? 'PEN' : _s(inv['currency']),
    );
  }
}

class PaySettings {
  PaySettings({
    this.yape = '',
    this.plin = '',
    this.bankName = '',
    this.bankAccount = '',
    this.bankCci = '',
    this.holder = '',
    this.note = '',
    this.mpEnabled = false,
    this.remindersEnabled = false,
    List<int>? offsets,
  }) : offsets = offsets ?? const [-3, 0, 3, 7, 15];

  String yape;
  String plin;
  String bankName;
  String bankAccount;
  String bankCci;
  String holder;
  String note;
  bool mpEnabled;
  bool remindersEnabled;
  List<int> offsets;

  bool get hasAnyMethod => yape.isNotEmpty || plin.isNotEmpty || bankAccount.isNotEmpty || bankCci.isNotEmpty || mpEnabled;

  factory PaySettings.fromJson(Map<String, dynamic> j) => PaySettings(
        yape: _s(j['yape_phone']),
        plin: _s(j['plin_phone']),
        bankName: _s(j['bank_name']),
        bankAccount: _s(j['bank_account']),
        bankCci: _s(j['bank_cci']),
        holder: _s(j['account_holder']),
        note: _s(j['pay_note']),
        mpEnabled: j['mp_enabled'] == true,
        remindersEnabled: j['reminders_enabled'] == true,
        offsets: j['reminder_offsets'] is List ? (j['reminder_offsets'] as List).map((e) => _num(e).toInt()).toList() : null,
      );

  Map<String, dynamic> toRow(String orgId) {
    String? n(String v) => v.trim().isEmpty ? null : v.trim();
    final sorted = [...offsets]..sort();
    return {
      'org_id': orgId,
      'yape_phone': n(yape.replaceAll(RegExp(r'\D'), '')),
      'plin_phone': n(plin.replaceAll(RegExp(r'\D'), '')),
      'bank_name': n(bankName),
      'bank_account': n(bankAccount),
      'bank_cci': n(bankCci.replaceAll(RegExp(r'\D'), '')),
      'account_holder': n(holder),
      'pay_note': n(note),
      'reminders_enabled': remindersEnabled,
      'reminder_offsets': sorted.isEmpty ? [0] : sorted,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

/// Comportamiento de pago histórico de un cliente (RPC client_payment_stats).
class ClientPayStats {
  const ClientPayStats({
    required this.key,
    required this.name,
    required this.invoices,
    required this.creditInvoices,
    required this.settled,
    required this.avgDaysToPay,
    required this.avgDaysLate,
    required this.maxDaysLate,
    required this.openBalance,
    required this.overdueBalance,
  });

  final String key; // nombre en minúsculas
  final String name;
  final int invoices;
  final int creditInvoices;
  final int settled;
  final double? avgDaysToPay;
  final double? avgDaysLate;
  final int maxDaysLate;
  final double openBalance;
  final double overdueBalance;

  factory ClientPayStats.fromJson(Map<String, dynamic> j) => ClientPayStats(
        key: _s(j['client_key']),
        name: _s(j['client_name']),
        invoices: _num(j['invoices']).toInt(),
        creditInvoices: _num(j['credit_invoices']).toInt(),
        settled: _num(j['settled']).toInt(),
        avgDaysToPay: _numOrNull(j['avg_days_to_pay']),
        avgDaysLate: _numOrNull(j['avg_days_late']),
        maxDaysLate: _num(j['max_days_late']).toInt(),
        openBalance: _num(j['open_balance']),
        overdueBalance: _num(j['overdue_balance']),
      );
}

/// Velocidad de venta de un producto (RPC product_velocity).
class ProductVelocity {
  const ProductVelocity({required this.id, required this.name, required this.stock, required this.reorderPoint, required this.units, required this.perDay});
  final String id;
  final String name;
  final double? stock;
  final double? reorderPoint;
  final double units;
  final double perDay;

  /// Días hasta quedarse sin stock al ritmo actual (null = no se vende o no se controla).
  double? get daysLeft => stock == null || perDay <= 0 ? null : (stock! <= 0 ? 0 : stock! / perDay);
  bool get atRisk => stock != null && (stock! <= (reorderPoint ?? 0) || (daysLeft != null && daysLeft! <= 14));

  factory ProductVelocity.fromJson(Map<String, dynamic> j) => ProductVelocity(
        id: _s(j['product_id']),
        name: _s(j['name']),
        stock: _numOrNull(j['stock']),
        reorderPoint: _numOrNull(j['reorder_point']),
        units: _num(j['units']),
        perDay: _num(j['per_day']),
      );
}

/// Pago registrado con su fecha (para flujo de caja).
class DatedPayment {
  const DatedPayment({required this.amount, required this.paidOn, required this.currency});
  final double amount;
  final String paidOn;
  final String currency;
}

// ───────────────────────── IA ─────────────────────────

class AssistantHighlight {
  const AssistantHighlight(this.label, this.value, this.tone);
  final String label;
  final String value;
  final String tone; // ok | warn | bad | info
}

class AssistantReply {
  AssistantReply({
    required this.intent,
    required this.answer,
    required this.speak,
    required this.highlights,
    required this.suggestions,
    this.draft,
    this.expense,
    this.transcript = '',
  });

  final String intent; // question | invoice | quote | expense | collections | unknown
  final String answer;
  final String speak;
  final List<AssistantHighlight> highlights;
  final List<String> suggestions;
  final InvoiceDraft? draft;
  final Expense? expense;
  final String transcript;

  factory AssistantReply.fromJson(Map<String, dynamic> body, Profile profile) {
    final r = Map<String, dynamic>.from((body['reply'] ?? const {}) as Map);
    InvoiceDraft? draft;
    if (r['invoice'] is Map) {
      final inv = Map<String, dynamic>.from(r['invoice'] as Map);
      draft = InvoiceDraft.fromParse({...inv, 'transcript': body['transcript']}, profile);
    }
    Expense? expense;
    if (r['expense'] is Map) {
      final e = Map<String, dynamic>.from(r['expense'] as Map);
      expense = Expense(
        spentOn: _s(e['date']).isEmpty ? todayIso() : _s(e['date']),
        category: _s(e['category']),
        description: _s(e['description']),
        total: _num(e['amount']),
        supplierName: _s(e['supplier_name']),
        currency: profile.currency.isEmpty ? 'PEN' : profile.currency,
        source: 'voice',
      );
    }
    return AssistantReply(
      intent: _s(r['intent']).isEmpty ? 'unknown' : _s(r['intent']),
      answer: _s(r['answer']),
      speak: _s(r['speak']),
      highlights: ((r['highlights'] ?? []) as List).map((h) {
        final m = Map<String, dynamic>.from(h as Map);
        return AssistantHighlight(_s(m['label']), _s(m['value']), _s(m['tone']));
      }).toList(),
      suggestions: ((r['suggestions'] ?? []) as List).map((e) => e.toString()).toList(),
      draft: draft,
      expense: expense,
      transcript: _s(body['transcript']),
    );
  }
}

/// Comprobante de compra leído por la cámara.
class DocScan {
  DocScan({
    required this.docType,
    required this.supplierName,
    required this.supplierTaxId,
    this.clientName = '',
    this.clientTaxId = '',
    required this.docNumber,
    required this.issueDate,
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.items,
    required this.category,
    required this.confidence,
  });

  final String docType;
  final String supplierName;
  final String supplierTaxId;
  final String clientName;
  final String clientTaxId;
  final String docNumber;
  final String issueDate;
  final String currency;
  final double? subtotal;
  final double? tax;
  final double total;
  final List<LineItem> items;
  final String category;
  final double confidence;

  factory DocScan.fromJson(Map<String, dynamic> j) => DocScan(
        docType: _s(j['doc_type']),
        supplierName: _s(j['supplier_name']),
        supplierTaxId: _s(j['supplier_tax_id']),
        clientName: _s(j['client_name']),
        clientTaxId: _s(j['client_tax_id']),
        docNumber: _s(j['doc_number']),
        issueDate: _s(j['issue_date']),
        currency: _s(j['currency']).isEmpty ? 'PEN' : _s(j['currency']),
        subtotal: _numOrNull(j['subtotal']),
        tax: _numOrNull(j['tax']),
        total: _num(j['total']),
        items: ((j['items'] ?? []) as List).map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        category: _s(j['category']).isEmpty ? 'otros' : _s(j['category']),
        confidence: _num(j['confidence']),
      );
}

/// Constancia de pago (Yape/Plin/banco) leída por la cámara.
class PaymentScan {
  PaymentScan({
    required this.app,
    required this.amount,
    required this.currency,
    required this.payerName,
    required this.operationCode,
    required this.date,
  });

  final String app;
  final double amount;
  final String currency;
  final String payerName;
  final String operationCode;
  final String date;

  factory PaymentScan.fromJson(Map<String, dynamic> j) => PaymentScan(
        app: _s(j['app']),
        amount: _num(j['amount']),
        currency: _s(j['currency']).isEmpty ? 'PEN' : _s(j['currency']),
        payerName: _s(j['payer_name']),
        operationCode: _s(j['operation_code']),
        date: _s(j['date']),
      );
}
