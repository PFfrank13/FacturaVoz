import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/retail_basic_modules.dart';

void main() {
  test('tarjetas de Bodega crecen con accesibilidad sin desbordar por altura rígida', () {
    for (final width in [320.0, 360.0, 480.0, 600.0, 840.0, 1200.0]) {
      final normal = retailDashboardCardExtent(width, 1);
      final accessible = retailDashboardCardExtent(width, 1.4);
      final large = retailDashboardCardExtent(width, 2);
      expect(accessible, greaterThan(normal), reason: 'ancho $width');
      expect(large, greaterThan(accessible), reason: 'ancho $width');
      expect(normal, greaterThanOrEqualTo(164));
    }
  });

  test('móvil compacto reserva más espacio y escala extrema queda acotada', () {
    expect(retailDashboardCardExtent(320, 1),
        greaterThan(retailDashboardCardExtent(600, 1)));
    expect(retailDashboardCardExtent(320, 4),
        retailDashboardCardExtent(320, 3));
  });
}
