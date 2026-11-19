import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/glass_widgets.dart';
import 'package:facturavoz/ui/pos_product_card.dart';
import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/retail_visual.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
            chart: const SizedBox(height: 45),
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
        const Row(children: [
          Chip(label: Text('Todos')),
          SizedBox(width: 8),
          Chip(label: Text('Bebidas')),
          SizedBox(width: 8),
          Chip(label: Text('Abarrotes')),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap:true, physics:const NeverScrollableScrollPhysics(),
          crossAxisCount:2, crossAxisSpacing:12,mainAxisSpacing:12,
          childAspectRatio:.62,
          children: [
            for(final p in const [
              ('Agua mineral 625 ml','S/ 1.80','Bebidas'),
              ('Leche fresca 1 L','S/ 4.90','Lácteos'),
              ('Arroz extra 1 kg','S/ 4.50','Abarrotes'),
              ('Aceite de oliva','S/ 17.90','Abarrotes'),
              ('Pan artesanal','S/ 5.50','Panadería'),
              ('Galletas caseras','S/ 3.50','Snacks'),
            ])
              FvPosProductCard(
                name:p.$1,price:p.$2,category:p.$3,
                icon:Icons.shopping_bag_outlined,
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
        for(final p in const [
          ('Agua mineral 625 ml','S/ 1.80','48'),
          ('Leche fresca 1 L','S/ 4.90','24'),
          ('Arroz extra 1 kg','S/ 4.50','6'),
          ('Aceite de oliva','S/ 17.90','18'),
          ('Pan artesanal','S/ 5.50','12'),
        ])
          Padding(padding:const EdgeInsets.only(bottom:10),
            child: Container(
              height:84,padding:const EdgeInsets.all(10),
              decoration:BoxDecoration(
                color:Colors.white,borderRadius:BorderRadius.circular(20),
                border:Border.all(color:const Color(0xFFE3EBF3))),
              child:Row(children: [
                ClipRRect(borderRadius:BorderRadius.circular(13),
                  child:SizedBox(width:58,height:60,
                    child:FvProductPhotoFallback(name:p.$1))),
                const SizedBox(width:13),
                Expanded(child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,
                  mainAxisAlignment:MainAxisAlignment.center,children: [
                    Text(p.$1,maxLines:1,overflow:TextOverflow.ellipsis,
                      style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13)),
                    const SizedBox(height:5),
                    Text(p.$2,style:const TextStyle(
                      color:FvLuxe.jade,fontWeight:FontWeight.w700,fontSize:14)),
                  ])),
                Text(p.$3,style:const TextStyle(
                  fontWeight:FontWeight.w700,color:FvLuxe.jade)),
                const Icon(Icons.chevron_right_rounded,color:Colors.black45),
              ]),
            )),
      ]),
    ),
  )),
]);

void main() {
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
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('preview-root')),
        matchesGoldenFile('previews/${p.toLowerCase()}.png'));
      expect(tester.takeException(),isNull);
    });
  }
}
