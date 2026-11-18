import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/retail_purchases.dart';

void main() {
  test('compras conserva márgenes táctiles en móviles y tablets', () {
    expect(retailPurchaseHorizontalInset(320), 16);
    expect(retailPurchaseHorizontalInset(360), 16);
    expect(retailPurchaseHorizontalInset(768), 16);
    expect(retailPurchaseHorizontalInset(960), 16);
    expect(retailPurchaseHorizontalInset(970), 16);
    expect(retailPurchaseHorizontalInset(980), 16);
    expect(retailPurchaseHorizontalInset(992), 16);
  });

  test('compras limita formularios a 960 dp en escritorio y ultrawide', () {
    for (final width in <double>[1040, 1280, 1440, 1920, 3440]) {
      final inset = retailPurchaseHorizontalInset(width);
      expect(inset, greaterThanOrEqualTo(16));
      expect(width - inset * 2, closeTo(960, 0.001));
    }
  });

  test('compras no produce márgenes invalidos ante medidas no finitas', () {
    expect(retailPurchaseHorizontalInset(double.infinity), 16);
    expect(retailPurchaseHorizontalInset(double.nan), 16);
  });
}
