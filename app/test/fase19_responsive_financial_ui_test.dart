import 'package:facturavoz/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in <double>[280, 320, 390, 768]) {
    for (final scale in <double>[1, 1.6, 2]) {
      testWidgets('Financial row adapts to $width at text scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: Padding(
              padding: EdgeInsets.all(12),
              child: DataRow2(
                'Importe pendiente de comprobantes por cobrar',
                'S/ 123,456.78',
                strong: true,
              ),
            )),
          ),
        ));
        expect(find.text('S/ 123,456.78'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Empty state honors reduced motion', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SingleChildScrollView(
          child: EmptyState(title: 'Sin ventas', body: 'Registra tu primera venta'),
        )),
      ),
    ));
    expect(find.text('Sin ventas'), findsOneWidget);
    expect(find.text('Registra tu primera venta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
