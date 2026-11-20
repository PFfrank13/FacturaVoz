import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/pos_product_card.dart';
import 'package:facturavoz/ui/inventory_product_card.dart';
import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/retail_visual.dart';
import 'package:facturavoz/ui/motion.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'dart:io';
import 'dart:typed_data';

// Widget-level captures rendered by Flutter, not concept art.
// The amounts below are OFFLINE FIXTURES, never live financial data.
Widget _frame(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.light),
  home: RepaintBoundary(
    key: const ValueKey('preview-root'),
    child: Scaffold(body: SafeArea(child: child)),
  ),
);

Widget _home() => Column(children: [
  Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
    child: Row(children: [
      const Icon(Icons.menu_rounded, size: 22),
      const SizedBox(width: 16),
      Text('Inicio', style: buildTheme(Brightness.light).textTheme.titleLarge),
      const Spacer(),
      const Icon(Icons.notifications_none_rounded, size: 23),
    ]),
  ),
  Expanded(child: DecoratedBox(
    decoration: BoxDecoration(gradient: FvLuxe.ambient(Brightness.light)),
    child: SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Text('Hola, Solvex',
            style: buildTheme(Brightness.light).textTheme.headlineMedium)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
          child: RetailPremiumOverview(
            name: 'Solvex', currencySymbol: 'S/',
            salesAmount: 29.50, salesCount: 2, drafts: 1,
            todayAmount: 0, todayCount: 0,
            loaded: true, showMonth: true,
            chart: const Sparkline(
              values: [0, 0, 8, 14, 0, 0, 0, 6, 1, 0, 5, 0, 0, 0],
              height: 45, color: FvLuxe.jade),
            onGoal: () {})),
        const SizedBox(height: 14),
        RetailHomeQuickActions(
          onNavigate: (_) {},
          allowed: const {'sell', 'stock', 'comprobantes', 'cash', 'fiados'}),
        Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Text('Hoy', style: buildTheme(Brightness.light).textTheme.headlineSmall)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Expanded(child: RetailHomeStat(label:'Ventas de hoy',
              value:'S/ 0.00',detail:'0 ventas',
              icon:Icons.trending_up_rounded,tint:RetailAccent.teal)),
            const SizedBox(width: 10),
            Expanded(child: RetailHomeStat(label:'Estado de mi caja',
              value:'Sin abrir',detail:'Toca para abrir',
              icon:Icons.point_of_sale_rounded,tint:RetailAccent.amber)),
          ])),
      ])),
  )),
  RetailPremiumBottomDock(
    current:'home', onNavigate: (_) {},onMore: () {},
    items: const [
      ('home','Inicio',Icons.home_outlined),
      ('sell','Ventas',Icons.shopping_cart_outlined),
      ('stock','Inventario',Icons.inventory_2_outlined),
      ('cash','Caja',Icons.point_of_sale_outlined),
    ]),
]);

Widget _pos() => Column(children: [
  Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
    child: Row(children: [
      const Icon(Icons.menu_rounded),
      const SizedBox(width: 15),
      Text('Venta rápida', style: buildTheme(Brightness.light).textTheme.titleLarge),
      const Spacer(),
      const Icon(Icons.qr_code_scanner_rounded),
    ])),
  Expanded(child: DecoratedBox(
    decoration: BoxDecoration(gradient: FvLuxe.ambient(Brightness.light)),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 18),
      child: Column(children: [
        TextField(
          readOnly: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Buscar producto o escanear código',
          )),
        const SizedBox(height: 14),
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(children: [
            Chip(label: Text('Todos')),
            SizedBox(width: 8),
            Chip(label: Text('Bebidas')),
            SizedBox(width: 8),
            Chip(label: Text('Abarrotes')),
          ]),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap:true, physics:const NeverScrollableScrollPhysics(),
          crossAxisCount:2, crossAxisSpacing:12,mainAxisSpacing:12,
          childAspectRatio:.62,
          children: [
            for(final p in const [
              ('Agua mineral 625 ml','S/ 1.80','Bebidas','assets/demo/water.webp'),
              ('Leche fresca 1 L','S/ 4.90','Lácteos','assets/demo/milk.webp'),
              ('Arroz extra 1 kg','S/ 4.50','Abarrotes','assets/demo/rice.webp'),
              ('Aceite de oliva','S/ 17.90','Abarrotes','assets/demo/oil.webp'),
              ('Pan artesanal','S/ 5.50','Panadería','assets/demo/bread.webp'),
              ('Galletas caseras','S/ 3.50','Snacks','assets/demo/cookies.webp'),
            ])
              FvPosProductCard(
                name:p.$1,price:p.$2,category:p.$3,
                icon:Icons.shopping_bag_outlined,
                photo: Image.asset(p.$4, fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  semanticLabel: 'Fotografía de muestra de ${p.$1}'),
                onAdd: () {},
              ),
          ],
        ),
      ]),
    ),
  )),
  const Padding(
    padding: EdgeInsets.fromLTRB(15, 8, 15, 20),
    child: FvGlassSurface(
      padding: EdgeInsets.all(16),
      radius: 23,blur: 20,
      child: Row(children: [
        Expanded(child: Text('Carrito de ejemplo',
          style:TextStyle(fontWeight:FontWeight.w700,fontSize:14))),
        Text('S/ 0.00',style:TextStyle(fontWeight:FontWeight.w700,fontSize:19)),
      ]),
    ),
  ),
]);

