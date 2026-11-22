import 'dart:io';
import 'dart:typed_data';

import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

Widget _fixture(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.light),
  builder: (_, navigator) => RepaintBoundary(
    key: const ValueKey('checkout-preview'),
    child: navigator!,
  ),
  home: child,
);

Widget _cart() {
  final items = <LineItem>[
    LineItem(productId: 'demo-a', description: 'Agua mineral 625 ml',
      quantity: 2, unitPrice: 1.80),
    LineItem(productId: 'demo-b', description: 'Leche fresca 1 L',
      quantity: 1, unitPrice: 4.90),
    LineItem(productId: 'demo-c', description: 'Pan artesanal',
      quantity: 1, unitPrice: 5.50),
  ];
  return PosCartReviewScreen(
    lines: () => items,
    currency: 'PEN', taxRate: 18,
    productImages: const {},
    fixtureAssetPhotos: const {
      'demo-a': 'assets/demo/water.webp',
      'demo-b': 'assets/demo/milk.webp',
      'demo-c': 'assets/demo/bread.webp',
    },
    onChangeQuantity: (id, delta) {
      for(final item in items) {
        if(item.productId == id) item.quantity += delta;
      }
    },
  );
}

Widget _payment() => Builder(builder: (context) => Scaffold(body: Center(
  child: FilledButton(
    onPressed: () => choosePosPayment(context,
      currency: 'PEN', total: 16.52,
      items: [
        LineItem(description: 'Agua mineral 625 ml', quantity: 2, unitPrice: 1.80),
        LineItem(description: 'Leche fresca 1 L', quantity: 1, unitPrice: 4.90),
        LineItem(description: 'Pan artesanal', quantity: 1, unitPrice: 5.50),
      ],
    ),
    child: const Text('Abrir cobro'),
  ),
)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
    await inter.load();
    await (FontLoader('DM Serif Text')..addFont(rootBundle.load('assets/fonts/DMSerifText-Regular.ttf'))).load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (await icons.exists()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(
          ByteData.sublistView(await icons.readAsBytes())));
      await loader.load();
    }
  });

  for(final name in ['Carrito','Cobro']) {
    testWidgets('captura Flutter real de $name con fixtures', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_fixture(name == 'Carrito' ? _cart() : _payment()));
      if (name == 'Cobro') await tester.tap(find.text('Abrir cobro'));
      final context = tester.element(find.byKey(const ValueKey('checkout-preview')));
      final assets = name == 'Carrito'
          ? const ['assets/demo/water.webp', 'assets/demo/milk.webp', 'assets/demo/bread.webp']
          : const ['assets/payments/yape.png', 'assets/payments/plin.png'];
      await tester.runAsync(() => Future.wait([
        for (final asset in assets) precacheImage(AssetImage(asset), context),
      ]));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('checkout-preview')),
        matchesGoldenFile('previews/${name.toLowerCase()}.png'));
      expect(tester.takeException(), isNull);
    });
  }
}
