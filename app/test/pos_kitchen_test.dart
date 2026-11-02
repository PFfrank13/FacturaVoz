import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/pos_kitchen.dart';

void main() {
  test('La misma nota se serializa independiente del nombre de plato', () {
    const line = KitchenDraftItem(
      description: 'Lomo saltado', quantity: 2, unitPrice: 18, note: '  sin cebolla  ',
    );
    expect(line.toJson(), {
      'description': 'Lomo saltado',
      'quantity': 2,
      'unit_price': 18,
      'note': 'sin cebolla',
    });
  });

  test('Id de reintento cumple formato UUID v4 y cambia entre pedidos', () {
    final a = newKitchenRequestId();
    final b = newKitchenRequestId();
    final v4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(v4.hasMatch(a), isTrue);
    expect(v4.hasMatch(b), isTrue);
    expect(a, isNot(b));
  });
}
