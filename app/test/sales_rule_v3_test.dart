import 'package:facturavoz/finance.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/reports.dart';
import 'package:flutter_test/flutter_test.dart';

// A2: la MISMA regla de ventas en Inicio, Reportes, Mi negocio y Copiloto (igual que sales_summary en la base).
InvoiceRecord v3(double total, {String kind = 'factura', bool voided = false, String status = 'paid', String? fiscal, String date = '2026-10-05'}) =>
    InvoiceRecord(
      id: '$kind$total$voided$status',
      number: 'F001-1',
      issueDate: date,
      status: status,
      currency: 'PEN',
      taxRate: 18,
      notes: 'Importada',
      clientName: 'Ana',
      clientTaxId: '',
      clientDocType: '',
      items: const [],
      fiscalStatus: fiscal,
      docKind: kind,
      voided: voided,
      imported: true,
      lockedTotals: Totals(round2(total / 1.18), round2(total - total / 1.18), total),
    );

void main() {
  final data = [
    v3(118),
    v3(236, kind: 'boleta'),
    v3(59, kind: 'nota_credito'), // resta
    v3(1000, voided: true), // anulada: fuera
    v3(500, status: 'draft'), // borrador: fuera
    v3(300, fiscal: 'rejected'), // rechazada por SUNAT: fuera
  ];

  test('neto = ventas − notas de crédito, sin anuladas, borradores ni rechazadas', () {
    final r = buildReport(data)['PEN']!;
    expect(r.total, 295); // 118 + 236 − 59
    expect(r.count, 2); // las notas de crédito no cuentan como venta
  });

  test('Mi negocio usa la misma regla', () {
    final p = profitOf(invoices: data, expenses: const [], payments: const [], currency: 'PEN');
    expect(round2(p.sales + p.salesTax), 295);
    expect(p.invoiceCount, 2);
  });

  test('montos importados se respetan tal cual', () {
    final i = v3(100.01);
    expect(i.totals.total, 100.01);
    expect(v3(59, kind: 'nota_credito').signedTotal, -59);
  });

  test('una anulada o una nota de crédito nunca es "por cobrar"', () {
    expect(v3(100, voided: true, status: 'sent').receivable, isFalse);
    expect(v3(100, kind: 'nota_credito', status: 'sent').receivable, isFalse);
    expect(v3(100, status: 'sent').receivable, isTrue);
  });
}
