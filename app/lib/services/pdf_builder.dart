import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';

const _ink = PdfColor.fromInt(0xFF111827);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _brand = PdfColor.fromInt(0xFF1E3A8A);
const _line = PdfColor.fromInt(0xFFD1D5DB);
const _soft = PdfColor.fromInt(0xFFF3F4F6);

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String _docLabel(String t) => switch (t) {
      '6' => 'RUC',
      '1' => 'DNI',
      '4' => 'C. EXTRANJERÍA',
      '7' => 'PASAPORTE',
      _ => 'DOC.',
    };

/// Marca del emisor para el PDF (v2.0): logo, plantilla y color. Todo opcional.
class PdfBrand {
  const PdfBrand({this.logo, this.template = 'clasico', this.color});
  final Uint8List? logo;
  final String template; // clasico | moderno | minimal
  final int? color; // 0xFFRRGGBB

  static int? parseHex(String? hex) {
    final h = (hex ?? '').replaceAll('#', '');
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(h)) return null;
    return int.parse('FF$h', radix: 16);
  }
}

/// PDF A4 generado en el dispositivo.
/// - Con [fiscal]: representación impresa del comprobante electrónico (formato SUNAT, con QR y hash),
///   construida SOLO con el contenido enviado a SUNAT.
/// - Sin [fiscal]: nota de venta interna, marcada claramente como SIN VALIDEZ TRIBUTARIA.
Future<Uint8List> buildInvoicePdf(InvoiceRecord inv, Profile issuer, {FiscalDoc? fiscal, PdfBrand brand = const PdfBrand()}) async {
  final minimal = brand.template == 'minimal';
  final modern = brand.template == 'moderno';
  final accent = brand.color != null ? PdfColor.fromInt(brand.color!) : (minimal ? _ink : _brand);
  pw.MemoryImage? logo;
  if (brand.logo != null && brand.logo!.isNotEmpty) {
    try {
      logo = pw.MemoryImage(brand.logo!);
    } catch (_) {
      logo = null; // un logo dañado nunca impide generar el comprobante
    }
  }
  final logoImg = logo; // copia final: se usa dentro del constructor de páginas
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(
    title: fiscal?.number ?? inv.number,
    author: issuer.businessName,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  final view = fiscal != null ? _fiscalView(fiscal) : _internalView(inv, issuer);

  pw.TextStyle st(double size, {bool b = false, PdfColor color = _ink}) =>
      pw.TextStyle(fontSize: size, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);

  pw.Widget banner(String text, PdfColor color) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(3)),
        child: pw.Text(text, textAlign: pw.TextAlign.center, style: st(8.5, b: true, color: PdfColors.white)),
      );

  pw.Widget totalRow(String k, String v, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: st(strong ? 10.5 : 9, b: strong, color: strong ? _ink : _muted))),
          pw.Text(v, style: st(strong ? 11 : 9.5, b: strong)),
        ]),
      );

  pw.Widget cell(String t, {bool right = false, bool head = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
        child: pw.Text(t, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: st(head ? 8.5 : 9, b: head, color: head ? PdfColors.white : _ink)),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 34, 36, 34),
      footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(view.footerNote, style: st(7, color: _muted)),
        pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: st(7, color: _muted)),
      ]),
      build: (c) => [
        for (final b in view.banners) banner(b.$1, b.$2),
        // ---- Cabecera: emisor + recuadro del comprobante
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logoImg != null) ...[
            pw.Container(width: 70, height: 60, alignment: pw.Alignment.topLeft, child: pw.Image(logoImg, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(view.issuerName, style: st(15, b: true, color: accent)),
              if (view.issuerTrade.isNotEmpty && view.issuerTrade != view.issuerName) pw.Text(view.issuerTrade, style: st(9.5)),
              pw.SizedBox(height: 3),
              for (final l in view.issuerLines) pw.Text(l, style: st(8.5, color: _muted)),
            ]),
          ),
          pw.SizedBox(width: 16),
          pw.Container(
            width: 190,
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: pw.BoxDecoration(
              color: modern ? accent : null,
              border: pw.Border.all(color: accent, width: minimal ? 0.8 : 1.4),
              borderRadius: pw.BorderRadius.circular(modern ? 8 : 4),
            ),
            child: pw.Column(children: [
              if (view.issuerRuc.isNotEmpty) pw.Text('R.U.C. ${view.issuerRuc}', style: st(11, b: true, color: modern ? PdfColors.white : _ink)),
              pw.SizedBox(height: 4),
              pw.Text(view.title, textAlign: pw.TextAlign.center, style: st(11, b: true, color: modern ? PdfColors.white : accent)),
              pw.SizedBox(height: 4),
              pw.Text(view.number, style: st(12, b: true, color: modern ? PdfColors.white : _ink)),
            ]),
          ),
        ]),
        pw.SizedBox(height: 14),
        // ---- Cliente y datos
        pw.Container(
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: minimal ? null : _soft,
            border: minimal ? pw.Border.all(color: _line, width: 0.6) : null,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(children: [
            _kv('Señor(es)', view.clientName, st),
            if (view.clientDoc.isNotEmpty) _kv(view.clientDocLabel, view.clientDoc, st),
            if (view.clientAddress.isNotEmpty) _kv('Dirección', view.clientAddress, st),
            _kv('Fecha de emisión', view.date, st),
            _kv('Moneda', view.currencyName, st),
            if (view.paymentLine.isNotEmpty) _kv('Condición de pago', view.paymentLine, st),
          ]),
        ),
        pw.SizedBox(height: 12),
        // ---- Detalle
        pw.Table(
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.8)),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FixedColumnWidth(40),
            2: const pw.FixedColumnWidth(42),
            3: const pw.FlexColumnWidth(),
            4: const pw.FixedColumnWidth(70),
            5: const pw.FixedColumnWidth(74),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: accent),
              children: [cell('#', head: true), cell('Cant.', head: true, right: true), cell('Unid.', head: true), cell('Descripción', head: true), cell('V. Unit.', head: true, right: true), cell('Importe', head: true, right: true)],
            ),
            for (var k = 0; k < view.rows.length; k++)
              pw.TableRow(children: [
                cell('${k + 1}'),
                cell(qtyText(view.rows[k].qty), right: true),
                cell(view.rows[k].unit),
                cell(view.rows[k].description),
                cell(money(view.rows[k].unitValue, view.currency), right: true),
                cell(money(view.rows[k].amount, view.currency), right: true),
              ]),
          ],
        ),
        pw.SizedBox(height: 10),
        // ---- Totales
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: view.legend.isEmpty
                ? pw.SizedBox()
                : pw.Padding(padding: const pw.EdgeInsets.only(right: 16), child: pw.Text('SON: ${view.legend.replaceFirst('SON ', '')}', style: st(9, b: true))),
          ),
          pw.SizedBox(
            width: 200,
            child: pw.Column(children: [
              for (final t in view.totalRows) totalRow(t.$1, money(t.$2, view.currency), strong: t.$3),
            ]),
          ),
        ]),
        if (view.notes.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('Observaciones', style: st(8, color: _muted)),
          pw.Text(view.notes, style: st(9)),
        ],
        pw.SizedBox(height: 18),
        // ---- Pie fiscal: QR + hash + estado
        if (view.qr != null)
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8))),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              // QR con corrección de errores nivel Q (25 %), como pide SUNAT para la representación impresa.
              pw.BarcodeWidget(barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.quartile), data: view.qr!, width: 86, height: 86),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(view.statusLine, style: st(9, b: true)),
                  if (view.hash.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Valor resumen: ${view.hash}', style: st(7.5, color: _muted))),
                  pw.SizedBox(height: 4),
                  pw.Text(view.legalNote, style: st(7.5, color: _muted)),
                ]),
              ),
            ]),
          ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _kv(String k, String v, pw.TextStyle Function(double, {bool b, PdfColor color}) st) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 100, child: pw.Text(k, style: st(8.5, color: _muted))),
        pw.Expanded(child: pw.Text(v, style: st(9.5, b: true))),
      ]),
    );

