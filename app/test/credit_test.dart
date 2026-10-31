import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/credit.dart';

void main() {
  test('sin límite no advierte', () {
    expect(creditCheck(limit: null, used: 500, newTotal: 900).level, CreditLevel.none);
    expect(creditCheck(limit: 0, used: 0, newTotal: 10).level, CreditLevel.none);
  });

  test('ok, cerca y pasado', () {
    expect(creditCheck(limit: 1000, used: 100, newTotal: 200).level, CreditLevel.ok);
    final near = creditCheck(limit: 1000, used: 500, newTotal: 350);
    expect(near.level, CreditLevel.near);
    expect(near.left, 150);
    final over = creditCheck(limit: 1000, used: 800, newTotal: 300);
    expect(over.level, CreditLevel.over);
    expect(over.excess, 100);
    expect(over.after, 1100);
  });

  test('justo en el límite no se pasa', () {
    expect(creditCheck(limit: 1000, used: 700, newTotal: 300).level, CreditLevel.near);
  });
}
