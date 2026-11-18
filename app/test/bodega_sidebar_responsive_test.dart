import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/shell.dart';

void main() {
  test('Bodega muestra Drawer superpuesto solo por debajo de 700dp', () {
    for (final width in [320.0, 360.0, 412.0, 600.0, 699.0]) {
      expect(bodegaUsesPermanentSidebar(width), isFalse,
          reason: 'ancho de pantalla $width');
    }
  });

  test('Bodega usa un único NavigationRail desde tablet', () {
    for (final width in [700.0, 768.0, 980.0, 1024.0, 1280.0, 1440.0, 1920.0]) {
      expect(bodegaUsesPermanentSidebar(width), isTrue,
          reason: 'ancho de pantalla $width');
    }
  });
}
