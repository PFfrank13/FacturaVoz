// Comanda para cocina y precuenta (estilo restaurante): se imprimen en la térmica (Bluetooth o red) o salen en PDF de rollo.
// La COMANDA no lleva precios (la cocina no los necesita). La PRECUENTA muestra lo consumido y dice claramente que
// NO es comprobante de pago (el comprobante se emite al cobrar).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../logic/escpos.dart';
import '../../models.dart';
import 'ticket_printer.dart';

class ComandaLine {
  const ComandaLine(this.qty, this.name, [this.note = '']);
  final double qty;
  final String name;
  final String note; // "sin cebolla", "con arroz"…
}

class ComandaData {
  const ComandaData({required this.table, required this.waiter, required this.date, required this.lines, this.order = '', this.note = ''});
  final String table; // vacío = para llevar
  final String waiter;
  final String date;
  final String order; // número de pedido (si existe)
  final String note;
  final List<ComandaLine> lines;

  String get where => table.trim().isEmpty ? 'PARA LLEVAR' : 'MESA: ${table.trim()}';
}

/// Texto de fecha y hora para el papel.
String nowText([DateTime? t]) {
  final d = t ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

Uint8List buildEscPosComanda(ComandaData d, {required int width}) {
  final e = EscPos(Paper.of(width))..init();
  e.text('COMANDA', a: 1, b: true, big: true);
  e.text(d.date, a: 1);
  e.line();
  e.text(d.where, b: true, big: width == 80);
  if (d.order.isNotEmpty) e.text('PEDIDO: ${d.order}', b: true);
  if (d.waiter.isNotEmpty) e.text('MOZO: ${d.waiter}');
  e.line();
  for (final l in d.lines) {
    e.wrap('${qtyText(l.qty)}x ${l.name}', b: true);
    if (l.note.trim().isNotEmpty) e.wrap('   >> ${l.note.trim()}');
  }
  if (d.note.trim().isNotEmpty) {
    e.line();
    e.wrap('NOTA: ${d.note.trim()}');
  }
  e.feed(3);
  e.cut();
  return e.bytes();
}

Future<Uint8List> buildComandaPdf(ComandaData d, {required int width}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final fmt = width == 58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
  final fs = width == 58 ? 8.0 : 9.0;
  pw.TextStyle st({bool b = false, double? size}) => pw.TextStyle(fontSize: size ?? fs, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal);
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold), title: 'Comanda');
  doc.addPage(pw.Page(
    pageFormat: fmt.copyWith(marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 8),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text('COMANDA', textAlign: pw.TextAlign.center, style: st(b: true, size: fs + 5)),
      pw.Text(d.date, textAlign: pw.TextAlign.center, style: st()),
      pw.Divider(thickness: 0.5),
      pw.Text(d.where, style: st(b: true, size: fs + 3)),
      if (d.order.isNotEmpty) pw.Text('PEDIDO: ${d.order}', style: st(b: true)),
      if (d.waiter.isNotEmpty) pw.Text('MOZO: ${d.waiter}', style: st()),
      pw.Divider(thickness: 0.5),
      for (final l in d.lines) ...[
        pw.Text('${qtyText(l.qty)}x ${l.name}', style: st(b: true, size: fs + 1)),
        if (l.note.trim().isNotEmpty) pw.Text('   >> ${l.note.trim()}', style: st()),
      ],
      if (d.note.trim().isNotEmpty) ...[pw.Divider(thickness: 0.5), pw.Text('NOTA: ${d.note.trim()}', style: st())],
    ]),
  ));
  return doc.save();
}

/// Precuenta: usa el mismo formato del ticket, con la advertencia de que no es comprobante.
TicketData precuentaData({
  required Profile profile,
  required String table,
  required String waiter,
  required List<TicketLine> lines,
  required List<(String, double, bool)> totals,
  required String currency,
}) =>
    TicketData(
      issuerName: profile.tradeName.trim().isNotEmpty ? profile.tradeName : profile.businessName,
      issuerRuc: profile.taxId,
      issuerAddress: profile.address,
      title: 'PRECUENTA',
      number: table.trim().isEmpty ? 'PARA LLEVAR' : 'MESA ${table.trim()}',
      date: nowText(),
      clientName: waiter.isEmpty ? '' : 'Atendió: $waiter',
      clientDoc: '',
      lines: lines,
      totals: totals,
      currency: currency,
      warning: 'NO ES COMPROBANTE DE PAGO',
      footer: 'Pide tu boleta o factura al pagar.',
    );

/// Imprime la comanda en la impresora configurada; si la impresora es "PDF", abre el PDF de rollo.
Future<void> printComanda(ComandaData d) async {
  final cfg = await PrinterStore.load();
  if (cfg.kind == 'pdf') {
    final pdf = await buildComandaPdf(d, width: cfg.width);
    await Printing.layoutPdf(name: 'comanda.pdf', onLayout: (_) => pdf);
    return;
  }
  await sendEscPos(cfg, buildEscPosComanda(d, width: cfg.width));
}

