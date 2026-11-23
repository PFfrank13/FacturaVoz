import 'package:facturavoz/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('venta por monto: S/ 2 de azúcar a S/ 4.50 el kilo son 0.44 kg', () {
    expect(weightFor(amount: 2, pricePerKilo: 4.5), 0.44);
  });
  test('venta por kilos se redondea a 10 g', () {
    expect(weightFor(kilos: 0.257, pricePerKilo: 4.5), 0.26);
    expect(weightFor(kilos: 1, pricePerKilo: 0), 1);
  });
  test('nada que vender si no alcanza para 10 g o falta el precio', () {
    expect(weightFor(amount: 0.01, pricePerKilo: 4.5), isNull);
    expect(weightFor(amount: 2, pricePerKilo: 0), isNull);
    expect(weightFor(kilos: -1, pricePerKilo: 4.5), isNull);
    expect(weightFor(pricePerKilo: 4.5), isNull);
  });
  test('un producto KGM se vende por peso', () {
    final p = Product.fromJson({'id': 'a', 'name': 'Azúcar rubia', 'unit_price': 4.5, 'unit': 'KGM', 'active': true});
    expect(p.byWeight, isTrue);
    expect(p.isService, isFalse);
  });
}
