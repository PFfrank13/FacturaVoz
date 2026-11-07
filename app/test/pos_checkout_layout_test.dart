import 'package:facturavoz/models.dart';
import 'package:facturavoz/access.dart';
import 'package:facturavoz/screens/pos.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 768.0]) {
    testWidgets('seleccionar producto y abrir cobro por encima del dock a $width', (tester) async {
      Access.instance.isAdmin = true;
      Access.instance.licenseCheckedOnline = true;
      Access.instance.license = const LicenseInfo(source: 'hub', mode: 'full', features: {'facturar': true, 'stock': false});
      addTearDown(Access.instance.clear);
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(
        // Same nested Scaffold constraint as MainShell: dock reserves its height.
        extendBody: false,
        bottomNavigationBar: const SizedBox(height: 94, child: Center(child: Text('Navegación'))),
        body: PosScreen(embedded: true,
          loadProducts: () async => [Product(id: 'qa-product', name: 'Arroz de prueba', unitPrice: 10, unit: 'NIU', active: true)],
          loadExtras: () async => {},
        ),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arroz de prueba'));
      await tester.pumpAndSettle();
      final charge = find.text('Cobrar');
      expect(charge.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(charge).dy, lessThan(806));
      await tester.tap(charge);
      await tester.pumpAndSettle();
      expect(find.text('¿Cómo paga?'), findsOneWidget);
      expect(find.text('Más opciones (cliente, factura, crédito)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
