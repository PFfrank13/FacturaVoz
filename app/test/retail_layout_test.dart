import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/ui/retail_layout.dart';

void main() {
  test('Tarjetas: un panel estrecho, dos columnas si caben', () {
    for (final width in <double>[0, 320, 360, 600, 768, 879.9]) {
      expect(retailCardColumnCount(width), 1, reason: '$width');
    }
    for (final width in <double>[880, 1024, 1440, 3440]) {
      expect(retailCardColumnCount(width), 2, reason: '$width');
    }
    expect(retailCardColumnCount(double.infinity), 1);
    expect(retailCardColumnCount(double.nan), 1);
    expect(retailCardColumnCount(819, twoColumnMinWidth: 820), 1);
    expect(retailCardColumnCount(820, twoColumnMinWidth: 820), 2);
  });

  testWidgets('Los listados usan todo el móvil y no se estiran en escritorio', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in <double>[320, 360, 768, 1024, 1440, 1920, 3440]) {
      tester.view.physicalSize = Size(width, 780);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RetailResponsiveFrame(
            maxWidth: 1120,
            child: ListView(children: const [Text('Contenido real')]),
          ),
        ),
      ));

      expect(tester.getSize(find.byType(ListView)).width,
          closeTo(width < 1120 ? width : 1120, 0.1),
          reason: 'Ancho físico lógico $width');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Respeta el ancho de paneles divididos, no el de la ventana', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 420,
            height: 520,
            child: RetailResponsiveFrame(
              maxWidth: 1120,
              child: ListView(children: const [Text('Panel')]),
            ),
          ),
        ),
      ),
    ));

    expect(tester.getSize(find.byType(ListView)).width, 420);
    expect(tester.takeException(), isNull);
  });
}
