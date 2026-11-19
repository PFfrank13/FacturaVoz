import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/pos_product_card.dart';
import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final lo = a.computeLuminance() < b.computeLuminance() ? a : b;
  final hi = a.computeLuminance() > b.computeLuminance() ? a : b;
  return (hi.computeLuminance() + .05) / (lo.computeLuminance() + .05);
}
void main() {
  for (final brightness in Brightness.values) {
    test('iOS Luxe uses contrast-safe actions in $brightness', () {
      final scheme = buildTheme(brightness).colorScheme;
      expect(contrast(scheme.primary, scheme.onPrimary), greaterThan(4.5));
      expect(FvLuxe.ambient(brightness).colors, hasLength(3));
    });
    testWidgets('glass remains accessible at 320 dp, $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness),
        home: const Scaffold(body: Center(child: SizedBox(
          width: 284, height: 84,
          child: FvGlassSurface(
            child: Center(child: Text('FacturaVoz')),
          ),
        ))),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  }
  testWidgets('POS animates quantity and keeps its real callback', (tester) async {
    var added = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(
        width: 160,height:250,
        child: StatefulBuilder(builder: (context, setState) =>
          FvPosProductCard(
            name:'Agua mineral',
            price:'S/ 1.80',
            icon:Icons.water_drop_outlined,
            quantity:added > 0 ? '$added' : null,
            onAdd: () => setState(() => added++),
          )),
      ))),
    ));
    await tester.tap(find.byTooltip('Añadir Agua mineral'));
    await tester.pumpAndSettle();
    expect(added,1);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion uses no active entrance animation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: SizedBox(
          width:210,height:168,
          child:RetailHomeStat(
            label:'Caja',value:'Sin abrir',
            icon:Icons.point_of_sale,
            tint:RetailAccent.amber),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations,isFalse);
    expect(tester.takeException(),isNull);
  });
}
