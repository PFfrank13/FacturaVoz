import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/shell.dart';

void main() {
  test('Bodega muestra Drawer superpuesto en móvil y tablet compacta', () {
    for (final width in [320.0, 360.0, 412.0, 600.0, 768.0, 979.0]) {
      expect(bodegaUsesPermanentSidebar(width), isFalse,
          reason: 'ancho de pantalla $width');
    }
  });

  test('Bodega usa un único menú lateral fijo en escritorio', () {
    for (final width in [980.0, 1024.0, 1280.0, 1440.0, 1920.0]) {
      expect(bodegaUsesPermanentSidebar(width), isTrue,
          reason: 'ancho de pantalla $width');
    }
  });
}
