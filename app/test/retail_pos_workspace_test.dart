import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/ui/retail_pos_workspace.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  test('panel de carrito solo en el espacio real disponible', () {
    for (final width in [320.0, 360.0, 600.0, 840.0, 899.0]) {
      expect(retailPosUseSideCart(width), isFalse, reason: 'ancho $width');
    }
    for (final width in [900.0, 1040.0, 1280.0, 1440.0]) {
      expect(retailPosUseSideCart(width), isTrue, reason: 'ancho $width');
    }
    expect(retailPosUseSideCart(double.infinity), isFalse);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('carrito enterprise muestra importes reales y abre la revisión en $brightness', (tester) async {
      var reviews = 0;
      final lines = [
        LineItem(description: 'Agua sin gas 600 ml', quantity: 2, unitPrice: 3.5, productId: 'sku-agua'),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness),
        home: Scaffold(body: Center(child: SizedBox(
          width: 320,
          height: 560,
          child: RetailPosCartPane(
            lines: lines,
            totals: computeTotals(lines, 18),
            currency: 'PEN',
            onReview: () => reviews++,
          ),
        ))),
      ));
      expect(find.byKey(const ValueKey('retail-pos-desktop-cart')), findsOneWidget);
      expect(find.text('Agua sin gas 600 ml'), findsOneWidget);
      expect(find.text('2 × S/ 3.50'), findsOneWidget);
      expect(find.textContaining('8.26'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('retail-pos-desktop-charge')));
      await tester.pump();
      expect(reviews, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('venta vacía bloquea el cobro y muestra guía', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: Center(child: SizedBox(
        width: 320,
        height: 560,
        child: RetailPosCartPane(
          lines: [],
          totals: Totals(0, 0, 0),
          currency: 'PEN',
          onReview: null,
        ),
      ))),
    ));
    expect(find.text('Tu venta comienza aquí'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('retail-pos-desktop-charge')));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('carrito lateral ajusta y retira SKU mediante el controlador protegido', (tester) async {
    final deltas = <double>[];
    final line = LineItem(
      description: 'Agua sin gas', quantity: 2, unitPrice: 3.5, productId: 'sku-agua',
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(
        width: 320, height: 560,
        child: RetailPosCartPane(
          lines: [line],
          totals: computeTotals([line], 18),
          currency: 'PEN',
          onReview: null,
          onQuantityChange: (id, delta) {
            expect(id, 'sku-agua');
            deltas.add(delta);
          },
        ),
      ))),
    ));
    await tester.tap(find.byKey(const ValueKey('retail-pos-qty-plus-sku-agua')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('retail-pos-qty-minus-sku-agua')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('retail-pos-qty-remove-sku-agua')));
    await tester.pump();
    expect(deltas, [1.0, -1.0, -2.0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reducir una fracción no produce cantidades negativas', (tester) async {
    final deltas = <double>[];
    final line = LineItem(description: 'Producto por peso',
      quantity: 0.5, unitPrice: 10, productId: 'sku-peso');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(
        width: 320, height: 560,
        child: RetailPosCartPane(
          lines: [line],
          totals: computeTotals([line], 18),
          currency: 'PEN',
          onReview: null,
          onQuantityChange: (id, delta) => deltas.add(delta),
        ),
      ))),
    ));
    await tester.tap(find.byKey(const ValueKey('retail-pos-qty-minus-sku-peso')));
    await tester.pump();
    expect(deltas, [-0.5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso de edición no se muestran controles de cantidad', (tester) async {
    final line = LineItem(description: 'Agua',
      quantity: 1, unitPrice: 2, productId: 'sku-agua');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: Center(child: SizedBox(
        width: 320, height: 560,
        child: RetailPosCartPane(
          lines: [line], totals: computeTotals([line], 18),
          currency: 'PEN', onReview: null,
        ),
      ))),
    ));
    expect(find.byKey(const ValueKey('retail-pos-qty-plus-sku-agua')), findsNothing);
    expect(find.byKey(const ValueKey('retail-pos-qty-remove-sku-agua')), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
