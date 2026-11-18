import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/shell.dart';

void main() {
  test('Ocho rubros conservan dock móvil y cambian a rail desde 700 dp', () {
    for (final rubro in <String>[
      'restaurante', 'salon', 'consultorio', 'taller',
      'servicios_tecnicos', 'mayorista', 'educacion', 'construccion',
    ]) {
      for (final width in [320.0, 360.0, 600.0, 699.0]) {
        expect(usesMultirubroRail(rubro, width), isFalse,
          reason: '$rubro en $width dp');
      }
      for (final width in [700.0, 768.0, 1024.0, 1920.0, 3440.0]) {
        expect(usesMultirubroRail(rubro, width), isTrue,
          reason: '$rubro en $width dp');
      }
    }
  });

  test('La navegación única de Bodega conserva su propio rail', () {
    expect(usesMultirubroRail('bodega', 320), false);
    expect(usesMultirubroRail('bodega', 1024), false);
    expect(bodegaUsesPermanentSidebar(1024), true);
    expect(bodegaUsesPermanentSidebar(360), false);
    expect(usesMultirubroRail('restaurante', double.infinity), false);
  });
}
