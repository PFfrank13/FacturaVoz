import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/screens/pos_payment_success.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('Carrito Bodega ${brightness.name} ${width}px x1.4',
          (tester) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final items = [
          LineItem(productId: 'p1', description: 'Aceite vegetal botella grande',
            quantity: 2, unitPrice: 9.50),
        ];
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: PosCartReviewScreen(
              currency: 'PEN', taxRate: 18,
              lines: () => items, productImages: const {},
              onChangeQuantity: (id, delta) {
                items.first.quantity += delta;
              },
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Carrito de venta'), findsOneWidget);
        expect(find.byKey(const ValueKey('retail-continue-payment')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Cobro exitoso ${brightness.name} ${width}px x1.4',
          (tester) async {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: const PosPaymentSuccessScreen(
              invoiceId: 'id-prueba',
              method: 'efectivo',
              currency: 'PEN',
              total: 24.50,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Cobro registrado'), findsOneWidget);
        expect(find.text('Venta registrada y cobrada'), findsOneWidget);
        expect(find.text('Emitir boleta'), findsOneWidget);
        // Lista perezosa: en pantallas estrechas, el botón de impresión se
        // construye al desplazar la vista. Debe seguir siendo alcanzable.
        await tester.scrollUntilVisible(
          find.text('Imprimir ticket'),
          175,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Imprimir ticket'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Pantalla efectivo conserva confirmación manual y vuelto',
      (tester) async {
    PosPaymentApproval? approval;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(builder: (context) => Scaffold(body: Center(
        child: FilledButton(
          onPressed: () async {
            approval = await confirmPosPayment(context,
              method: 'efectivo', currency: 'PEN', total: 7.85);
          },
          child: const Text('Iniciar cobro'),
        ),
      ))),
    ));
    await tester.tap(find.text('Iniciar cobro'));
    await tester.pumpAndSettle();
    expect(find.text('Cobro efectivo'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '10.00');
    await tester.pumpAndSettle();
    expect(find.textContaining('Vuelto:'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirmar pago'));
    await tester.tap(find.text('Confirmar pago'));
    await tester.pumpAndSettle();
    expect(approval?.method, 'efectivo');
    expect(approval?.note, contains('Vuelto:'));
    expect(tester.takeException(), isNull);
  });
}
