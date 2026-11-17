import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:facturavoz/screens/home.dart' show CopilotCards;
import 'package:facturavoz/screens/menu.dart';
import 'package:facturavoz/screens/shell.dart' show bodegaDrawerIds;
import 'package:facturavoz/screens/retail_basic_modules.dart';
import 'package:facturavoz/screens/settings_v2.dart' show showSecuritySheet;

void main() {
  setUp(() {
    final a = Access.instance;
    a.rubro = 'bodega';
    a.role = 'owner';
    a.isAdmin = true;
    a.licenseCheckedOnline = true;
    a.license = const LicenseInfo(
      plan: 'BASICO',
      source: 'hub',
      status: 'activa',
      mode: 'full',
      enforced: true,
      activated: true,
      features: {
        'facturar': true,
        'clientes': true,
        'cobros': true,
        'voz': true,
        'caja': true,
        'reportes': true,
        'avisos_pago': true,
        'cotizaciones': true,
        'copiloto': false,
        'copiloto_agente': false,
        'stock': false,
        'fiados': false,
        'antifraude': false,
      },
    );
  });

  tearDown(() {
    final a = Access.instance;
    a.rubro = null;
    a.role = 'member';
    a.isAdmin = false;
    a.licenseCheckedOnline = false;
    a.license = const LicenseInfo();
  });

  test('Básico solo autoriza funciones habilitadas por el Hub', () {
    expect(featureById('pos')!.allowed, isTrue);
    expect(featureById('caja')!.allowed, isTrue);
    expect(featureById('agente')!.allowed, isFalse);
    expect(featureById('productos')!.allowed, isFalse);
    expect(featureById('fiados')!.allowed, isFalse);
  });

  test('El Drawer no muestra módulos fuera del plan ni Copiloto en Básico', () {
    final a = Access.instance;
    expect(bodegaDrawerIds(a), ['home', 'sell', 'cash', 'settings']);
    a.license = const LicenseInfo(
      source: 'hub', mode: 'full', status: 'activa', activated: true,
      enforced: true, plan: 'BASICO',
      features: {
        'facturar': true, 'caja': true, 'fiados': true, 'stock': true,
        'voz': true, 'copiloto': false,
      },
    );
    expect(bodegaDrawerIds(a), [
      'home', 'sell', 'fiados', 'cash', 'stock', 'settings',
    ]);
  });

  testWidgets('Inicio Básico elimina Ver todas y Más herramientas', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RetailBasicModules())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retail-module-pos')), findsOneWidget);
    expect(find.text('Ver todas'), findsNothing);
    expect(find.text('Más herramientas'), findsNothing);
    expect(find.text('Nueva venta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El menú Básico no muestra candados, Copiloto ni upsell', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Herramientas de tu negocio'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.textContaining('Disponible en el plan'), findsNothing);
    expect(find.text('Tareas del Copiloto'), findsNothing);
    expect(find.text('Libreta de fiados'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Las sugerencias del Copiloto desaparecen totalmente en Básico', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CopilotCards(alerts: const [], onChanged: () {})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tu copiloto te sugiere'), findsNothing);
    expect(find.text('Tu resumen en 30 segundos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El panel Seguridad solo muestra herramientas autorizadas', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showSecuritySheet(context),
            child: const Text('Abrir seguridad'),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('Abrir seguridad'));
    await tester.pumpAndSettle();
    expect(find.text('Alertas del dueño'), findsNothing);
    expect(find.text('Bitácora'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pro con licencia Copiloto sí recibe sus propias sugerencias', (tester) async {
    Access.instance.license = const LicenseInfo(
      plan: 'PRO',
      source: 'hub',
      status: 'activa',
      mode: 'full',
      enforced: true,
      activated: true,
      features: {'copiloto': true, 'facturar': true},
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CopilotCards(alerts: const [], onChanged: () {})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tu copiloto te sugiere'), findsOneWidget);
    expect(find.text('Tu resumen en 30 segundos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
