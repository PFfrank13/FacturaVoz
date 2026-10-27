import 'package:facturavoz/finance.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/models_pro.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceRecord inv({
  String id = 'i1',
  String client = 'Ferretería Díaz SAC',
  String issue = '2026-10-01',
  String? due,
  double price = 100,
  double paid = 0,
  String status = 'sent',
  String currency = 'PEN',
}) =>
    InvoiceRecord(
      id: id,
      number: 'F-$id',
      issueDate: issue,
      status: status,
      currency: currency,
      taxRate: 18,
      notes: '',
      clientName: client,
      clientTaxId: '',
      clientDocType: '',
      dueDate: due,
      paid: paid,
      items: [LineItem(description: 'Servicio', quantity: 1, unitPrice: price)],
    );

ClientPayStats stats({double? late, double overdue = 0, int settled = 5, int maxLate = 0, double? toPay}) => ClientPayStats(
      key: 'x',
      name: 'X',
      invoices: settled,
      creditInvoices: settled,
      settled: settled,
      avgDaysToPay: toPay,
      avgDaysLate: late,
      maxDaysLate: maxLate,
      openBalance: overdue,
      overdueBalance: overdue,
    );

void main() {
  test('fechas', () {
    expect(daysBetween('2026-10-01', '2026-10-31'), 30);
    expect(addDays('2026-12-30', 3), '2027-01-02');
    expect(dayMonth('2026-11-05'), '05/11');
  });

  test('antigüedad de deudas por tramos', () {
    final a = agingOf([
      inv(id: 'a', due: '2026-11-10'), // por vencer
      inv(id: 'b', due: '2026-10-20'), // 7 días
      inv(id: 'c', due: '2026-09-10'), // 47 días
      inv(id: 'd', due: '2026-06-01'), // +90
      inv(id: 'e', due: '2026-10-01', paid: 118), // pagada: no cuenta
    ], '2026-10-27');
    expect(a.current, 118);
    expect(a.d1to30, 118);
    expect(a.d31to60, 118);
    expect(a.d90plus, 118);
    expect(a.overdue, 354);
    expect(a.total, 472);
  });

  test('score de crédito', () {
    expect(scoreClient(null).grade, Grade.unknown);
    expect(scoreClient(stats(late: 0)).grade, Grade.a);
    expect(scoreClient(stats(late: 8)).grade, Grade.b);
    expect(scoreClient(stats(late: 10, overdue: 50)).grade, Grade.c);
    expect(scoreClient(stats(late: 25, overdue: 500, maxLate: 60)).grade, Grade.d);
    expect(scoreClient(stats(late: 25, overdue: 500, maxLate: 60)).advice, contains('contado'));
  });

  test('fecha probable de pago según historial', () {
    final i = inv(due: '2026-11-10');
    expect(expectedPayDate(i, stats(late: 5), '2026-10-27'), '2026-11-15');
    // ya vencida y sin pagar: se espera tras un recordatorio (hoy + 7)
    expect(expectedPayDate(inv(due: '2026-10-01'), stats(late: 2), '2026-10-27'), '2026-11-03');
    // al contado sin vencimiento: emisión + días promedio de pago
    expect(expectedPayDate(inv(issue: '2026-10-25'), stats(toPay: 10), '2026-10-27'), '2026-11-04');
  });

  test('proyección de caja avisa cuando faltaría dinero', () {
    final f = forecastCash(
      receivables: [inv(due: '2026-10-30', price: 100)],
      stats: const {},
      dailyExpense: 10,
      today: '2026-10-27',
      weeks: 3,
    );
    expect(f.weeks.length, 3);
    expect(f.weeks.first.inflow, closeTo(118 * 0.75, 0.01)); // cliente nuevo: 75 %
    expect(f.weeks.first.outflow, 70);
    expect(f.warning, isNotNull);
    expect(f.totalOut, 210);
  });

  test('rentabilidad: ventas y gastos sin IGV, IGV estimado y caja', () {
    final p = profitOf(
      invoices: [inv(price: 1000), inv(id: 'r', price: 500, status: 'draft')],
      expenses: [Expense(spentOn: '2026-10-02', category: 'mercaderia', description: 'x', total: 236, tax: 36)],
      payments: const [DatedPayment(amount: 500, paidOn: '2026-10-05', currency: 'PEN')],
      currency: 'PEN',
    );
    expect(p.sales, 1000);
    expect(p.salesTax, 180);
    expect(p.expenses, 200);
    expect(p.profit, 800);
    expect(p.margin, closeTo(0.8, 0.0001));
    expect(p.igvEstimate, 144);
    expect(p.netCash, 264);
    expect(p.invoiceCount, 1);
  });

  test('serie mensual de 6 meses termina en el mes actual', () {
    final s = monthlySeries(
      invoices: [inv(issue: '2026-10-03', price: 100), inv(id: '2', issue: '2026-05-03', price: 50)],
      expenses: [Expense(spentOn: '2026-09-02', category: 'otros', description: 'x', total: 118, tax: 18)],
      currency: 'PEN',
      today: '2026-10-27',
    );
    expect(s.map((m) => m.label).toList(), ['May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct']);
    expect(s.first.sales, 50);
    expect(s.last.sales, 100);
    expect(s[4].expenses, 100);
  });

  test('avisos del día', () {
    final list = buildInsights(
      invoices: [inv(id: 'a', due: '2026-10-20'), inv(id: 'b', due: '2026-10-30', client: 'Bodega Lupe')],
      today: '2026-10-27',
      currency: 'PEN',
      pendingClaims: 2,
      stock: const [ProductVelocity(id: 'p', name: 'Cable HDMI', stock: 4, reorderPoint: 5, units: 30, perDay: 1)],
    );
    expect(list.map((i) => i.kind).toList(), ['claims', 'overdue', 'due_soon', 'stock']);
    expect(list[3].title, contains('Cable HDMI'));
  });

  test('similitud de nombres tolera abreviaturas de Yape', () {
    expect(nameSimilarity('Juan P. Perez', 'Juan Pérez Gómez'), greaterThanOrEqualTo(0.6));
    expect(nameSimilarity('Ferreteria Diaz', 'FERRETERÍA DÍAZ S.A.C.'), 1);
    expect(nameSimilarity('Maria Lopez', 'Corpax SAC'), 0);
  });

  test('conciliación propone la factura correcta', () {
    final r = matchPayment(
      PaymentScan(app: 'yape', amount: 118, currency: 'PEN', payerName: 'Juan P. Perez', operationCode: '123', date: '2026-10-27'),
      [
        inv(id: 'a', client: 'Corpax SAC', price: 100),
        inv(id: 'b', client: 'Juan Pérez', price: 100),
        inv(id: 'c', client: 'Juan Pérez', price: 50), // saldo 59: pagó más → descartada
      ],
      '2026-10-27',
    );
    expect(r.first.invoice.id, 'b');
    expect(r.first.reasons, contains('El nombre coincide'));
    expect(r.any((c) => c.invoice.id == 'c'), isFalse);
  });
}
