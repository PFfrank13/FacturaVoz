import 'package:facturavoz/ui/credit_luxe_widgets.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 768.0, 1024.0]) {
      testWidgets('Fiados Luxe se adapta: ${brightness.name} $width dp',
          (tester) async {
        tester.view.physicalSize = Size(width, 830);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.35)),
            child: Scaffold(body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: const [
                FvCreditBalanceCard(
                  name: 'María Fernanda de la Cruz Contreras',
                  amount: 'S/ 1,250.00',
                  hasBalance: true,
                  overdue: true,
                  overLimit: true,
                  dueLabel: 'Vencido desde 18/11/2026',
                  lastMovement: '19/11/2026',
                ),
                SizedBox(height: 12),
                FvCreditBalanceCard(
                  name: 'Cliente con saldo pagado',
                  amount: 'S/ 0.00',
                  hasBalance: false,
                  overdue: true,
                  overLimit: true,
                  dueLabel: 'Vencido desde 15/11/2026',
                ),
              ]),
            )),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Vencido'), findsOneWidget);
        expect(find.text('Al día'), findsOneWidget);
        expect(find.text('Vencido desde 15/11/2026'), findsNothing);
        expect(find.text('S/ 1,250.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Fiados muestra el estado real sin asumir pagos', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: Center(child: SizedBox(
        width: 280,
        child: FvCreditBalanceCard(
          name: 'Cliente de ejemplo',
          amount: 'S/ 30.00',
          hasBalance: true,
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('SALDO PENDIENTE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
