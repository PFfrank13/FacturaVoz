import 'package:facturavoz/access.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/products.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final width in [320.0, 768.0]) {
    testWidgets('catálogo filtra y busca con texto ampliado a $width', (tester) async {
      Access.instance.isAdmin = true;
      Access.instance.licenseCheckedOnline = true;
      Access.instance.license = const LicenseInfo(source: 'hub', mode: 'full', features: {'facturar': true, 'stock': false});
      addTearDown(Access.instance.clear);
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)), child: child!),
        home: ProductsScreen(loadProducts: () async => [
          Product(id: 'a', name: 'Arroz superior', unitPrice: 12.50, unit: 'NIU', active: true),
          Product(id: 'b', name: 'Leche archivada', unitPrice: 4, unit: 'NIU', active: false),
        ])));
      await tester.pumpAndSettle();
      expect(find.text('Arroz superior'), findsOneWidget);
      expect(find.text('Leche archivada'), findsNothing);
      expect(find.text('Por reponer'), findsNothing);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/catalog-$width.png'));
      await tester.tap(find.text('Archivados')); await tester.pumpAndSettle();
      expect(find.text('Leche archivada'), findsOneWidget);
      expect(find.text('Arroz superior'), findsNothing);
      await tester.tap(find.text('Todos')); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'arroz'); await tester.pumpAndSettle();
      expect(find.text('Arroz superior'), findsOneWidget);
      expect(find.text('Leche archivada'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
