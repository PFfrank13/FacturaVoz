import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/screens/retail_basic_modules.dart';

void main() {
  // A test-only verified entitlement is used to exercise the widgets; no
  // back-end policy or real license is changed.
  setUp(() {
    final access = Access.instance;
    access.rubro = 'bodega';
    access.role = 'owner';
    access.isAdmin = true;
    access.licenseCheckedOnline = true;
    access.license = const LicenseInfo(
      mode: 'full',
      source: 'hub',
      enforced: true,
      features: {
        'facturar': true,
        'stock': true,
        'fiados': true,
        'caja': true,
        'reportes': true,
        'clientes': true,
      },
    );
  });

  tearDown(() {
    final access = Access.instance;
    access.rubro = null;
    access.role = 'member';
    access.isAdmin = false;
    access.licenseCheckedOnline = false;
    access.license = const LicenseInfo();
  });

  for (final (width, expectedColumns) in const [
    (320.0, 2),
    (600.0, 3),
    (900.0, 4),
  ]) {
    testWidgets('Basic dashboard uses $expectedColumns columns at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RetailBasicModules())),
      ));
      await tester.pumpAndSettle();

      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('retail-basic-modules')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount,
        expectedColumns,
      );
      expect(find.byKey(const ValueKey('retail-module-pos')), findsOneWidget);
      expect(find.text('Nueva venta'), findsOneWidget);
      expect(find.text('FacturaVoz · Plan Básico'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Pro and Empresa plans do not display the Basic-only home dashboard', (tester) async {
    for (final plan in const ['PRO', 'EMPRESA']) {
      Access.instance.license = LicenseInfo(
        plan: plan, mode: 'full', source: 'hub', enforced: true,
        features: const {'facturar': true, 'stock': true, 'caja': true},
      );
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RetailBasicModules())),
      ));
      expect(find.text('FacturaVoz · Plan Básico'), findsNothing);
      expect(find.byKey(const ValueKey('retail-basic-modules')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Bodega module shortcuts are not available without a valid license', (tester) async {
    Access.instance.license = const LicenseInfo();
    Access.instance.licenseCheckedOnline = false;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RetailBasicModules())),
    ));

    expect(find.byKey(const ValueKey('retail-module-pos')), findsNothing);
    expect(find.byKey(const ValueKey('retail-module-productos')), findsNothing);
    expect(find.byKey(const ValueKey('retail-module-fiados')), findsNothing);
    expect(find.byKey(const ValueKey('retail-module-comprobantes')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
