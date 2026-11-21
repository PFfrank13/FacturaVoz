import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/shell.dart';
import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/glass_widgets.dart';
import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/theme.dart';

import 'support/retail_fixture.dart';

void main() {
  Future<void> mountDock(
    WidgetTester tester, {
    required ValueNotifier<String> current,
    double width = 320,
    double scale = 1,
    bool contrast = false,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = Size(width, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 720),
          textScaler: TextScaler.linear(scale),
          highContrast: contrast,
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          bottomNavigationBar: ValueListenableBuilder(
            valueListenable: current,
            builder: (context, active, _) => RetailPremiumBottomDock(
              current: active,
              items: const [
                ('home', 'Inicio', Icons.home_outlined),
                ('sell', 'Ventas', Icons.point_of_sale_outlined),
                ('stock', 'Inventario', Icons.inventory_2_outlined),
                ('cash', 'Caja', Icons.wallet_outlined),
              ],
              onNavigate: (id) => current.value = id,
              onMore: () => current.value = 'receipts',
            ),
          ),
        ),
      ),
    ));
  }

  Finder destination(String id) => find.byKey(ValueKey('bodega-dock-$id'));
  final indicator = find.byKey(const ValueKey('retail-dock-selection'));

  testWidgets('la selección retoma el trayecto desde su posición visible',
      (tester) async {
    final current = ValueNotifier('home');
    addTearDown(current.dispose);
    await mountDock(tester, current: current, width: 430);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final start = tester.getCenter(indicator).dx;
    await tester.tap(destination('stock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final middle = tester.getCenter(indicator).dx;
    expect(middle, inExclusiveRange(start, tester.getCenter(destination('stock')).dx));
    await tester.tap(destination('cash'));
    await tester.pump();
    expect(tester.getCenter(indicator).dx, closeTo(middle, .01));
    await tester.pumpAndSettle();
    expect(tester.getCenter(indicator), tester.getCenter(destination('cash')));
    await tester.tap(destination('more'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(indicator), tester.getCenter(destination('more')));
  });

  testWidgets('al invertir el trayecto el indicador conserva la velocidad',
      (tester) async {
    final current = ValueNotifier('home');
    addTearDown(current.dispose);
    await mountDock(tester, current: current, width: 430);
    await tester.tap(destination('cash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 55));
    final turning = tester.getCenter(indicator).dx;
    await tester.tap(destination('home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.getCenter(indicator).dx, greaterThan(turning));
    await tester.pumpAndSettle();
    expect(tester.getCenter(indicator), tester.getCenter(destination('home')));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final contrast in [false, true]) {
      testWidgets('cabecera y rail adaptan el material a $platform y contraste $contrast',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.dark).copyWith(platform: platform),
          home: MediaQuery(
            data: MediaQueryData(highContrast: contrast),
            child: const Column(children: [
              SizedBox(height: 60, child: FvGlassTopBar()),
              FvFloatingGlassDock(radius: 26,
                child: SizedBox(width: 76, height: 400)),
            ]),
          ),
        ));
        for (final surface in [FvGlassTopBar, FvFloatingGlassDock]) {
          final filter = find.descendant(of: find.byType(surface),
            matching: find.byType(BackdropFilter));
          expect(filter, contrast ? findsNothing : findsOneWidget);
        }
      });
    }
  }

  for (final scale in [1.4, 2.0]) {
    testWidgets('las etiquetas caben a escala $scale con contraste y movimiento reducido',
        (tester) async {
      final current = ValueNotifier('home');
      addTearDown(current.dispose);
      await mountDock(tester,
          current: current, scale: scale, contrast: true, reduceMotion: true);
      expect(find.byType(BackdropFilter), findsNothing);
      for (final id in ['home', 'sell', 'stock', 'cash', 'more']) {
        final control = destination(id);
        final target = tester.getSize(control);
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        final label = find.descendant(of: control, matching: find.byType(Text));
        final text = find.descendant(of: label, matching: find.byType(RichText));
        expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
      }
      await tester.tap(destination('stock'));
      await tester.pump();
      await tester.pump();
      expect(tester.getCenter(indicator), tester.getCenter(destination('stock')));
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final contrast in [false, true]) {
      testWidgets('Glass sin overflow en $brightness (contraste: $contrast)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: MediaQueryData(highContrast: contrast),
            child: Scaffold(
              body: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 300,
                  child: FvGlassSurface(
                    radius: 22,
                    padding: const EdgeInsets.all(16),
                    child: Text('Navegación',
                      style: TextStyle(color: brightness == Brightness.dark ? FvTokens.inkDark : FvTokens.ink)),
                  ),
                ),
              ),
            ),
          ),
        ));
        expect(find.text('Navegación'), findsOneWidget);
        expect(find.byType(BackdropFilter),
            contrast ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('barra lateral de FacturaVoz', () {
    setUpAll(startRetailFixture);
    tearDownAll(stopRetailFixture);

    testWidgets('la barra presenta etiquetas al ampliar y conserva el destino al volver a móvil',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(768, 960);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: const MainShell()));
      await tester.pump();
      final rail = find.byKey(const ValueKey('bodega-navigation-rail'));
      expect(tester.widget<NavigationRail>(rail).extended, isFalse);
      expect(find.byType(RetailPremiumBottomDock), findsNothing);
      tester.view.physicalSize = const Size(1280, 850);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(tester.widget<NavigationRail>(rail).extended, isTrue);
      await tester.tap(find.descendant(of: rail, matching: find.text('Inventario')).hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      final selectedRail = tester.widget<NavigationRail>(rail);
      final label = selectedRail.destinations[selectedRail.selectedIndex!].label as Text;
      expect(label.data, 'Inventario');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(rail, findsNothing);
      expect(tester.widget<RetailPremiumBottomDock>(find.byType(RetailPremiumBottomDock)).current, 'stock');
      expect(tester.takeException(), isNull);
    });
  });
}
