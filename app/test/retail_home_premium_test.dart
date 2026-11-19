import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/ds.dart';
import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in <double>[320, 390, 768, 1024]) {
    for (final brightness in Brightness.values) {
      testWidgets('Inicio premium muestra cifras reales y no desborda a $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(
                textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    RetailPremiumHero(
                      name: 'Bodega de la esquina, empresa de nombre largo',
                      currency: 'PEN',
                      total: 29.50,
                      count: 2,
                      drafts: 1,
                      loaded: true,
                      showMonth: true,
                      todayTotal: 0,
                      goal: null,
                      series: const <double>[0, 0, 0, 29.5, 0, 0],
                      onGoal: () {},
                    ),
                    const SizedBox(height: 18),
                    const DsStat(
                      label: 'Ventas de hoy', value: 'S/ 0.00',
                      detail: '0 ventas',
                      accent: Color(0xFF527CC2),
                      icon: Icons.trending_up_rounded,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('bodega-enterprise-overview')),
            findsOneWidget);
        expect(find.text('S/ 29.50'), findsOneWidget);
        expect(find.text('2 ventas emitidas'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('los atajos usan el callback de MainShell, sin navegación duplicada',
      (tester) async {
    String? destination;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: RetailHomeShortcuts(
          items: const [
            RetailHomeShortcut('sell', 'Venta rápida',
                Icons.shopping_bag_rounded, Color(0xFFD97763)),
            RetailHomeShortcut('stock', 'Inventario',
                Icons.inventory_2_rounded, Color(0xFF5785C6)),
          ],
          onSelect: (id) => destination = id,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('retail-home-open-sell')));
    await tester.pump();
    expect(destination, 'sell');
    expect(tester.takeException(), isNull);
  }

  testWidgets('la cifra mensual no se expone sin permiso de reportes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: RetailPremiumHero(
          name: 'Tienda', currency: 'PEN',
          total: 900000, count: 50,
          loaded: true, showMonth: false,
          series: const [], goal: null, onGoal: () {},
        ),
      ),
    ));
    expect(find.text('S/ 900,000.00'), findsNothing);
    expect(find.byKey(const ValueKey('retail-home-real-month-total')),
        findsNothing);
  });
}
