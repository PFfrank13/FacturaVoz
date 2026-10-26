import 'package:facturavoz/models.dart';
import 'package:facturavoz/reports.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceRecord inv(String date, String client, double price,
        {String cur = 'PEN', String? fiscal, double tax = 18, String status = 'sent', double paid = 0, String? due}) =>
    InvoiceRecord(
      id: '$date$client$price',
      number: 'N-1',
      issueDate: date,
      status: status,
      paid: paid,
      dueDate: due,
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
  paymentTests();
  receivableTests();
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

void receivableTests() {
  test('por cobrar y vencido en el reporte, y columnas del CSV', () {
    final list = [
      inv('2026-10-01', 'Ana', 100, paid: 18, due: '2026-10-10'), // saldo 100, vencida
      inv('2026-10-02', 'Luis', 100, due: '2026-12-01'), // saldo 118, vigente
      inv('2026-10-03', 'Zoe', 100, status: 'paid', paid: 118), // saldada
      inv('2026-10-04', 'Rey', 100, status: 'draft'), // borrador: no se cobra
    ];
    final r = buildReport(list, today: '2026-10-25')['PEN']!;
    expect(r.receivable, 218);
    expect(r.overdue, 100);
    final csv = invoicesToCsv(list);
    expect(csv.contains('Total,Cobrado,Saldo,Vence,Estado'), isTrue);
    expect(csv.contains('118.00,18.00,100.00,2026-10-10'), isTrue);
  });
}

void paymentTests() {
  InvoiceRecord mk({String status = 'sent', String? due, double paid = 0, String? fiscal}) => InvoiceRecord(
        id: 'x',
        number: 'N-1',
        issueDate: '2026-10-01',
        status: status,
        currency: 'PEN',
        taxRate: 18,
        notes: '',
        clientName: 'Ana',
        clientTaxId: '',
        clientDocType: '',
        dueDate: due,
        paid: paid,
        fiscalStatus: fiscal,
        items: [LineItem(description: 'x', quantity: 1, unitPrice: 100)],
      );

  test('saldo, por cobrar y vencida', () {
    expect(mk().balance, 118);
    expect(mk(paid: 40).balance, 78);
    expect(mk(paid: 200).balance, 0); // nunca negativo
    expect(mk().receivable, isTrue);
    expect(mk(status: 'draft').receivable, isFalse);
    expect(mk(status: 'paid', paid: 118).receivable, isFalse);
    expect(mk(paid: 118).receivable, isFalse);
    expect(mk(fiscal: 'rejected').receivable, isFalse);
    expect(mk(due: '2026-10-10').isOverdue('2026-10-11'), isTrue);
    expect(mk(due: '2026-10-10').isOverdue('2026-10-10'), isFalse); // vence hoy: aún no vencida
    expect(mk(due: '2026-10-10', paid: 118).isOverdue('2026-12-01'), isFalse);
    expect(mk().isOverdue('2030-01-01'), isFalse); // sin fecha no vence
  });

  test('todayIso con ceros a la izquierda', () {
    expect(todayIso(DateTime(2026, 3, 5)), '2026-03-05');
  });
}
