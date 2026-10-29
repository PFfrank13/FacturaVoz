// Impresión de tickets térmicos 58/80 mm (Fase 4):
//   · Bluetooth (Android: prioridad; iPhone: impresoras BLE compatibles) con print_bluetooth_thermal.
//   · Red Wi‑Fi/LAN (IP:9100) en Android/iOS.
//   · Ticket en PDF de rollo (57/80 mm) en TODAS las plataformas (web, USB, cualquier impresora): siempre funciona.
// El logo del EMISOR se imprime como imagen monocroma (difuminado) en la cabecera; el QR SUNAT con corrección Q.
// Honestidad: impresoras USB conectadas al teléfono y la impresión directa desde la web no están soportadas (usa PDF).
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../logic/escpos.dart';
import '../../models.dart';
import 'net_print_stub.dart' if (dart.library.io) 'net_print_io.dart';

// ═════════════════════════ Configuración guardada en el teléfono ═════════════════════════
class PrinterConfig {
  const PrinterConfig({this.kind = 'pdf', this.address = '', this.name = '', this.width = 80, this.nativeQr = true, this.openDrawer = false});
  final String kind; // pdf | bt | net
  final String address; // MAC (bt) o IP[:puerto] (net)
  final String name;
  final int width; // 58 | 80
  final bool nativeQr; // QR por comando de la impresora (si no, como imagen)
  final bool openDrawer;

