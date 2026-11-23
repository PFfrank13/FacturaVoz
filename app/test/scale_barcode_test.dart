import 'package:facturavoz/logic/scale_barcode.dart';
import 'package:flutter_test/flutter_test.dart';

String withCheck(String twelve) => '$twelve${ean13Check(twelve)}';

void main() {
  test('lee PLU y peso de una etiqueta de balanza', () {
    final code = withCheck('210012301250'); // PLU 00123, 1250 g
    final l = parseScaleLabel(code)!;
    expect(l.plu, '00123');
    expect(l.prefixPlu, '2100123');
    expect(l.kilos, 1.25);
  });

  test('rechaza códigos normales, dígito de control malo o peso cero', () {
    expect(parseScaleLabel('7751234567890'), isNull);
    final good = withCheck('210012301250');
    final bad = '${good.substring(0, 12)}${(int.parse(good[12]) + 1) % 10}';
    expect(parseScaleLabel(bad), isNull);
    expect(parseScaleLabel(withCheck('210012300000')), isNull);
  });

  test('empareja con el código guardado en el producto', () {
    final l = parseScaleLabel(withCheck('210012301250'))!;
    expect(matchesScaleProduct('00123', l), isTrue);
    expect(matchesScaleProduct('123', l), isTrue);
    expect(matchesScaleProduct('2100123', l), isTrue);
    expect(matchesScaleProduct('7751234567890', l), isFalse);
  });

  test('dígito de control EAN-13 conocido', () {
    expect(ean13Check('400638133393'), 1); // 4006381333931, ejemplo clásico de EAN-13
  });
}
