import 'package:facturavoz/ui/cash_luxe_widgets.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 768.0, 1024.0]) {
      testWidgets('Caja Luxe es responsive: ${brightness.name}, ${width}dp',
        (tester) async {
          tester.view.physicalSize = Size(width, 820);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            theme: buildTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.3)),
              child: Scaffold(body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: const [
                  FvCashJourney(opened: true, movements: 2, closed: false),
                  SizedBox(height: 16),
                  FvCashBlindPanel(),
                  SizedBox(height: 16),
                  FvCashMovementTile(
                    kind: 'ingreso',
                    label: 'Ingreso de efectivo',
                    amount: 'S/ 25.00',
                    time: '20/11 11:00',
                  ),
                ]),
              )),
            ),
          ));
          await tester.pumpAndSettle();
          expect(find.text('Arqueo ciego'), findsOneWidget);
          expect(find.text('Pendiente'), findsOneWidget);
          expect(find.text('S/ 25.00'), findsOneWidget);
          expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Panel ciego no revela saldo ni calculos monetarios', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: Center(child: SizedBox(
        width: 290, child: FvCashBlindPanel(),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('saldo esperado'), findsOneWidget);
    expect(find.textContaining('S/'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Caja respeta reducir movimiento', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: SizedBox(
          width: 340,
          child: FvCashJourney(opened: true, movements: 0, closed: false),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
