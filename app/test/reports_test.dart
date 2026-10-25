import 'package:facturavoz/models.dart';
import 'package:facturavoz/reports.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceRecord inv(String date, String client, double price, {String cur = 'PEN', String? fiscal, double tax = 18}) => InvoiceRecord(
      id: '$date$client$price',
      number: 'N-1',
      issueDate: date,
      status: 'sent',
      currency: cur,
      taxRate: tax,
      notes: '',
      clientName: client,
      clientTaxId: '',
      clientDocType: '',
      items: [LineItem(description: 'x', quantity: 1, unitPrice: price)],
      fiscalStatus: fiscal,
    );

void main() {
  test('rango de mes, incluido diciembre', () {
    expect(monthRange(2026, 10).toExclusive, '2026-11-01');
    expect(monthRange(2026, 12).toExclusive, '2027-01-01');
    expect(monthRange(2026, 3).from, '2026-03-01');
  });

  test('totales por moneda sin mezclar y sin contar rechazados', () {
    final r = buildReport([
      inv('2026-10-02', 'Ana', 100),
      inv('2026-10-02', 'Ana', 50),
      inv('2026-10-05', 'Luis', 200, fiscal: 'rejected'),
      inv('2026-10-06', 'Zoe', 10, cur: 'USD'),
    ]);
    expect(r['PEN']!.count, 2);
    expect(r['PEN']!.subtotal, 150);
    expect(r['PEN']!.tax, 27);
    expect(r['PEN']!.total, 177);
    expect(r['PEN']!.byDay[2], 177);
    expect(r['PEN']!.topClients.first.name, 'Ana');
    expect(r['USD']!.total, 11.8);
  });

  test('CSV escapa comillas/comas y neutraliza fórmulas', () {
    expect(csvCell('=HYPERLINK("x")'), "\"'=HYPERLINK(\"\"x\"\")\"");
    expect(csvCell('Perez, Juan'), '"Perez, Juan"');
    expect(csvCell('Ana\nLuz'), 'Ana Luz');
    final csv = invoicesToCsv([inv('2026-10-02', '+51 Ana', 100)]);
    expect(csv.startsWith('﻿Fecha,'), isTrue);
    expect(csv.contains("'+51 Ana"), isTrue);
    expect(csv.contains('118.00'), isTrue);
  });
}
