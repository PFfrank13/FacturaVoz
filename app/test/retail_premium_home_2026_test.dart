import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cero, meta y métricas legibles con letra grande en modo oscuro', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4), disableAnimations: true),
        child: Scaffold(body: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(16), child: Column(children: [
            RetailPremiumOverview(
              name: 'Mercado Oliva', currencySymbol: 'S/', salesAmount: 0, salesCount: 0,
              drafts: 0, todayAmount: null, todayCount: null, loaded: true, showMonth: true,
              goalPercent: 0, onGoal: () {}, chart: null,
            ),
            RetailHomeStatGrid(children: [
              RetailHomeStat(label: 'Estado de mi caja', value: 'Sin abrir',
                detail: 'Toca para abrir la caja', icon: Icons.point_of_sale_rounded,
                tint: RetailAccent.amber, onTap: () => opened = true),
              const RetailHomeStat(label: 'Stock bajo', value: '0', detail: 'Todo en orden',
                icon: Icons.inventory_2_rounded, tint: RetailAccent.teal),
            ]),
          ]),
        ))),
      ),
    ));
    expect(find.text('S/ 0.00'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 ventas emitidas'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Stock bajo')).dy,
      greaterThan(tester.getBottomLeft(find.text('Toca para abrir la caja')).dy));
    await tester.tap(find.text('Sin abrir'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso de reportes se muestra solo la actividad diaria', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RetailPremiumOverview(
      name: 'Mercado Oliva', currencySymbol: 'S/', salesAmount: 831.60, salesCount: 18,
      drafts: 5, todayAmount: null, todayCount: 2, loaded: true, showMonth: false,
      goalPercent: .5, onGoal: () {}, chart: const Text('Tendencia privada'),
    ))));
    expect(find.text('Hoy 2 ventas'), findsOneWidget);
    expect(find.text('S/ 831.60'), findsNothing);
    expect(find.text('18 ventas emitidas'), findsNothing);
    expect(find.text('5 borradores'), findsNothing);
    expect(find.text('Tendencia privada'), findsNothing);
    expect(find.byKey(const ValueKey('bodega-goal-action')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('home premium real sin overflow en $width', (tester) async {
      tester.view.physicalSize = Size(width, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var goalTap = false;
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
      for (final id in ['sell', 'stock', 'cash']) {
        await tester.tap(find.byKey(ValueKey('bodega-dock-$id')));
        await tester.pump();
      }
      expect(navigated, ['sell', 'stock', 'cash']);
      await tester.tap(find.byKey(const ValueKey('bodega-dock-more')));
      expect(more, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
