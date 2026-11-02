import 'package:facturavoz/logic/sample_catalog.dart';
import 'package:facturavoz/rubros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Todos los rubros tienen productos de ejemplo válidos', () {
    for (final id in proStar.keys) {
      final l = sampleCatalog[id];
      expect(l, isNotNull, reason: 'sin ejemplos para $id');
      expect(l!.length, greaterThanOrEqualTo(4));
      final names = <String>{};
      for (final s in l) {
        expect(s.name.trim(), isNotEmpty);
        expect(s.price, greaterThan(0));
        expect(s.category.trim(), isNotEmpty);
        expect(s.emoji, isNotEmpty);
        expect(names.add(s.name.toLowerCase()), isTrue, reason: 'repetido en $id: ${s.name}');
      }
    }
  });

  test('tileEmoji usa el de ejemplo y, si no, palabras clave', () {
    expect(tileEmoji('Ceviche'), '🐟');
    expect(tileEmoji('Gaseosa grande'), '🥤');
    expect(tileEmoji('Cosa rara', 'Sin pista'), isNull);
  });
}
