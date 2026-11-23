import 'package:facturavoz/services/product_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acepta códigos de barras reales y rechaza basura', () {
    expect(isValidCode('7751234567892'), isTrue);
    expect(isValidCode('ABC-12.5'), isTrue);
    expect(isValidCode('123'), isFalse);
    expect(isValidCode('código con espacios'), isFalse);
  });
  test('el aviso dice de qué producto es el código', () {
    expect(codeTakenMessage('7751234567892', 'Papel Noble'), contains('«Papel Noble»'));
    expect(codeTakenMessage('7751234567892', null), contains('ya es de otro producto'));
  });
}
