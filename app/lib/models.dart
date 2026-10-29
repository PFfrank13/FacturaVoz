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
    this.dueDate,
    List<LineItem>? items,
  }) : items = items ?? [];

  String clientName;
  String clientTaxId;
  double taxRate;
  String currency;
  String notes;
  String? transcript;

  /// Fecha de vencimiento 'yyyy-MM-dd' si la venta es al crédito; null = al contado.
  String? dueDate;
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
    this.clientEmail = '',
    this.dueDate,
    this.paid = 0,
    required this.items,
    this.fiscalStatus,
    this.fiscalNumber,
    this.docKind,
    this.voided = false,
    this.imported = false,
    this.lockedTotals,
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
  final String clientEmail;
  final String? dueDate; // 'yyyy-MM-dd'
  final double paid; // suma de cobros registrados
  final List<LineItem> items;
  final String? fiscalStatus; // pending | accepted | rejected | error (null = sin comprobante electrónico)
  final String? fiscalNumber; // F001-00000007
  final String? docKind; // factura | boleta | nota_credito | nota_venta (null = se decide al emitir)
  final bool voided; // anulado: no cuenta como venta
  final bool imported; // vino del sistema anterior (no se reenvía a SUNAT)
  final Totals? lockedTotals; // montos tal como venían del archivo importado

  Totals get totals => lockedTotals ?? computeTotals(items, taxRate);
  bool get isCreditNote => docKind == 'nota_credito';

  /// ¿Cuenta como venta? MISMA regla que el servidor (sales_summary): emitido o pagado, no anulado, no rechazado.
  bool get countsAsSale => (status == 'sent' || status == 'paid') && !voided && fiscalStatus != 'rejected';

  /// Total con signo: las notas de crédito restan.
  double get signedTotal => isCreditNote ? -totals.total : totals.total;

  /// Saldo por cobrar (nunca negativo).
  double get balance {
    final b = round2(totals.total - paid);
    return b < 0 ? 0 : b;
  }

  /// ¿Hay algo por cobrar? Solo facturas emitidas, no rechazadas ni ya pagadas.
  bool get receivable => status != 'draft' && status != 'paid' && fiscalStatus != 'rejected' && !voided && !isCreditNote && balance > 0.004;

  /// Vencida: por cobrar y con fecha de vencimiento anterior a [today] ('yyyy-MM-dd').
  bool isOverdue(String today) => receivable && dueDate != null && dueDate!.compareTo(today) < 0;

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
      clientEmail: (client['email'] ?? '') as String,
      dueDate: j['due_date'] as String?,
      paid: j['payments'] is List ? round2((j['payments'] as List).fold<double>(0, (a, e) => a + _num((e as Map)['amount']))) : 0,
      fiscalStatus: fiscal?['status'] as String?,
      fiscalNumber: fiscal == null ? null : fiscalNumberOf(fiscal['series'] as String, (fiscal['correlative'] as num).toInt()),
      items: ((j['invoice_items'] ?? []) as List)
          .map((e) => LineItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      docKind: j['doc_kind'] as String?,
      voided: j['voided_at'] != null,
      imported: j['import_job_id'] != null,
      lockedTotals: j['totals_locked'] == true ? Totals(_num(j['amt_base']), _num(j['amt_tax']), _num(j['amt_total'])) : null,
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

enum RiskLevel { low, medium, high }

class RiskReport {
  const RiskReport(this.level, this.reasons);
  final RiskLevel level;
  final List<String> reasons;
}

/// Revisión automática previa al guardado (reglas fijas, sin red ni IA: instantánea y gratis).
/// Avisa de datos que suelen causar rechazos de SUNAT o errores de tipeo; nunca bloquea.
RiskReport assessRisk({
  required String clientName,
  required String clientTaxId,
  required List<LineItem> items,
  required double taxRate,
}) {
  final reasons = <String>[];
  var level = RiskLevel.low;
  void raise(RiskLevel l, String why) {
    reasons.add(why);
    if (l.index > level.index) level = l;
  }

  final total = computeTotals(items, taxRate).total;
  final doc = clientTaxId.trim();
  final digits = RegExp(r'^\d+$').hasMatch(doc);

  if (total > 5000) raise(RiskLevel.high, 'Monto alto (${total.toStringAsFixed(2)}): confirma que no hay un cero de más.');
  for (final i in items) {
    if (i.description.trim().isNotEmpty && i.unitPrice <= 0) {
      raise(RiskLevel.high, '“${i.description.trim()}” tiene precio 0.');
      break;
    }
  }
  if (doc.isEmpty && total >= 700) {
    raise(RiskLevel.medium, 'Desde S/ 700 SUNAT pide identificar al cliente (DNI o RUC).');
  } else if (doc.isEmpty) {
    raise(RiskLevel.medium, 'Sin DNI/RUC del cliente: solo servirá como boleta a consumidor.');
  }
  if (doc.isNotEmpty && digits && doc.length != 8 && doc.length != 11) {
    raise(RiskLevel.medium, 'El documento no parece DNI (8) ni RUC (11).');
  }
  const generic = {'servicio', 'servicios', 'varios', 'trabajo', 'producto', 'productos', 'item', 'ítem', 'otros', 'cosa'};
  for (final i in items) {
    final d = i.description.trim().toLowerCase();
    if (d.isNotEmpty && (d.length < 4 || generic.contains(d))) {
      raise(RiskLevel.medium, 'Descripción muy genérica (“${i.description.trim()}”): sé más específico.');
      break;
    }
  }
  if (items.any((i) => i.quantity > 1000)) raise(RiskLevel.medium, 'Cantidad inusualmente alta.');
  if (clientName.trim().length < 3) raise(RiskLevel.medium, 'Nombre de cliente muy corto.');
  return RiskReport(level, reasons);
}

/// Empresa (organización) a la que pertenece el usuario.
class Org {
  const Org({required this.id, required this.name, required this.taxId, required this.role});
  final String id;
  final String name;
  final String taxId;
  final String role; // owner | admin | member

  bool get isAdmin => role == 'owner' || role == 'admin';
  String get roleLabel => switch (role) {
        'owner' => 'Propietario',
        'admin' => 'Administrador',
        _ => 'Miembro',
      };
}

class OrgMember {
  const OrgMember({required this.userId, required this.email, required this.role});
  final String userId;
  final String email;
  final String role;
}


/// Cliente tal como lo ve la pantalla "Clientes" (varias filas de la base pueden ser el mismo cliente).
class ClientCard {
  ClientCard({required this.ids, required this.name, required this.taxId, required this.email, required this.address});
  final List<String> ids;
  final String name;
  final String taxId;
  String email;
  String address;
}


/// Producto o servicio del catálogo de la empresa.
class Product {
  Product({required this.id, required this.name, required this.unitPrice, required this.unit, required this.active, this.stock, this.reorderPoint, this.unitCost, this.inStore = true});
  final String id;
  final String name;
  final double unitPrice;
  final String unit; // NIU producto | ZZ servicio
  final bool active;

  /// Stock actual (null = no se controla). Se descuenta solo al emitir una venta con ese nombre.
  final double? stock;
  final double? reorderPoint;
  bool get tracksStock => stock != null;
  bool get lowStock => stock != null && stock! <= (reorderPoint ?? 0);

  /// Costo unitario (sin IGV), para calcular margen y precio sugerido. null = no registrado.
  final double? unitCost;

  /// Visible en la tienda en línea.
  final bool inStore;

  /// Margen sobre el precio (0..1) o null si no hay costo.
  double? get margin => unitCost == null || unitPrice <= 0 ? null : (unitPrice - unitCost!) / unitPrice;

  bool get isService => unit == 'ZZ';

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        unitPrice: _num(j['unit_price']),
        unit: (j['unit'] ?? 'NIU') as String,
        active: j['active'] != false,
        stock: j['stock'] == null ? null : _num(j['stock']),
        reorderPoint: j['reorder_point'] == null ? null : _num(j['reorder_point']),
        unitCost: j['unit_cost'] == null ? null : _num(j['unit_cost']),
        inStore: j['in_store'] != false,
      );
}


String todayIso([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

const paymentMethods = {
  'efectivo': 'Efectivo',
  'yape': 'Yape',
  'plin': 'Plin',
  'transferencia': 'Transferencia',
  'tarjeta': 'Tarjeta',
  'mercadopago': 'Mercado Pago',
  'otro': 'Otro',
};

/// Cobro registrado sobre una factura.
class Payment {
  Payment({required this.id, required this.amount, required this.paidOn, required this.method, required this.note});
  final String id;
  final double amount;
  final String paidOn; // yyyy-MM-dd
  final String method;
  final String note;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: j['id'] as String,
        amount: _num(j['amount']),
        paidOn: (j['paid_on'] ?? '') as String,
        method: (j['method'] ?? 'otro') as String,
        note: (j['note'] ?? '') as String,
      );
}