Future<void> printPrecuenta(TicketData d) async {
  final cfg = await PrinterStore.load();
  if (cfg.kind == 'pdf') {
    final pdf = await buildTicketPdf(d, width: cfg.width);
    await Printing.layoutPdf(name: 'precuenta.pdf', onLayout: (_) => pdf);
    return;
  }
  await sendEscPos(cfg, buildEscPosTicket(d, width: cfg.width, nativeQr: cfg.nativeQr));
}

// ═════════════════════════ Documentos de cada rubro (orden, cita, recibo) ═════════════════════════
// Cada rubro imprime SU documento: taller → orden de trabajo, servicios técnicos → orden de servicio,
// construcción → orden de obra, salón y consultorio → cita, educación → horario/clase. Son comprobantes internos
// (NO son comprobantes de pago). Salen en la térmica configurada o en PDF de rollo.
class DocData {
  const DocData({required this.title, required this.number, required this.date, required this.issuer, required this.rows, this.signature = false, this.footer = ''});
  final String title;
  final String number;
  final String date;
  final String issuer;
  final List<(String, String)> rows; // (etiqueta, valor); se omiten los vacíos
  final bool signature;
  final String footer;

  List<(String, String)> get shown => [for (final r in rows) if (r.$2.trim().isNotEmpty) r];
}

/// Título y si lleva firma, según el rubro.
({String title, bool signature, String footer}) jobDocSpec(String? rubro) => switch (rubro) {
      'taller' => (title: 'ORDEN DE TRABAJO', signature: true, footer: 'Presenta esta orden para recoger tu equipo.'),
      'servicios_tecnicos' => (title: 'ORDEN DE SERVICIO', signature: true, footer: 'Conserva esta orden.'),
      'construccion' => (title: 'ORDEN DE OBRA', signature: true, footer: ''),
      'salon' => (title: 'CITA', signature: false, footer: 'Llega unos minutos antes. Si no puedes venir, avísanos.'),
      'consultorio' => (title: 'CITA', signature: false, footer: 'Llega unos minutos antes. Si no puedes venir, avísanos.'),
      'educacion' => (title: 'HORARIO / CLASE', signature: false, footer: ''),
      _ => (title: 'ORDEN', signature: false, footer: ''),
    };

Uint8List buildEscPosDoc(DocData d, {required int width}) {
  final e = EscPos(Paper.of(width))..init();
  if (d.issuer.isNotEmpty) e.text(d.issuer, a: 1, b: true);
  e.text(d.title, a: 1, b: true, big: true);
  e.text(d.number, a: 1, b: true);
  e.text(d.date, a: 1);
  e.line();
  for (final r in d.shown) {
    e.wrap('${r.$1}: ${r.$2}');
  }
  if (d.signature) {
    e.feed(2);
    e.text('Firma del cliente:');
    e.feed(2);
    e.line('_');
  }
  if (d.footer.isNotEmpty) {
    e.feed();
    e.wrap(d.footer, a: 1);
  }
  e.feed(3);
  e.cut();
  return e.bytes();
}

Future<Uint8List> buildDocPdf(DocData d, {required int width}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final fmt = width == 58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
  final fs = width == 58 ? 8.0 : 9.0;
  pw.TextStyle st({bool b = false, double? size}) => pw.TextStyle(fontSize: size ?? fs, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal);
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold), title: d.title);
  doc.addPage(pw.Page(
    pageFormat: fmt.copyWith(marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 8),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (d.issuer.isNotEmpty) pw.Text(d.issuer, textAlign: pw.TextAlign.center, style: st(b: true)),
      pw.Text(d.title, textAlign: pw.TextAlign.center, style: st(b: true, size: fs + 4)),
      pw.Text(d.number, textAlign: pw.TextAlign.center, style: st(b: true)),
      pw.Text(d.date, textAlign: pw.TextAlign.center, style: st()),
      pw.Divider(thickness: 0.5),
      for (final r in d.shown) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 2), child: pw.Text('${r.$1}: ${r.$2}', style: st())),
      if (d.signature) ...[pw.SizedBox(height: 22), pw.Text('Firma del cliente:', style: st()), pw.SizedBox(height: 22), pw.Divider(thickness: 0.7)],
      if (d.footer.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text(d.footer, textAlign: pw.TextAlign.center, style: st(size: fs - 1))),
    ]),
  ));
  return doc.save();
}

Future<void> printDoc(DocData d) async {
  final cfg = await PrinterStore.load();
  if (cfg.kind == 'pdf') {
    final pdf = await buildDocPdf(d, width: cfg.width);
    await Printing.layoutPdf(name: '${d.title.toLowerCase().replaceAll(' ', '-')}.pdf', onLayout: (_) => pdf);
    return;
  }
  await sendEscPos(cfg, buildEscPosDoc(d, width: cfg.width));
}
