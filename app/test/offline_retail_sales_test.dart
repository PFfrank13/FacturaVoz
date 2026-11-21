import 'package:facturavoz/services/repo.dart';
import 'package:facturavoz/services/v2_repo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/retail_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('las ventas de la demo cuadran con los comprobantes al cambiar de año', () async {
    await startRetailFixture(salesDate: DateTime(2027, 1, 2));
    addTearDown(stopRetailFixture);
    final invoices = await Repo.listInvoices();
    expect(invoices.map((invoice) => invoice.issueDate),
        ['2026-12-24', '2026-12-27', '2026-12-30', '2027-01-02']);
    final december = await V2Repo.salesSummary('2026-12-01', '2027-01-01', 'PEN');
    final january = await V2Repo.salesSummary('2027-01-01', '2027-02-01', 'PEN');
    expect(december?['sales_total'], 66);
    expect(december?['sales_count'], 3);
    expect(january?['sales_total'], 55);
    expect(january?['sales_count'], 1);

    final series = await V2Repo.salesDaily('2027-01-02', 'PEN');
    expect(series, [0, 0, 0, 0, 5.5, 0, 0, 22, 0, 0, 38.5, 0, 0, 55]);
    final cash = await V2Repo.daySummary('2027-01-02');
    expect(cash.salesTotal, 55);
    expect(cash.salesCount, 1);
    expect(cash.byMethod['efectivo'], 55);
    final empty = await V2Repo.daySummary('2027-01-01');
    expect(empty.salesTotal, 0);
    expect(empty.salesCount, 0);
  });
}