  Map<String, dynamic> toJson() => {'kind': kind, 'address': address, 'name': name, 'width': width, 'nativeQr': nativeQr, 'openDrawer': openDrawer};
  factory PrinterConfig.fromJson(Map<String, dynamic> j) => PrinterConfig(
        kind: (j['kind'] ?? 'pdf') as String,
        address: (j['address'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        width: (j['width'] as num?)?.toInt() == 58 ? 58 : 80,
        nativeQr: j['nativeQr'] != false,
        openDrawer: j['openDrawer'] == true,
      );

  PrinterConfig copyWith({String? kind, String? address, String? name, int? width, bool? nativeQr, bool? openDrawer}) => PrinterConfig(
        kind: kind ?? this.kind,
        address: address ?? this.address,
        name: name ?? this.name,
        width: width ?? this.width,
        nativeQr: nativeQr ?? this.nativeQr,
        openDrawer: openDrawer ?? this.openDrawer,
      );

  String get label => switch (kind) {
        'bt' => 'Bluetooth · ${name.isEmpty ? address : name} · $width mm',
        'net' => 'Red · $address · $width mm',
        _ => 'Ticket en PDF · $width mm',
      };
}

class PrinterStore {
  static const _key = 'fv_printer_v2';
  static const _s = FlutterSecureStorage();

  static Future<PrinterConfig> load({int? orgWidth}) async {
    try {
      final raw = await _s.read(key: _key);
      if (raw != null && raw.isNotEmpty) return PrinterConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
    return PrinterConfig(width: orgWidth == 58 ? 58 : 80);
  }

  static Future<void> save(PrinterConfig c) async {
    try {
      await _s.write(key: _key, value: jsonEncode(c.toJson()));
    } catch (_) {}
  }
}

/// Qué se puede usar en esta plataforma.
bool get bluetoothSupported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
bool get networkSupported => !kIsWeb;

// ═════════════════════════ Datos del ticket ═════════════════════════
class TicketLine {
  const TicketLine(this.qty, this.description, this.unit, this.amount);
  final double qty;
  final String description;
  final double unit;
  final double amount;
}

class TicketData {
  const TicketData({
    required this.issuerName,
    required this.issuerRuc,
    required this.issuerAddress,
    required this.title,
    required this.number,
    required this.date,
    required this.clientName,
    required this.clientDoc,
    required this.lines,
    required this.totals,
    required this.currency,
    this.legend = '',
    this.payment = '',
    this.qr,
    this.hash = '',
    this.footer = '',
    this.warning = '',
  });

  final String issuerName, issuerRuc, issuerAddress, title, number, date, clientName, clientDoc, currency, legend, payment, hash, footer, warning;
  final List<TicketLine> lines;
  final List<(String, double, bool)> totals;
  final String? qr;
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Ticket del comprobante electrónico: solo con lo que se envió a SUNAT (mismo contenido que el PDF A4).
TicketData ticketFromFiscal(FiscalDoc f) {
  final p = f.payload;
  final company = _m(p['company']);
  final addr = _m(company['address']);
  final client = _m(p['client']);
  final cur = (p['tipoMoneda'] ?? 'PEN') as String;
  final iso = ((p['fechaEmision'] ?? '') as String).split('T').first;
  final t = f.totals;
  final igv = _d(t['igv']);
  final total = _d(t['total']);
  final tipoDoc = (client['tipoDoc'] ?? '-') as String;
  final fp = _m(p['formaPago']);
  final cuotas = ((p['cuotas'] ?? const []) as List).map(_m).toList();
  return TicketData(
    issuerName: (company['razonSocial'] ?? '') as String,
    issuerRuc: (company['ruc'] ?? '') as String,
    issuerAddress: [addr['direccion'], addr['distrito']].where((e) => e != null && '$e'.isNotEmpty && '$e' != '-').join(' - '),
    title: f.typeName,
    number: f.number,
    date: displayDate(iso),
    clientName: (client['rznSocial'] ?? '') as String,
    clientDoc: tipoDoc == '-' ? '' : '${tipoDoc == '6' ? 'RUC' : (tipoDoc == '1' ? 'DNI' : 'Doc.')} ${client['numDoc'] ?? ''}',
    currency: cur,
    lines: ((p['details'] ?? const []) as List).map(_m).map((d) => TicketLine(_d(d['cantidad']), (d['descripcion'] ?? '') as String, _d(d['mtoPrecioUnitario']), _d(d['mtoPrecioUnitario']) * _d(d['cantidad']))).toList(),
    totals: [
      if (_d(t['gravadas']) > 0) ('Op. gravada', _d(t['gravadas']), false),
      if (_d(t['exoneradas']) > 0) ('Op. exonerada', _d(t['exoneradas']), false),
      if (_d(t['inafectas']) > 0) ('Op. inafecta', _d(t['inafectas']), false),
      ('IGV', igv, false),
      ('TOTAL', total, true),
    ],
    legend: f.legend,
    payment: fp['tipo'] == 'Credito' ? 'Crédito${cuotas.isNotEmpty ? ' · vence ${displayDate('${cuotas.first['fechaPago'] ?? ''}'.split('T').first)}' : ''}' : 'Contado',
    qr: [company['ruc'], f.docType, f.series, f.correlative.toString().padLeft(8, '0'), igv.toStringAsFixed(2), total.toStringAsFixed(2), iso, tipoDoc, client['numDoc'] ?? '', f.hash].join('|'), // 10 campos; el último es el valor resumen
    hash: f.hash,
    footer: 'Representación impresa de la ${f.typeName.toLowerCase()}. Consulte su validez en www.sunat.gob.pe',
    warning: f.env == 'beta' ? 'PRUEBA (SUNAT BETA) - SIN VALIDEZ' : (f.status == 'accepted' ? '' : 'AÚN NO ACEPTADO POR SUNAT'),
  );
}

/// Nota de venta interna (sin comprobante electrónico): se marca SIN VALIDEZ TRIBUTARIA.
TicketData ticketFromInternal(InvoiceRecord inv, Profile issuer) {
  final t = inv.totals;
  return TicketData(
    issuerName: issuer.tradeName.isNotEmpty ? issuer.tradeName : issuer.businessName,
    issuerRuc: issuer.taxId,
    issuerAddress: issuer.address,
    title: 'NOTA DE VENTA',
    number: inv.number,
    date: displayDate(inv.issueDate),
    clientName: inv.clientName,
    clientDoc: inv.clientTaxId,
    currency: inv.currency,
    lines: [for (final i in inv.items) TicketLine(i.quantity, i.description, round2(i.unitPrice * (1 + inv.taxRate / 100)), round2(i.amount * (1 + inv.taxRate / 100)))],
    totals: [('Subtotal', t.subtotal, false), (issuer.taxLabel.isEmpty ? 'IGV' : issuer.taxLabel, t.tax, false), ('TOTAL', t.total, true)],
    footer: 'Documento interno. No es comprobante de pago.',
    warning: 'SIN VALIDEZ TRIBUTARIA',
  );
}

// ═════════════════════════ Imagen del logo y del QR ═════════════════════════
/// Logo (PNG/JPG) → monocromo del ancho dado (en puntos de la impresora).
Future<Raster?> logoRaster(Uint8List? bytes, int widthDots) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: widthDots);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return rasterize(data.buffer.asUint8List(), img.width, img.height, widthDots);
  } catch (_) {
    return null; // logo dañado: se imprime sin logo
  }
}

/// QR (nivel Q) como imagen 1 bit, para impresoras que no entienden el comando QR nativo.
Raster qrRaster(String data, {int sizeDots = 240}) {
  final px = (sizeDots ~/ 8) * 8;
  final els = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.quartile).make(data, width: px.toDouble(), height: px.toDouble());
  final out = Uint8List((px ~/ 8) * px);
  for (final e in els) {
    if (e is! BarcodeBar || !e.black) continue;
    final x0 = e.left.floor(), y0 = e.top.floor();
    final x1 = (e.left + e.width).ceil().clamp(0, px), y1 = (e.top + e.height).ceil().clamp(0, px);
    for (var y = y0.clamp(0, px); y < y1; y++) {
      for (var x = x0.clamp(0, px); x < x1; x++) {
        out[y * (px ~/ 8) + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return Raster(px, px, out);
}

// ═════════════════════════ ESC/POS ═════════════════════════
Uint8List buildEscPosTicket(TicketData d, {required int width, Raster? logo, bool nativeQr = true, bool openDrawer = false}) {
  final paper = Paper.of(width);
  final e = EscPos(paper)..init();
  String m(double v) => money(v, d.currency);
  if (logo != null) {
    e.image(logo);
    e.feed();
  }
  e.text(d.issuerName, a: 1, b: true);
  if (d.issuerRuc.isNotEmpty) e.text('RUC ${d.issuerRuc}', a: 1);
  if (d.issuerAddress.isNotEmpty) e.wrap(d.issuerAddress, a: 1);
  e.line();
  if (d.warning.isNotEmpty) e.text('*** ${d.warning} ***', a: 1, b: true);
  e.wrap(d.title, a: 1, b: true);
  e.text(d.number, a: 1, b: true, big: width == 80);
  e.line();
  e.text('Fecha: ${d.date}');
  if (d.clientName.isNotEmpty && d.clientName != '—') e.wrap('Cliente: ${d.clientName}');
  if (d.clientDoc.isNotEmpty) e.text(d.clientDoc);
  e.line();
  for (final l in d.lines) {
    e.wrap(l.description);
    e.pair('  ${qtyText(l.qty)} x ${m(l.unit)}', m(l.amount));
  }
  e.line();
  for (final t in d.totals) {
    e.pair(t.$1, m(t.$2), b: t.$3);
  }
  if (d.legend.isNotEmpty) {
    e.feed();
    e.wrap(d.legend.startsWith('SON') ? d.legend : 'SON: ${d.legend}');
  }
  if (d.payment.isNotEmpty) e.text('Forma de pago: ${d.payment}');
  if (d.qr != null) {
    e.feed();
    if (nativeQr) {
      e.qr(d.qr!, module: width == 58 ? 5 : 6);
    } else {
      e.image(qrRaster(d.qr!, sizeDots: width == 58 ? 216 : 264));
    }
  }
  if (d.hash.isNotEmpty) e.wrap('Valor resumen: ${d.hash}', a: 1);
  if (d.footer.isNotEmpty) e.wrap(d.footer, a: 1);
  e.text('¡Gracias por su compra!', a: 1);
  e.feed(3);
  e.cut();
  if (openDrawer) e.openDrawer();
  return e.bytes();
}

// ═════════════════════════ PDF de rollo (siempre disponible) ═════════════════════════
Future<Uint8List> buildTicketPdf(TicketData d, {required int width, Uint8List? logo}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final fmt = width == 58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold), title: d.number);
  pw.MemoryImage? img0;
  try {
    if (logo != null && logo.isNotEmpty) img0 = pw.MemoryImage(logo);
  } catch (_) {}
  final img = img0;
  String m(double v) => money(v, d.currency);
  final fs = width == 58 ? 7.0 : 8.0;
  pw.TextStyle st({bool b = false, double? size}) => pw.TextStyle(fontSize: size ?? fs, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal);
  doc.addPage(pw.Page(
    pageFormat: fmt.copyWith(marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 8),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (img != null) pw.Center(child: pw.Image(img, height: 48, fit: pw.BoxFit.contain)),
      pw.Text(d.issuerName, textAlign: pw.TextAlign.center, style: st(b: true, size: fs + 1.5)),
      if (d.issuerRuc.isNotEmpty) pw.Text('RUC ${d.issuerRuc}', textAlign: pw.TextAlign.center, style: st()),
      if (d.issuerAddress.isNotEmpty) pw.Text(d.issuerAddress, textAlign: pw.TextAlign.center, style: st()),
      pw.Divider(thickness: 0.5),
      if (d.warning.isNotEmpty) pw.Text('*** ${d.warning} ***', textAlign: pw.TextAlign.center, style: st(b: true)),
      pw.Text(d.title, textAlign: pw.TextAlign.center, style: st(b: true)),
      pw.Text(d.number, textAlign: pw.TextAlign.center, style: st(b: true, size: fs + 2)),
      pw.Divider(thickness: 0.5),
      pw.Text('Fecha: ${d.date}', style: st()),
      if (d.clientName.isNotEmpty && d.clientName != '—') pw.Text('Cliente: ${d.clientName}', style: st()),
      if (d.clientDoc.isNotEmpty) pw.Text(d.clientDoc, style: st()),
      pw.Divider(thickness: 0.5),
      for (final l in d.lines) ...[
        pw.Text(l.description, style: st()),
        pw.Row(children: [pw.Expanded(child: pw.Text('  ${qtyText(l.qty)} x ${m(l.unit)}', style: st())), pw.Text(m(l.amount), style: st())]),
      ],
      pw.Divider(thickness: 0.5),
      for (final t in d.totals) pw.Row(children: [pw.Expanded(child: pw.Text(t.$1, style: st(b: t.$3))), pw.Text(m(t.$2), style: st(b: t.$3))]),
      if (d.legend.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(d.legend.startsWith('SON') ? d.legend : 'SON: ${d.legend}', style: st())),
      if (d.payment.isNotEmpty) pw.Text('Forma de pago: ${d.payment}', style: st()),
      if (d.qr != null)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.quartile), data: d.qr!, width: 90, height: 90)),
        ),
      if (d.hash.isNotEmpty) pw.Text('Valor resumen: ${d.hash}', textAlign: pw.TextAlign.center, style: st(size: fs - 1)),
      if (d.footer.isNotEmpty) pw.Text(d.footer, textAlign: pw.TextAlign.center, style: st(size: fs - 1)),
      pw.SizedBox(height: 4),
      pw.Text('¡Gracias por su compra!', textAlign: pw.TextAlign.center, style: st()),
    ]),
  ));
  return doc.save();
}

