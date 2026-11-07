import 'package:facturavoz/logic/retail_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('céntimos exactos y rechazo de importes ambiguos', () {
    expect(parseCents('0.29'), 29);
    expect(parseCents('12,50'), 1250);
    expect(parseCents('50'), 5000);
    expect(parseCents('0.1'), 10);
    for (final value in ['NaN', 'Infinity', '-1', '1e2', '1.001', '1,000.00']) {
      expect(parseCents(value), isNull);
    }
    expect(centsFromLegacy(23.60), 2360);
  });
}
