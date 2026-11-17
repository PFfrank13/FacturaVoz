import 'package:facturavoz/logic/catalog_link.dart';
import 'package:facturavoz/models.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, String name, {bool active = true, double price = 3}) => Product(id: id, name: name, unitPrice: price, unit: 'NIU', active: active, stock: 10);

void main() {
  final catalog = [_p('agua', 'Agua 625 ml'), _p('arroz', 'Arroz 1kg', price: 4.5), _p('viejo', 'Pan', active: false)];

  test('vincula solo con el nombre exacto (sin mayúsculas ni espacios extra)', () {
    final out = linkToCatalog([LineItem(description: '  agua   625 ML ', quantity: 2)], catalog);
    expect(out.single.productId, 'agua');
    expect(out.single.unitPrice, 3, reason: 'sin precio dictado toma el del catálogo');
  });

  test('una descripción parecida NO se vincula (nunca adivina)', () {
    final out = linkToCatalog([LineItem(description: 'agua', quantity: 1), LineItem(description: 'Arroz', quantity: 1)], catalog);
    expect(out.map((i) => i.productId), everyElement(isNull));
  });

  test('productos inactivos no se vinculan', () {
    expect(linkToCatalog([LineItem(description: 'Pan')], catalog).single.productId, isNull);
  });

  test('respeta el precio dictado y una vinculación previa', () {
    final out = linkToCatalog([LineItem(description: 'Arroz 1kg', unitPrice: 5), LineItem(description: 'X', productId: 'manual')], catalog);
    expect(out.first.productId, 'arroz');
    expect(out.first.unitPrice, 5);
    expect(out.last.productId, 'manual');
  });

  test('si hubiera dos productos con el mismo nombre, no vincula ninguno', () {
    final dup = [_p('a', 'Gaseosa'), _p('b', 'gaseosa')];
    expect(linkToCatalog([LineItem(description: 'Gaseosa')], dup).single.productId, isNull);
  });
}