// ------------------------------------------------------------------ modelos de vista

class _Row {
  _Row(this.qty, this.unit, this.description, this.unitValue, this.amount);
  final double qty;
  final String unit;
  final String description;
  final double unitValue;
  final double amount;
}

class _View {
  _View({
    required this.title,
    required this.number,
    required this.issuerName,
    required this.issuerTrade,
    required this.issuerRuc,
    required this.issuerLines,
    required this.clientName,
    required this.clientDocLabel,
    required this.clientDoc,
    required this.clientAddress,
    required this.date,
    required this.currency,
    required this.currencyName,
    required this.paymentLine,
    required this.rows,
    required this.totalRows,
    required this.legend,
    required this.notes,
    required this.banners,
    required this.footerNote,
    this.qr,
    this.hash = '',
    this.statusLine = '',
    this.legalNote = '',
  });

  final String title, number, issuerName, issuerTrade, issuerRuc;
  final List<String> issuerLines;
  final String clientName, clientDocLabel, clientDoc, clientAddress, date, currency, currencyName, paymentLine;
  final List<_Row> rows;
  final List<(String, double, bool)> totalRows;
  final String legend, notes, footerNote, hash, statusLine, legalNote;
  final List<(String, PdfColor)> banners;
  final String? qr;
}

String _currencyName(String c) => switch (c) {
      'PEN' => 'SOLES (PEN)',
      'USD' => 'DÓLARES AMERICANOS (USD)',
      'EUR' => 'EUROS (EUR)',
      _ => c,
    };

