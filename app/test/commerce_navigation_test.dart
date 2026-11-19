import 'package:facturavoz/access.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:facturavoz/screens/menu.dart';
import 'package:facturavoz/ui/feature_access.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:facturavoz/ux/commerce_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Local fixtures only: no Hub writes, no network and no production plan matrix.
void fixture({String plan = 'BASICO', String role = 'owner',
    Map<String, bool> can = const {}, Map<String, dynamic> grants = const {},
    String mode = 'full', bool verified = true}) {
  final a = Access.instance;
  a.applyCached({'role': role, 'is_admin': role == 'owner' || role == 'admin', 'can': can},
    {'enforced': true, 'source': 'hub', 'mode': mode, 'plan': plan, 'features': grants});
  a.licenseCheckedOnline = verified;
  a.licenseChecking = false;
}

void main() {
  tearDown(() => Access.instance.clear());

  for (final (plan, role) in [('BASICO', 'owner'), ('BASICO', 'cajero'),
    ('PRO', 'owner'), ('PRO', 'vendedor'), ('EMPRESA', 'admin'), ('EMPRESA', 'cajero')]) {
    test('$plan / $role: actual grants and role decide, never plan label', () {
      fixture(plan: plan, role: role, can: {'sell': true, 'collect': true, 'settings': false},
        grants: {'facturar': true, 'caja': true, 'tienda': true, 'fiados': false});
      expect(featureById('pos')!.allowed, isTrue);
      expect(featureById('caja')!.allowed, isTrue);
      expect(featureById('fiados')!.allowed, isFalse);
      expect(featureById('fiados')!.roleOk, isTrue);
      expect(featureById('tienda')!.roleOk, isFalse);
      for (final id in sectorOnlyNavigation) {
        expect(featureById(id)!.roleOk, isFalse);
      }
    });
  }

  test('Basic add-ons work; Empresa without grant remains locked', () {
    fixture(grants: {'copiloto': true, 'tienda': true});
    expect(featureById('copiloto')!.allowed, isTrue);
    expect(featureById('tienda')!.allowed, isTrue);
    fixture(plan: 'EMPRESA');
    expect(featureById('copiloto')!.allowed, isFalse);
    expect(featureById('tienda')!.allowed, isFalse);
  });

  test('voice requires facturar and voz independently', () {
    fixture(grants: {'voz': true});
    expect(featureById('voz')!.allowed, isFalse);
    fixture(grants: {'voz': true, 'facturar': true});
    expect(featureById('voz')!.allowed, isTrue);
  });

  for (final mode in ['restricted', 'blocked']) {
    test('$mode does not permit even unmetered business destinations', () {
      fixture(mode: mode, grants: {'facturar': true});
      expect(featureById('gastos')!.allowed, isFalse);
      expect(featureById('pos')!.allowed, isFalse);
      expect(featureById('plan')!.allowed, isTrue);
    });
  }

  testWidgets('locked function opens upgrade modal without constructing destination', (tester) async {
    fixture();
    var opened = false;
    final f = FeatureEntry(id: 'probe', title: 'Probe', subtitle: '', icon: Icons.store,
      group: 'Vender', feature: 'tienda', builder: (_) { opened = true; return const Text('Protected'); });
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => openFeature(context, f), child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Actualiza tu plan'), findsOneWidget);
    expect(find.text('Ver planes'), findsOneWidget);
    expect(opened, isFalse);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(find.text('Actualiza tu plan'), findsNothing);
  });

  testWidgets('role denial is not an upsell or a constructed route', (tester) async {
    fixture(role: 'cajero', grants: {'tienda': true});
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => openFeature(context, featureById('tienda')!), child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    expect(find.text('Actualiza tu plan'), findsNothing);
    expect(find.text('Tu rol no tiene permiso para esta herramienta.'), findsOneWidget);
  });

  testWidgets('an open route loses its protected child when verification is invalidated', (tester) async {
    fixture(grants: {'tienda': true});
    await tester.pumpWidget(MaterialApp(home: FeatureAccessGate(
      roleAllowed: () => true, planAllowed: () => Access.instance.has('tienda'),
      builder: (_) => const Text('Protected data'))));
    expect(find.text('Protected data'), findsOneWidget);
    Access.instance.invalidateLicenseCheck();
    await tester.pumpAndSettle();
    expect(find.text('Protected data'), findsNothing);
    expect(find.text('Tu licencia necesita validación. Revisa Mi plan.'), findsOneWidget);
  });

  test('Básico: menú operativo sin vitrinas premium ni otros rubros', () {
    expect(commerceMenuVisible('pos', 'BASICO'), isTrue);
    expect(commerceMenuVisible('inventario', 'BASICO'), isTrue);
    expect(commerceMenuVisible('fiados', 'BASICO'), isTrue);
    expect(commerceMenuVisible('plan', 'BASICO'), isTrue);
    expect(commerceMenuVisible('copiloto', 'BASICO'), isFalse);
    expect(commerceMenuVisible('tienda', 'BASICO'), isFalse);
    expect(commerceMenuVisible('agente', 'BASICO'), isFalse);
    expect(commerceMenuVisible('carta', 'EMPRESA'), isFalse);
    expect(commerceMenuVisible('tipo', 'PRO'), isFalse);
  });

  testWidgets('Básico: menú y búsqueda ocultan la tienda sin concesión', (tester) async {
    fixture(grants: {'facturar': true, 'stock': true, 'fiados': true, 'caja': true});
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const MenuScreen()));
    await tester.enterText(find.byType(TextField), 'Tienda en línea');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Tienda en línea'), findsNothing);
    expect(find.text('No incluida en tu plan actual'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Inventario');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Inventario'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
