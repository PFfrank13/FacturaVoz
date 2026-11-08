import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/pos_payment_logic.dart';

void main() {
  test('parses PEN cents exactly without floating point', () {
    expect(parsePosCents('12.5'), 1250);
    expect(parsePosCents('12,50'), 1250);
    expect(parsePosCents('0.01'), 1);
    expect(parsePosCents('150'), 15000);
    expect(parsePosCents('1.234'), isNull);
    expect(parsePosCents('-1.00'), isNull);
    expect(parsePosCents('NaN'), isNull);
    expect(parsePosCents(''), isNull);
  });

  test('cash must cover the sale; change is exact in cents', () {
    expect(posChangeDue(chargeCents: 785, tenderedCents: 1000), 215);
    expect(posChangeDue(chargeCents: 785, tenderedCents: 785), 0);
    expect(() => posChangeDue(chargeCents: 785, tenderedCents: 784), throwsArgumentError);
  });

  test('POS totals follow the existing two-decimal rounding convention', () {
    expect(posMoneyToCents(12.5), 1250);
    expect(posMoneyToCents(0.01), 1);
    expect(() => posMoneyToCents(-1), throwsArgumentError);
  });
}
