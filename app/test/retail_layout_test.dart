import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/ui/retail_layout.dart';

void main() {
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
