import 'dart:io';
import 'dart:typed_data';

import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

Widget _fixture(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.light),
  home: RepaintBoundary(
    key: const ValueKey('checkout-preview'),
    child: child,
  ),
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
    onChangeQuantity: (id, delta) {
      for(final item in items) {
        if(item.productId == id) item.quantity += delta;
      }
    },
  );
}

Widget _payment() => Scaffold(
  appBar: AppBar(title: const Text('Método de cobro')),
  body: DecoratedBox(
    decoration: BoxDecoration(gradient: FvLuxe.ambient(Brightness.light)),
    child: ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: FvLuxe.editorial(Brightness.light),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TOTAL A COBRAR', style: TextStyle(
            color: Color(0xFF52647A), fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 5),
          const Text('S/ 16.52',style: TextStyle(
            color: Color(0xFF172337),fontSize: 36,
            fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Text('4 artículos de muestra · no se realiza ningún cobro',
            style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 24),
      const Text('Selecciona cómo te pagarán', style: TextStyle(
        fontSize: 19, fontWeight: FontWeight.w800,
        color: Color(0xFF172337))),
      const SizedBox(height: 14),
      SizedBox(height: 162, child: Row(children: [
        Expanded(child: PosPaymentMethodCard(
          method: 'efectivo', selected: true, onSelected: () {})),
        const SizedBox(width: 12),
        Expanded(child: PosPaymentMethodCard(
          method: 'tarjeta', selected: false, onSelected: () {})),
      ])),
      const SizedBox(height: 17),
      const Text('Yape · Plin · Transferencia', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Color(0xFF697A8E))),
      const SizedBox(height: 18),
      const Padding(padding: EdgeInsets.all(10),child: Text(
        'La confirmación del pago es manual y requiere la comprobación del cajero.',
        style:TextStyle(color:Color(0xFF697A8E),fontSize:12))),
      const SizedBox(height: 20),
      const FilledButton(
        onPressed: null,
        child: Text('Continuar · vista de muestra')),
    ]),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
    await inter.load();
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
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('checkout-preview')),
        matchesGoldenFile('previews/${name.toLowerCase()}.png'));
      expect(tester.takeException(), isNull);
    });
  }
}
