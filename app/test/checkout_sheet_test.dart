import 'package:facturavoz/ui/checkout_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('efectivo insuficiente bloquea; calcula vuelto y confirma una vez', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CheckoutSheet(
      total: 23.6, currency: 'PEN', onMore: () {}, onConfirm: (method) {
        expect(method, 'efectivo'); calls++;
      },
    ))));
    await tester.enterText(find.byType(TextField), '20');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '50,00');
    await tester.pump();
    expect(find.textContaining('26.40'), findsOneWidget);
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
  testWidgets('cobro pendiente conserva método y permite recuperar sin pedir efectivo otra vez', (tester) async {
    String? method;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CheckoutSheet(
      total: 23.6, currency: 'PEN', pendingMethod: 'yape', onMore: () {}, onConfirm: (value) => method = value,
    ))));
    expect(find.byType(TextField), findsNothing);
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.onSelected, isNull);
    }
    await tester.tap(find.text('Reintentar mismo cobro'));
    expect(method, 'yape');
  });
  for (final width in [320.0, 768.0]) {
    testWidgets('cobro accesible a $width con teclado y texto ampliado', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700), viewInsets: const EdgeInsets.only(bottom: 260), textScaler: const TextScaler.linear(1.6)),
        child: Scaffold(body: CheckoutSheet(total: 10, currency: 'PEN', onConfirm: (_) {}, onMore: () {})),
      )));
      await tester.enterText(find.byType(TextField), '20');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar cobro'));
      expect(find.text('Confirmar cobro').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