// ═════════════════════════ Envío a la impresora ═════════════════════════
class BtDevice {
  const BtDevice(this.name, this.mac);
  final String name;
  final String mac;
}

/// Android 12+: pide el permiso "Dispositivos cercanos" antes de usar el Bluetooth.
Future<void> _ensureBtPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
  if (r.values.any((s) => s.isPermanentlyDenied)) {
    throw StateError('Activa el permiso "Dispositivos cercanos" para FacturaVoz en Ajustes del teléfono.');
  }
}

Future<List<BtDevice>> pairedPrinters() async {
  if (!bluetoothSupported) return const [];
  await _ensureBtPermission();
  if (!await PrintBluetoothThermal.bluetoothEnabled) throw StateError('Enciende el Bluetooth del teléfono.');
  final list = await PrintBluetoothThermal.pairedBluetooths;
  return [for (final b in list) BtDevice(b.name, b.macAdress)];
}

/// Envía los bytes ESC/POS. Lanza un error con mensaje claro si algo falla (la pantalla ofrece el PDF).
Future<void> sendEscPos(PrinterConfig c, Uint8List bytes) async {
  switch (c.kind) {
    case 'bt':
      if (!bluetoothSupported) throw StateError('Bluetooth no disponible aquí. Usa "Ticket en PDF".');
      await _ensureBtPermission();
      if (!await PrintBluetoothThermal.bluetoothEnabled) throw StateError('Enciende el Bluetooth del teléfono.');
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) connected = await PrintBluetoothThermal.connect(macPrinterAddress: c.address);
      if (!connected) throw StateError('No se pudo conectar con la impresora ${c.name}. ¿Está encendida y emparejada?');
      final ok = await PrintBluetoothThermal.writeBytes(bytes.toList());
      if (!ok) throw StateError('La impresora no recibió el ticket. Inténtalo de nuevo.');
    case 'net':
      if (!networkSupported) throw StateError('La impresión por red no está disponible en la web.');
      final parts = c.address.split(':');
      await sendToNetworkPrinter(parts.first, parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100, bytes);
    default:
      throw StateError('Elige una impresora Bluetooth o de red, o usa el ticket en PDF.');
  }
}
