import 'package:facturavoz/ui/inventory_product_card.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 768.0, 1024.0]) {
      testWidgets('Inventario premium accesible: ${brightness.name}, ${width}dp',
          (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var opened = 0;
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3)),
            child: Scaffold(body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FvInventoryProductCard(
                  name: 'Aceite de oliva extravirgen botella de 500 ml',
                  price: '17.90',
                  category: 'Abarrotes',
                  barcode: '7750099887766',
                  isService: false,
                  active: true,
                  stockLabel: 'Stock 3',
                  lowStock: true,
                  marginLabel: 'Margen 25 %',
                  onOpen: () => opened++,
                ),
              ),
            )),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Stock bajo'), findsOneWidget);
        expect(find.text('17.90'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Aceite de oliva extravirgen botella de 500 ml'));
        await tester.pumpAndSettle();
        expect(opened, 1);
      });
    }
  }

  testWidgets('Solo lectura no abre el producto', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: Center(child: SizedBox(
        width: 280,
        child: FvInventoryProductCard(
          name: 'Servicio sin permisos de edición',
          price: '25.00',
          isService: true,
          active: false,
          stockLabel: null,
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Archivado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventario respeta reducir animaciones', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: SizedBox(
          width: 280,
          child: FvInventoryProductCard(
            name: 'Agua mineral 625 ml',
            price: '1.80',
            isService: false,
            active: true,
          ),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