_View _fiscalView(FiscalDoc f) {
  final p = f.payload;
  final company = _m(p['company']);
  final addr = _m(company['address']);
  final client = _m(p['client']);
  final cur = (p['tipoMoneda'] ?? 'PEN') as String;
  final date = displayDate(((p['fechaEmision'] ?? '') as String).split('T').first);
  final isoDate = ((p['fechaEmision'] ?? '') as String).split('T').first;
  final details = ((p['details'] ?? []) as List).map(_m).toList();
  final t = f.totals;
  final igv = _d(t['igv']);
  final total = _d(t['total']);
  final gravadas = _d(t['gravadas']);
  final exoneradas = _d(t['exoneradas']);
  final inafectas = _d(t['inafectas']);
  final rate = details.isNotEmpty ? _d(details.first['porcentajeIgv']) : 18;
  final accepted = f.status == 'accepted';

  final tipoDoc = (client['tipoDoc'] ?? '-') as String;
  final qr = [
    company['ruc'],
    f.docType,
    f.series,
    f.correlative.toString().padLeft(8, '0'),
    igv.toStringAsFixed(2),
    total.toStringAsFixed(2),
    isoDate,
    tipoDoc,
    client['numDoc'] ?? '',
    f.hash, // valor resumen: campo 10 del QR (Anexo N.° 6, num. 6.4)
  ].join('|');

  final banners = <(String, PdfColor)>[];
  if (f.env == 'beta') banners.add(('DOCUMENTO DE PRUEBA (SUNAT BETA) — SIN VALIDEZ TRIBUTARIA', const PdfColor.fromInt(0xFFB91C1C)));
  if (!accepted) {
    banners.add((
      f.status == 'rejected' ? 'COMPROBANTE RECHAZADO POR SUNAT — NO ES VÁLIDO' : 'COMPROBANTE AÚN NO CONFIRMADO POR SUNAT — NO ES VÁLIDO HASTA SU ACEPTACIÓN',
      const PdfColor.fromInt(0xFFB45309),
    ));
  }

  return _View(
    title: f.typeName,
    number: f.number,
    issuerName: (company['razonSocial'] ?? '') as String,
    issuerTrade: (company['nombreComercial'] ?? '') as String,
    issuerRuc: (company['ruc'] ?? '') as String,
    issuerLines: [
      (addr['direccion'] ?? '') as String,
      [addr['distrito'], addr['provincia'], addr['departamento']].where((e) => e != null && '$e'.isNotEmpty && '$e' != '-').join(' - '),
    ].where((e) => e.isNotEmpty).toList(),
    clientName: (client['rznSocial'] ?? '') as String,
    clientDocLabel: _docLabel(tipoDoc),
    clientDoc: tipoDoc == '-' ? '' : (client['numDoc'] ?? '') as String,
    clientAddress: (_m(client['address'])['direccion'] ?? '') as String,
    date: date,
    currency: cur,
    currencyName: _currencyName(cur),
    paymentLine: _paymentLine(p, cur),
    rows: details
        .map((d) => _Row(_d(d['cantidad']), (d['unidad'] ?? 'NIU') as String, (d['descripcion'] ?? '') as String, _d(d['mtoValorUnitario']), _d(d['mtoValorVenta'])))
        .toList(),
    totalRows: [
      if (gravadas > 0) ('Op. Gravada', gravadas, false),
      if (exoneradas > 0) ('Op. Exonerada', exoneradas, false),
      if (inafectas > 0) ('Op. Inafecta', inafectas, false),
      ('IGV (${qtyText(rate.toDouble())}%)', igv, false),
      ('IMPORTE TOTAL', total, true),
    ],

    legend: f.legend,
    notes: f.isCreditNote ? _noteReference(p) : '',
    banners: banners,
    footerNote: '${f.number} · ${f.typeName}',
    qr: qr,
    hash: f.hash,
    statusLine: accepted ? 'Aceptada por SUNAT${f.sunatCode.isEmpty ? '' : ' (CDR ${f.sunatCode})'}' : fiscalStatusLabel(f.status),
    legalNote: 'Representación impresa de la ${f.docType == '01' ? 'Factura Electrónica' : (f.isCreditNote ? 'Nota de Crédito Electrónica' : 'Boleta de Venta Electrónica')}. '
        'Puede consultar su validez en https://www.sunat.gob.pe con los datos del código QR.',
  );
}

