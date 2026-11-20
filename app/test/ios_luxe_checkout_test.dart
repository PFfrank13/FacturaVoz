import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0]) {
      testWidgets('Tarjetas de pago iOS Luxe: ${brightness.name}, ${width}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var method = '';
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(body: Center(child: SizedBox(
              height: 155,
              child: Row(children: [
                Expanded(child: PosPaymentMethodCard(
                  method: 'efectivo', selected: true,
                  onSelected: () => method = 'efectivo')),
                const SizedBox(width: 9),
                Expanded(child: PosPaymentMethodCard(
                  method: 'tarjeta', selected: false,
                  onSelected: () => method = 'tarjeta')),
              ]),
            ))),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Efectivo'), findsOneWidget);
        expect(find.text('Tarjeta'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Tarjeta'));
        expect(method, 'tarjeta');
      });

      testWidgets('Carrito mantiene controles táctiles: ${brightness.name}, ${width}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 810);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final items = <LineItem>[
          LineItem(productId: 'producto-1',
            description: 'Aceite vegetal botella grande',
            quantity: 2, unitPrice: 9.50),
        ];
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: PosCartReviewScreen(
              currency: 'PEN', taxRate: 18,
              lines: () => items,
              onChangeQuantity: (id, delta) {
                if (id == 'producto-1') items.first.quantity += delta;
              },
              productImages: const {},
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final add = find.byTooltip('Agregar uno');
        final remove = find.byTooltip('Quitar uno');
        expect(add, findsOneWidget);
        expect(remove, findsOneWidget);
        expect(tester.getSize(add).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
        // El resumen de cobro queda fijado abajo: desplazar el carrito antes
        // de tocar una cantidad con texto ampliado en pantallas estrechas.
        await tester.ensureVisible(add);
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(items.first.quantity, 3);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Pago respeta reducción de movimiento', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: SizedBox(
          width: 150, height: 145,
          child: PosPaymentMethodCard(
            method: 'efectivo', selected: true, onSelected: () {}),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
