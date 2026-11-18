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
    for (final width in [1040.0, 1280.0, 1440.0]) {
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
}
