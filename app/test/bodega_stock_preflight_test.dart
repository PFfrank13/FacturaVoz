import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/bodega_stock_preflight.dart';

void main() {
  test('permite venta con existencias suficientes', () {
    expect(firstInsufficientBodegaSku(
      {'a': 2, 'b': 1},
      {'a': 2, 'b': 10},
    ), isNull);
  });

  test('suma la cantidad por SKU antes de comparar', () {
    // El carrito agrupa cantidades, no nombres de artículo.
    expect(firstInsufficientBodegaSku(
      {'sku-a': 3, 'sku-b': 2},
      {'sku-a': 2, 'sku-b': 10},
    ), 'sku-a');
  });

  test('producto sin seguimiento (stock nulo) se puede vender', () {
    expect(firstInsufficientBodegaSku({'service': 100}, {'service': null}), isNull);
  });

  test('producto faltante, borrado o desactivado no puede pasar preflight', () {
    expect(firstInsufficientBodegaSku({'missing': 1}, const {}), 'missing');
  });

  test('saldo negativo, cero, NaN y cantidad inválida se rechazan', () {
    expect(firstInsufficientBodegaSku({'a': 1}, {'a': -1}), 'a');
    expect(firstInsufficientBodegaSku({'a': 1}, {'a': 0}), 'a');
    expect(firstInsufficientBodegaSku({'a': 1}, {'a': double.nan}), 'a');
    expect(firstInsufficientBodegaSku({'a': 0}, {'a': 4}), 'a');
  });
}
