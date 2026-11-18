import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/retail_cart_stock.dart';
import 'package:facturavoz/models.dart';

Product _product(double? stock) => Product(
  id: 'sku', name: 'Agua', unitPrice: 2.5, unit: 'NIU',
  active: true, stock: stock,
);

void main() {
  test('se puede agotar la última unidad sin pasar a negativo', () {
    expect(exceedsKnownRetailStock(_product(3), 2, 1), isFalse);
    expect(exceedsKnownRetailStock(_product(3), 2, 2), isTrue);
    expect(exceedsKnownRetailStock(_product(0), 0, 1), isTrue);
  });

  test('los productos sin seguimiento (stock NULL) siguen vendiéndose', () {
    expect(exceedsKnownRetailStock(_product(null), 500, 100), isFalse);
  });

  test('retirar del carrito no se bloquea incluso con saldo antiguo', () {
    expect(exceedsKnownRetailStock(_product(0), 2, -1), isFalse);
  });

  test('las cantidades fraccionarias respetan el inventario conocido', () {
    expect(exceedsKnownRetailStock(_product(1.5), 1, .5), isFalse);
    expect(exceedsKnownRetailStock(_product(1.5), 1, .6), isTrue);
  });
}