/// Forma de pago tal como se envió a SUNAT (Contado / Crédito con sus cuotas).
String _paymentLine(Map<String, dynamic> p, String cur) {
  final fp = _m(p['formaPago']);
  if ((fp['tipo'] ?? 'Contado') != 'Credito') return 'Contado';
  final cuotas = ((p['cuotas'] ?? const []) as List).map(_m).toList();
  if (cuotas.isEmpty) return 'Crédito';
  final parts = [
    for (final (i, c) in cuotas.indexed) 'Cuota ${i + 1}: ${money(_d(c['monto']), cur)} vence ${displayDate('${c['fechaPago'] ?? ''}'.split('T').first)}',
  ];
  return 'Crédito · ${parts.join(' · ')}';
}

/// "Documento que modifica: F001-00000012 · Motivo: …" a partir de la nota enviada a SUNAT.
String _noteReference(Map<String, dynamic> p) {
  final ref = ((p['numDocfectado'] ?? '') as String).split('-');
  final shown = ref.length == 2 ? fiscalNumberOf(ref[0], int.tryParse(ref[1]) ?? 0) : (p['numDocfectado'] ?? '') as String;
  return 'Documento que modifica: $shown · Motivo: ${p['desMotivo'] ?? ''}';
}

_View _internalView(InvoiceRecord inv, Profile issuer) {
  final t = inv.totals;
  final rate = qtyText(inv.taxRate);
  return _View(
    title: 'NOTA DE VENTA',
    number: inv.number,
    issuerName: issuer.businessName,
    issuerTrade: issuer.tradeName,
    issuerRuc: issuer.taxId,
    issuerLines: [issuer.address].where((e) => e.isNotEmpty).toList(),
    clientName: inv.clientName,
    clientDocLabel: 'Documento',
    clientDoc: inv.clientTaxId,
    clientAddress: '',
    date: displayDate(inv.issueDate),
    currency: inv.currency,
    currencyName: _currencyName(inv.currency),
    paymentLine: '',
    rows: inv.items.map((i) => _Row(i.quantity, '', i.description, round2(i.unitPrice), i.amount)).toList(),
    totalRows: [
      ('Subtotal', t.subtotal, false),
      ('${issuer.taxLabel.isEmpty ? 'Impuesto' : issuer.taxLabel} ($rate%)', t.tax, false),
      ('TOTAL', t.total, true),
    ],
    legend: '',
    notes: inv.notes,
    banners: [('DOCUMENTO SIN VALIDEZ TRIBUTARIO — NO ES COMPROBANTE DE PAGO ELECTRÓNICO', const PdfColor.fromInt(0xFF4B5563))],
    footerNote: 'Documento interno · ${inv.number}',
  );
}
