import 'package:facturavoz/rubros.dart';
import 'package:facturavoz/ux/rubro_experience.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada rubro tiene una guía comprensible y tres pasos', () {
    expect(rubroExperiences.keys.toSet(), rubros.map((r) => r.id).toSet());
    for (final r in rubros) {
      final guide = experienceFor(r.id);
      expect(guide.homeTitle.trim(), isNotEmpty, reason: r.id);
      expect(guide.homeSubtitle.trim(), isNotEmpty, reason: r.id);
      expect(guide.menuSubtitle.trim(), isNotEmpty, reason: r.id);
      expect(guide.steps.length, 3, reason: r.id);
      expect(guide.steps.every((s) => s.trim().isNotEmpty), isTrue, reason: r.id);
    }
  });

  test('ninguna herramienta del rubro desaparece del menú simplificado', () {
    for (final r in rubros) {
      final visible = <String>{...r.featureIds, ...commonFeatures};
      final originalAreas = {for (final a in r.areas) ...a.features};
      final extras = extraMenuFeatureIds(r, visible).toSet();
      expect({...originalAreas, ...extras}.containsAll(visible), isTrue, reason: r.id);
      expect(extras.intersection(originalAreas), isEmpty, reason: r.id);
    }
  });

  test('la interfaz cambia textos pero mantiene todos los accesos existentes', () {
    for (final r in rubros) {
      expect(r.home.length, greaterThanOrEqualTo(3));
      expect(r.areas, isNotEmpty);
      expect(r.signature, isNotEmpty);
    }
    expect(shortActionLabel('margen_obra', 'Márgenes'), 'Costos de obra');
    expect(shortActionLabel('platos', 'Costos'), 'Cuentas');
    expect(simpleAreaTitle('Plata'), 'Cobros y caja');
  });
}
