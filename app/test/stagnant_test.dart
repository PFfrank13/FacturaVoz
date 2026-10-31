import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/stagnant.dart';
import 'package:facturavoz/models_pro.dart';

ProductVelocity v(String n, double? stock, double units) => ProductVelocity(id: n, name: n, stock: stock, reorderPoint: null, units: units, perDay: units / 30);

void main() {
  test('solo productos con stock y sin ventas, los de más stock primero', () {
    final r = stagnantProducts([v('a', 5, 0), v('b', 20, 0), v('c', 10, 3), v('d', 0, 0), v('e', null, 0)]);
    expect(r.map((e) => e.name), ['b', 'a']);
  });

  test('respeta el límite', () {
    final all = [for (var i = 1; i <= 20; i++) v('p$i', i.toDouble(), 0)];
    final r = stagnantProducts(all, limit: 5);
    expect(r.length, 5);
    expect(r.first.name, 'p20');
  });
}
