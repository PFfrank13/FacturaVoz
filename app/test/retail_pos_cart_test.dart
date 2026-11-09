import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';

void main() {
  testWidgets('Retail cart updates quantities and always exposes payment action', (tester) async {
    final cart = <LineItem>[
      LineItem(productId: 'p1', description: 'Aceite vegetal 1 L', quantity: 1, unitPrice: 9.50),
      LineItem(productId: 'p2', description: 'Agua mineral 625 ml', quantity: 1, unitPrice: 1.80),
    ];
    await tester.pumpWidget(MaterialApp(
      home: PosCartReviewScreen(
        lines: () => cart,
        currency: 'PEN',
        taxRate: 18,
        productImages: const {},
        onChangeQuantity: (id, delta) {
          final line = cart.where((x) => x.productId == id).first;
          line.quantity += delta;
          cart.removeWhere((x) => x.quantity <= 0);
        },
      ),
    ));
    expect(find.text('Carrito de venta'), findsOneWidget);
    expect(find.byKey(const ValueKey('retail-continue-payment')), findsOneWidget);
    expect(find.textContaining('13.33'), findsOneWidget); // 11.30 + IGV 2.03

    await tester.tap(find.byTooltip('Agregar uno').first);
    await tester.pumpAndSettle();
    expect(cart.first.quantity, 2);
    expect(find.textContaining('24.54'), findsOneWidget); // 20.80 + IGV 3.74

    await tester.tap(find.byTooltip('Quitar uno').first);
    await tester.pumpAndSettle();
    expect(cart.first.quantity, 1);
    expect(find.textContaining('13.33'), findsOneWidget);
  });

  testWidgets('Retail cart cannot proceed when empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PosCartReviewScreen(
        lines: () => const [],
        currency: 'PEN', taxRate: 18,
        productImages: const {},
        onChangeQuantity: (_, _) {},
      ),
    ));
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.byKey(const ValueKey('retail-continue-payment')),
        matching: find.byType(FilledButton),
      ).first,
    );
    expect(button.onPressed, isNull);
  });
}
