import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('home premium real sin overflow en $width', (tester) async {
      tester.view.physicalSize = Size(width, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var goalTap = false;
      final nav = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: RetailPremiumOverview(
              name: 'Solvex',
              currencySymbol: 'S/',
              salesAmount: 29.50,
              salesCount: 2,
              drafts: 1,
              todayAmount: 0,
              todayCount: 0,
              loaded: true,
              showMonth: true,
              onGoal: () => goalTap = true,
              chart: const SizedBox(height: 48),
            )),
            RetailHomeQuickActions(
              allowed: const {'sell','stock','comprobantes','cash','fiados'},
              onNavigate: nav.add,
            ),
            const Padding(padding: EdgeInsets.all(12),
              child: RetailHomeStat(
                label: 'Estado de mi caja',
                value: 'Sin abrir',
                detail: 'Toca para abrir la caja',
                icon: Icons.point_of_sale_outlined,
                tint: RetailAccent.amber)),
          ]),
        )),
      ));
      expect(find.byKey(const ValueKey('bodega-enterprise-overview')),
          findsOneWidget);
      expect(find.text('S/ 29.50'), findsOneWidget);
      expect(find.text('2 ventas emitidas'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('bodega-goal-action')));
      expect(goalTap, isTrue);
      await tester.tap(find.byKey(const ValueKey('retail-home-quick-sell')));
      expect(nav, ['sell']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('dock comercial táctil en $width dp', (tester) async {
      tester.view.physicalSize = Size(width, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navigated = <String>[];
      var more = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(bottomNavigationBar: RetailPremiumBottomDock(
          current: 'home',
          items: const [
            ('home', 'Inicio', Icons.home_rounded),
            ('sell', 'Ventas', Icons.shopping_cart_outlined),
            ('stock', 'Inventario', Icons.inventory_2_outlined),
            ('cash', 'Caja', Icons.point_of_sale_outlined),
          ],
          onNavigate: navigated.add,
          onMore: () => more = true,
        )),
      ));
      expect(find.byKey(const ValueKey('bodega-premium-bottom-dock')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bodega-dock-sell')));
      await tester.pump();
      expect(navigated, ['sell']);
      await tester.tap(find.byKey(const ValueKey('bodega-dock-more')));
      expect(more, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('los accesos se ocultan sin permisos', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: RetailHomeQuickActions(
        allowed: const {'stock'},
        onNavigate: (_) {},
      )),
    ));
    expect(find.byKey(const ValueKey('retail-home-quick-stock')), findsOneWidget);
    expect(find.byKey(const ValueKey('retail-home-quick-sell')), findsNothing);
  });
}
