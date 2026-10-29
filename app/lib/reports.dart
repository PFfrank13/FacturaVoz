import 'models.dart';

/// Lógica pura de reportes (sin Flutter): se prueba con `flutter test`.

const monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Rango [desde, hasta) del mes, en 'yyyy-MM-dd'.
({String from, String toExclusive}) monthRange(int year, int month) {
  final next = DateTime(year, month + 1, 1);
  return (from: '$year-${_two(month)}-01', toExclusive: '${next.year}-${_two(next.month)}-01');
}

/// LA regla de ventas (igual que el servidor, sales_summary): emitido o pagado, no anulado, no rechazado por SUNAT.
/// Las notas de crédito cuentan, pero RESTAN (ver [signOf]).
bool countsAsSale(InvoiceRecord i) => i.countsAsSale;

/// +1 venta normal, −1 nota de crédito.
double signOf(InvoiceRecord i) => i.isCreditNote ? -1.0 : 1.0;

class ClientTotal {
  ClientTotal(this.name, this.total, this.count);
  final String name;
  final double total;
  final int count;
}

class CurrencyReport {
  CurrencyReport({
    required this.currency,
    required this.count,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.topClients,
    required this.byDay,
    this.receivable = 0,
    this.overdue = 0,
  });

  final String currency;
  final int count;
  final double subtotal;
  final double tax;
  final double total;
  final List<ClientTotal> topClients;
  final Map<int, double> byDay; // día del mes -> total
  final double receivable; // saldo por cobrar de lo facturado en el mes
  final double overdue; // parte del saldo ya vencida

  double get average => count == 0 ? 0 : round2(total / count);
}

/// Un reporte por moneda (nunca se suman monedas distintas).
Map<String, CurrencyReport> buildReport(List<InvoiceRecord> invoices, {int topN = 5, String? today}) {
  final now = today ?? todayIso();
  final groups = <String, List<InvoiceRecord>>{};
  for (final i in invoices.where(countsAsSale)) {
    groups.putIfAbsent(i.currency, () => []).add(i);
  }
  final out = <String, CurrencyReport>{};
  groups.forEach((cur, list) {
    var sub = 0.0, tax = 0.0, total = 0.0, recv = 0.0, over = 0.0;
    final clients = <String, (double, int)>{};
    final days = <int, double>{};
    var n = 0;
    for (final i in list) {
      final t = i.totals;
      final sg = signOf(i);
      if (!i.isCreditNote) n++;
      sub += sg * t.subtotal;
      tax += sg * t.tax;
      total += sg * t.total;
      if (i.receivable) {
        recv += i.balance;
        if (i.isOverdue(now)) over += i.balance;
      }
      final key = i.clientName.trim().isEmpty ? '—' : i.clientName.trim();
      final prev = clients[key] ?? (0.0, 0);
      clients[key] = (prev.$1 + sg * t.total, prev.$2 + (i.isCreditNote ? 0 : 1));
      final day = int.tryParse(i.issueDate.split('-').last) ?? 0;
      days[day] = round2((days[day] ?? 0) + sg * t.total);
    }
    final top = clients.entries.map((e) => ClientTotal(e.key, round2(e.value.$1), e.value.$2)).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    out[cur] = CurrencyReport(
      currency: cur,
      count: n,
      subtotal: round2(sub),
      tax: round2(tax),
      total: round2(total),
      topClients: top.take(topN).toList(),
      byDay: days,
      receivable: round2(recv),
      overdue: round2(over),
    );
  });
  return out;
}

/// Celda CSV segura: comillas escapadas y neutraliza fórmulas (= + - @) que Excel ejecutaría.
String csvCell(String v) {
  var s = v.replaceAll('\r', ' ').replaceAll('\n', ' ');
  if (s.isNotEmpty && '=+-@\t'.contains(s[0])) s = "'$s";
  if (s.contains(',') || s.contains('"')) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// CSV (UTF-8 con BOM para que Excel lea bien las tildes). Una fila por comprobante.
String invoicesToCsv(List<InvoiceRecord> invoices) {
  final b = StringBuffer('﻿');
  b.writeln('Fecha,Número,Comprobante electrónico,Cliente,Documento,Moneda,Subtotal,Impuesto,Total,Cobrado,Saldo,Vence,Estado,SUNAT');
  for (final i in invoices) {
    final t = i.totals;
    b.writeln([
      i.issueDate,
      i.number,
      i.fiscalNumber ?? '',
      i.clientName,
      i.clientTaxId,
      i.currency,
      t.subtotal.toStringAsFixed(2),
      t.tax.toStringAsFixed(2),
      t.total.toStringAsFixed(2),
      i.paid.toStringAsFixed(2),
      i.balance.toStringAsFixed(2),
      i.dueDate ?? '',
      statusLabel(i.status),
      i.fiscalStatus == null ? '' : fiscalStatusLabel(i.fiscalStatus!),
    ].map(csvCell).join(','));
  }
  return b.toString();
}
