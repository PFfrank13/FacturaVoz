import 'package:facturavoz/access.dart';
import 'package:facturavoz/permissions.dart';
import 'package:facturavoz/screens/retail_basic_modules.dart';
import 'package:facturavoz/screens/shell.dart' show bodegaDrawerIds;
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LicenseInfo _lic(String plan, {bool extras = false, bool copilot = false}) => LicenseInfo(
  plan: plan,
  source: 'hub',
  status: 'activa',
  mode: 'full',
  enforced: true,
  activated: true,
  features: {
    'facturar': true,
    'clientes': true,
    'fiados': true,
    'caja': true,
    'stock': true,
    'cobros': true,
    'reportes': true,
    'voz': true,
    'cotizaciones': extras,
    'precios': extras,
    'comisiones': extras,
    'recurrentes': extras,
    'copiloto': copilot,
    'copiloto_agente': copilot,
  },
);

void main() {
  setUp(() {
    final a = Access.instance;
    a.rubro = 'bodega';
    a.role = 'owner';
    a.isAdmin = true;
    a.licenseCheckedOnline = true;
    a.license = _lic('BASICO');
  });

  tearDown(() {
    final a = Access.instance;
    a.rubro = null;
    a.role = 'member';
    a.isAdmin = false;
    a.licenseCheckedOnline = false;
    a.license = const LicenseInfo();
  });

  test('Básico nunca presenta Copiloto, incluso con un flag legado erróneo', () {
    final a = Access.instance;
    a.license = _lic('BASICO', copilot: true);
    expect(a.has('copiloto'), isFalse);
    expect(a.has('copiloto_agente'), isFalse);
    expect(a.has('facturar'), isTrue);
    expect(a.has('stock'), isTrue);
    expect(bodegaDrawerIds(a), [
      'home', 'sell', 'fiados', 'cash', 'stock', 'settings',
    ]);
  });

  test('El Drawer se restringe al rol y contrato reales', () {
    final a = Access.instance;
    a.role = 'tecnico';
    a.isAdmin = false;
    expect(bodegaDrawerIds(a), ['home', 'settings']);
    a.role = 'owner';
    a.isAdmin = true;
    a.licenseCheckedOnline = false;
    expect(bodegaDrawerIds(a), ['home', 'settings']);
  });

  test('Pro y Empresa pueden usar Copiloto solo si Hub lo autoriza', () {
    final a = Access.instance;
    for (final plan in ['PRO', 'EMPRESA']) {
      a.license = _lic(plan);
      expect(a.has('copiloto'), isFalse);
      a.license = _lic(plan, copilot: true);
      expect(a.has('copiloto'), isTrue);
    }
  });

  for (final plan in ['PRO', 'EMPRESA']) {
    for (final brightness in Brightness.values) {
      testWidgets('Tablero $plan ${brightness.name} a 320 px, letra 1.4 sin candados', (tester) async {
        Access.instance.license = _lic(plan, extras: true, copilot: true);
        tester.view.physicalSize = const Size(320, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: const Scaffold(body: SingleChildScrollView(
              child: RetailPlanModules(),
            )),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('FacturaVoz · Plan ${plan == 'PRO' ? 'Pro' : 'Empresa'}'), findsOneWidget);
        expect(find.byKey(const ValueKey('retail-module-pos')), findsOneWidget);
        expect(find.byKey(const ValueKey('retail-plan-modules')), findsOneWidget);
        // Pro/Empresa no pierden acceso al historial ni a los reportes.
        expect(find.byKey(const ValueKey('retail-module-reportes')), findsOneWidget);
        expect(find.byKey(const ValueKey('retail-module-clientes')), findsOneWidget);
        expect(find.byKey(const ValueKey('retail-plan-premium')), findsOneWidget);
        expect(find.text('Nueva venta'), findsOneWidget);
        expect(find.text('Ver todas'), findsNothing);
        expect(find.text('Todas mis funciones'), findsNothing);
        expect(find.textContaining('Copiloto'), findsNothing);
        expect(find.byIcon(Icons.lock_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('Matriz completa de seis roles: planes no alteran permisos del usuario', () {
    const roles = ['owner', 'admin', 'finanzas', 'cajero', 'vendedor', 'tecnico'];
    const core = {'facturar', 'cobros', 'clientes', 'stock', 'fiados', 'caja', 'reportes'};
    const premium = {'cotizaciones', 'precios', 'comisiones', 'recurrentes'};
    for (final plan in ['BASICO', 'PRO', 'EMPRESA']) {
      bool has(String feature) => core.contains(feature) ||
          (plan != 'BASICO' && premium.contains(feature));
      for (final role in roles) {
        final m = previewPermissions(role, has);
        expect(m.allowed.toSet().intersection(m.denied.toSet()), isEmpty,
            reason: '$plan / $role no puede duplicar permisos contradictorios');
        if (role == 'tecnico') {
          expect(m.denied, containsAll(['Registrar ventas', 'Registrar cobros']));
        }
        if (role == 'cajero') {
          expect(m.allowed, containsAll(['Registrar ventas', 'Abrir caja']));
          expect(m.denied, contains('Ver ganancia y márgenes'));
        }
        if (role == 'admin') {
          expect(m.denied, contains('Pagar o cambiar el plan'));
        }
        if (role == 'owner') {
          expect(m.allowed, contains('Pagar o cambiar el plan'));
        }
      }
    }
  });

  testWidgets('Sin licencia verificada no existe tablero ni acceso operativo', (tester) async {
    final a = Access.instance;
    a.licenseCheckedOnline = false;
    a.license = _lic('EMPRESA', extras: true);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RetailPlanModules())));
    expect(find.byKey(const ValueKey('retail-module-pos')), findsNothing);
    expect(find.byKey(const ValueKey('retail-plan-modules')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