Widget _inventory() => Column(children: [
  Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
    child: Row(children: [
      const Icon(Icons.menu_rounded),
      const SizedBox(width: 15),
      Text('Inventario', style: buildTheme(Brightness.light).textTheme.titleLarge),
      const Spacer(),
      const Icon(Icons.add_rounded),
    ])),
  Expanded(child: DecoratedBox(
    decoration: BoxDecoration(gradient: FvLuxe.ambient(Brightness.light)),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment:CrossAxisAlignment.stretch, children: [
        Builder(builder: (context) => RetailVisual.hero(context:context,
          eyebrow:'INVENTARIO · BODEGA',
          title:'Tus productos, bajo control',
          subtitle:'Precios, existencias y alertas en un mismo lugar.',
          icon:Icons.inventory_2_outlined)),
        const SizedBox(height:16),
for (final p in const [
          ('Agua mineral 625 ml', 'S/ 1.80', '48', 'assets/demo/water.webp', 'Bebidas'),
          ('Leche fresca 1 L', 'S/ 4.90', '24', 'assets/demo/milk.webp', 'Lácteos'),
          ('Arroz extra 1 kg', 'S/ 4.50', '6', 'assets/demo/rice.webp', 'Abarrotes'),
          ('Aceite de oliva', 'S/ 17.90', '18', 'assets/demo/oil.webp', 'Abarrotes'),
          ('Pan artesanal', 'S/ 5.50', '12', 'assets/demo/bread.webp', 'Panadería'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: FvInventoryProductCard(
              name: p.$1,
              price: p.$2,
              active: true,
              isService: false,
              category: p.$5,
              stockLabel: 'Stock ${p.$3}',
              photo: Image.asset(p.$4, fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'Fotografía ilustrativa de ${p.$1}'),
              onOpen: () {},
            ),
          ),
      ]),
    ),
  )),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
    await inter.load();
    // flutter_test replaces fonts with Ahem by default. Load the real icon
    // font so exported previews are legible and show genuine Flutter icons.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable)
            .parent.parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (await icons.exists()) {
      final bytes = await icons.readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  for(final p in const <String>['Inicio','Venta','Inventario']) {
    testWidgets('Flutter render preview - $p', (tester) async {
      tester.view.physicalSize = const Size(390,844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_frame(switch (p) {
        'Inicio' => _home(),
        'Venta' => _pos(),
        _ => _inventory(),
      }));
      if (p == 'Venta' || p == 'Inventario') {
        // A test capture must wait for image decoding, not just layout.
        // In an actual app the image cache fills asynchronously.
        final context = tester.element(find.byKey(const ValueKey('preview-root')));
        await tester.runAsync(() async {
          await Future.wait([
            for (final name in const ['water','milk','rice','oil','bread','cookies'])
              precacheImage(AssetImage('assets/demo/$name.webp'), context),
          ]);
        });
      }
      await tester.pump();
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('preview-root')),
        matchesGoldenFile('previews/${p.toLowerCase()}.png'));
      expect(tester.takeException(),isNull);
    });
  }
}
