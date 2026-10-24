import 'package:intl/intl.dart';

double round2(double n) => (n * 100).round() / 100;

double _num(dynamic v) => v is num ? v.toDouble() : double.parse(v.toString());

/// Interpreta "12,5" o "12.5". Devuelve null si no es un número válido.
double? parseDecimal(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}

const currencySymbols = <String, String>{
  'PEN': 'S/',
  'USD': r'US$',
  'EUR': '€',
  'MXN': r'MX$',
  'COP': r'COL$',
  'CLP': r'CLP$',
  'ARS': r'ARS$',
  'BOB': 'Bs',
};

String money(double v, String currency) {
  final sym = currencySymbols[currency] ?? currency;
  if (currency == 'EUR') {
    return '${NumberFormat('#,##0.00', 'es').format(v)} $sym';
  }
  return '$sym ${NumberFormat('#,##0.00', 'en_US').format(v)}';
}

String qtyText(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

/// 'yyyy-MM-dd' -> 'dd/MM/yyyy'
String displayDate(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

class LineItem {
  LineItem({this.description = '', this.quantity = 1, this.unitPrice = 0});

  String description;
  double quantity;
  double unitPrice;

  factory LineItem.fromJson(Map<String, dynamic> j) => LineItem(
        description: (j['description'] ?? '') as String,
        quantity: _num(j['quantity']),
        unitPrice: _num(j['unit_price']),
      );

  Map<String, dynamic> toJson() => {
        'description': description.trim(),
        'quantity': round2(quantity),
        'unit_price': round2(unitPrice),
      };

  /// Mismo redondeo que se guarda en la base de datos (2 decimales).
  double get amount => round2(round2(quantity) * round2(unitPrice));
}

class Totals {
  const Totals(this.subtotal, this.tax, this.total);
  final double subtotal;
  final double tax;
  final double total;
}

/// El impuesto se calcula POR LÍNEA y se suma (así lo valida SUNAT y coincide con el servidor).
Totals computeTotals(Iterable<LineItem> items, double taxRate) {
  final lines = items.toList();
  final subtotal = round2(lines.fold<double>(0, (s, i) => s + i.amount));
  final tax = round2(lines.fold<double>(0, (s, i) => s + round2(i.amount * taxRate / 100)));
  return Totals(subtotal, tax, round2(subtotal + tax));
}

class Profile {
  Profile({
    this.businessName = '',
    this.taxId = '',
    this.address = '',
    this.currency = '',
    this.taxLabel = '',
    this.taxRate,
    this.tradeName = '',
    this.ubigeo = '',
    this.department = '',
    this.province = '',
    this.district = '',
    this.seriesFactura = 'F001',
    this.seriesBoleta = 'B001',
  });

  String businessName;
  String taxId;
  String address;
  String currency;
  String taxLabel;
  double? taxRate;
  String tradeName;
  String ubigeo;
  String department;
  String province;
  String district;
  String seriesFactura;
  String seriesBoleta;

  /// Datos mínimos para emitir comprobantes electrónicos (domicilio fiscal completo y RUC).
  bool get isFiscalReady =>
      RegExp(r'^\d{11}$').hasMatch(taxId.trim()) &&
      RegExp(r'^\d{6}$').hasMatch(ubigeo.trim()) &&
      department.trim().isNotEmpty &&
      province.trim().isNotEmpty &&
      district.trim().isNotEmpty &&
      address.trim().isNotEmpty;

  bool get isComplete =>
      businessName.trim().isNotEmpty &&
      currency.isNotEmpty &&
      taxLabel.trim().isNotEmpty &&
      taxRate != null;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        businessName: (j['business_name'] ?? '') as String,
        taxId: (j['tax_id'] ?? '') as String,
        address: (j['address'] ?? '') as String,
        currency: (j['currency'] ?? '') as String,
        taxLabel: (j['tax_label'] ?? '') as String,
        taxRate: j['default_tax_rate'] == null ? null : _num(j['default_tax_rate']),
        tradeName: (j['trade_name'] ?? '') as String,
        ubigeo: (j['ubigeo'] ?? '') as String,
        department: (j['department'] ?? '') as String,
        province: (j['province'] ?? '') as String,
        district: (j['district'] ?? '') as String,
        seriesFactura: (j['series_factura'] ?? 'F001') as String,
        seriesBoleta: (j['series_boleta'] ?? 'B001') as String,
      );

  Map<String, dynamic> toJson() => {
        'trade_name': tradeName.trim().isEmpty ? null : tradeName.trim(),
        'ubigeo': ubigeo.trim().isEmpty ? null : ubigeo.trim(),
        'department': department.trim().isEmpty ? null : department.trim(),
        'province': province.trim().isEmpty ? null : province.trim(),
        'district': district.trim().isEmpty ? null : district.trim(),
        'series_factura': seriesFactura.trim().toUpperCase(),
        'series_boleta': seriesBoleta.trim().toUpperCase(),
        'business_name': businessName.trim(),
        'tax_id': taxId.trim().isEmpty ? null : taxId.trim(),
        'address': address.trim().isEmpty ? null : address.trim(),
        'currency': currency,
        'tax_label': taxLabel.trim(),
        'default_tax_rate': taxRate == null ? null : round2(taxRate!),
      };
}

/// Datos de una factura todavía no guardada (dictada o manual).
class InvoiceDraft {
  InvoiceDraft({
    this.clientName = '',
    this.clientTaxId = '',
    required this.taxRate,
    required this.currency,
    this.notes = '',
    this.transcript,
    List<LineItem>? items,
  }) : items = items ?? [];

  String clientName;
  String clientTaxId;
  double taxRate;
  String currency;
  String notes;
  String? transcript;
  List<LineItem> items;

  /// Respuesta de POST /api/parse -> {"invoice": {...}}
  factory InvoiceDraft.fromParse(Map<String, dynamic> inv, Profile profile) => InvoiceDraft(
        clientName: (inv['client_name'] ?? '') as String,
        taxRate: inv['tax_rate'] == null ? (profile.taxRate ?? 0) : _num(inv['tax_rate']),
        currency: profile.currency,
        notes: (inv['notes'] ?? '') as String,
        transcript: inv['transcript'] as String?,
        items: ((inv['items'] ?? []) as List)
            .map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class InvoiceRecord {
  InvoiceRecord({
    required this.id,
    required this.number,
    required this.issueDate,
    required this.status,
    required this.currency,
    required this.taxRate,
    required this.notes,
    required this.clientName,
    required this.clientTaxId,
    required this.clientDocType,
    required this.items,
    this.fiscalStatus,
    this.fiscalNumber,
  });

  final String id;
  final String number;
  final String issueDate;
  final String status; // draft | sent | paid
  final String currency;
  final double taxRate;
  final String notes;
  final String clientName;
  final String clientTaxId;
  final String clientDocType;
  final List<LineItem> items;
  final String? fiscalStatus; // pending | accepted | rejected | error (null = sin comprobante electrónico)
  final String? fiscalNumber; // F001-00000007

  Totals get totals => computeTotals(items, taxRate);

  factory InvoiceRecord.fromJson(Map<String, dynamic> j) {
    final client = j['clients'] is Map ? Map<String, dynamic>.from(j['clients'] as Map) : <String, dynamic>{};
    final fd = j['fiscal_documents'];
    final fiscal = fd is Map ? Map<String, dynamic>.from(fd) : (fd is List && fd.isNotEmpty ? Map<String, dynamic>.from(fd.first as Map) : null);
    return InvoiceRecord(
      id: j['id'] as String,
      number: j['number'] as String,
      issueDate: j['issue_date'] as String,
      status: j['status'] as String,
      currency: (j['currency'] ?? 'EUR') as String,
      taxRate: _num(j['tax_rate']),
      notes: (j['notes'] ?? '') as String,
      clientName: (client['name'] ?? '—') as String,
      clientTaxId: (client['tax_id'] ?? '') as String,
      clientDocType: (client['doc_type'] ?? '') as String,
      fiscalStatus: fiscal?['status'] as String?,
      fiscalNumber: fiscal == null ? null : fiscalNumberOf(fiscal['series'] as String, (fiscal['correlative'] as num).toInt()),
      items: ((j['invoice_items'] ?? []) as List)
          .map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

String statusLabel(String s) => switch (s) {
      'draft' => 'Borrador',
      'sent' => 'Enviada',
      'paid' => 'Pagada',
      _ => s,
    };

String fiscalNumberOf(String series, int correlative) => '$series-${correlative.toString().padLeft(8, '0')}';

String fiscalStatusLabel(String s) => switch (s) {
      'accepted' => 'Aceptada por SUNAT',
      'rejected' => 'Rechazada por SUNAT',
      'pending' => 'Pendiente de envío',
      'error' => 'Sin respuesta de SUNAT',
      _ => s,
    };

/// Comprobante electrónico (lo escribe solo el servidor; la app únicamente lo lee).
class FiscalDoc {
  FiscalDoc({
    required this.docType,
    required this.series,
    required this.correlative,
    required this.env,
    required this.status,
    required this.legend,
    required this.sunatCode,
    required this.sunatMessage,
    required this.hash,
    required this.payload,
    required this.totals,
  });

  final String docType; // 01 factura | 03 boleta
  final String series;
  final int correlative;
  final String env; // beta | prod
  final String status;
  final String legend;
  final String sunatCode;
  final String sunatMessage;
  final String hash;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> totals;

  String get number => fiscalNumberOf(series, correlative);
  String get typeName => switch (docType) {
        '01' => 'FACTURA ELECTRÓNICA',
        '07' => 'NOTA DE CRÉDITO ELECTRÓNICA',
        _ => 'BOLETA DE VENTA ELECTRÓNICA',
      };
  bool get isCreditNote => docType == '07';

  factory FiscalDoc.fromJson(Map<String, dynamic> j) => FiscalDoc(
        docType: j['doc_type'] as String,
        series: j['series'] as String,
        correlative: (j['correlative'] as num).toInt(),
        env: j['env'] as String,
        status: j['status'] as String,
        legend: (j['legend'] ?? '') as String,
        sunatCode: (j['sunat_code'] ?? '') as String,
        sunatMessage: (j['sunat_message'] ?? '') as String,
        hash: (j['hash'] ?? '') as String,
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        totals: Map<String, dynamic>.from(j['totals'] as Map),
      );
}

/// La nota de crédito se maneja con el mismo modelo que un comprobante (docType '07').
/// [legend] es la leyenda en letras del comprobante original (los importes son idénticos).
FiscalDoc fiscalNoteFromJson(Map<String, dynamic> j, String legend) => FiscalDoc(
      docType: '07',
      series: j['series'] as String,
      correlative: (j['correlative'] as num).toInt(),
      env: j['env'] as String,
      status: j['status'] as String,
      legend: legend,
      sunatCode: (j['sunat_code'] ?? '') as String,
      sunatMessage: (j['sunat_message'] ?? '') as String,
      hash: (j['hash'] ?? '') as String,
      payload: Map<String, dynamic>.from(j['payload'] as Map),
      totals: Map<String, dynamic>.from(j['totals'] as Map),
    );

class FiscalCompany {
  FiscalCompany({required this.ruc, required this.env});
  final String ruc;
  final String env;
}
