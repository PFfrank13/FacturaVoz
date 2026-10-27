import 'models.dart';

double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? _numOrNull(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
String _s(dynamic v) => (v ?? '').toString();

/// Frecuencia de compra de un cliente (RPC client_activity).
class ClientActivity {
  const ClientActivity({
    required this.key,
    required this.name,
    required this.email,
    required this.purchases,
    required this.total,
    required this.firstPurchase,
    required this.lastPurchase,
    required this.avgGap,
    required this.daysSince,
  });

  final String key;
  final String name;
  final String email;
  final int purchases;
  final double total;
  final String firstPurchase;
  final String lastPurchase;

  /// Cada cuántos días suele comprar (null si compró una sola vez).
  final double? avgGap;
  final int daysSince;

  double get avgTicket => purchases == 0 ? 0 : round2(total / purchases);

  factory ClientActivity.fromJson(Map<String, dynamic> j) => ClientActivity(
        key: _s(j['client_key']),
        name: _s(j['client_name']),
        email: _s(j['client_email']),
        purchases: _num(j['purchases']).toInt(),
        total: _num(j['total']),
        firstPurchase: _s(j['first_purchase']),
        lastPurchase: _s(j['last_purchase']),
        avgGap: _numOrNull(j['avg_gap']),
        daysSince: _num(j['days_since']).toInt(),
      );
}

/// Plantilla de facturación recurrente.
class RecurringTemplate {
  RecurringTemplate({
    this.id,
    required this.clientName,
    this.clientTaxId = '',
    required this.items,
    required this.taxRate,
    required this.currency,
    this.notes = '',
    required this.dayOfMonth,
    this.dueDays = 0,
    required this.nextRun,
    this.active = true,
    this.runs = 0,
    this.lastError = '',
  });

  final String? id;
  String clientName;
  String clientTaxId;
  List<LineItem> items;
  double taxRate;
  String currency;
  String notes;
  int dayOfMonth;
  int dueDays;
  String nextRun; // yyyy-MM-dd
  bool active;
  final int runs;
  final String lastError;

  Totals get totals => computeTotals(items, taxRate);

  factory RecurringTemplate.fromJson(Map<String, dynamic> j) => RecurringTemplate(
        id: j['id'] as String?,
        clientName: _s(j['client_name']),
        clientTaxId: _s(j['client_tax_id']),
        items: ((j['items'] ?? []) as List).map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        taxRate: _num(j['tax_rate']),
        currency: _s(j['currency']).isEmpty ? 'PEN' : _s(j['currency']),
        notes: _s(j['notes']),
        dayOfMonth: _num(j['day_of_month']).toInt(),
        dueDays: _num(j['due_days']).toInt(),
        nextRun: _s(j['next_run']),
        active: j['active'] != false,
        runs: _num(j['runs']).toInt(),
        lastError: _s(j['last_error']),
      );

  Map<String, dynamic> toRow() => {
        'client_name': clientName.trim(),
        'client_tax_id': clientTaxId.trim().isEmpty ? null : clientTaxId.trim(),
        'items': items.map((i) => i.toJson()).toList(),
        'tax_rate': round2(taxRate),
        'currency': currency,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'day_of_month': dayOfMonth,
        'due_days': dueDays,
        'next_run': nextRun,
        'active': active,
      };
}

/// Tienda en línea de la empresa.
class StoreSettings {
  StoreSettings({this.slug = '', this.enabled = false, this.headline = '', this.whatsapp = '', this.exists = false});
  String slug;
  bool enabled;
  String headline;
  String whatsapp;
  final bool exists;

  factory StoreSettings.fromJson(Map<String, dynamic> j) => StoreSettings(
        slug: _s(j['slug']),
        enabled: j['enabled'] == true,
        headline: _s(j['headline']),
        whatsapp: _s(j['whatsapp']),
        exists: true,
      );
}
