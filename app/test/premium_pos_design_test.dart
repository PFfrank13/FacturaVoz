import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/pos_product_card.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  test('el POS reparte columnas según el ancho útil', () {
    expect(FvTokens.productColumns(320), 2);
    expect(FvTokens.productColumns(390), 2);
    expect(FvTokens.productColumns(699), 2);
    expect(FvTokens.productColumns(700), 3);
    expect(FvTokens.productColumns(860), 4);
    expect(FvTokens.productColumns(1100), 5);
    expect(FvTokens.productColumns(double.infinity), 2);
    expect(FvTokens.isWide(699), false);
    expect(FvTokens.isWide(700), true);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('tarjeta compacta accesible y conectada al callback $brightness',
        (tester) async {
      var additions = 0;
      var removals = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness),
        home: Scaffold(body: Center(child: SizedBox(
          width: 145,
          height: 244,
          child: FvPosProductCard(
            name: 'Arroz extra en bolsa de un kilogramo',
            price: 'S/ 4.80',
            category: 'Abarrotes',
            stockLabel: 'Stock: 12',
            quantity: '2',
            icon: Icons.inventory_2_outlined,
            onAdd: () => additions++,
            onRemove: () => removals++,
          ),
        ))),
      ));
      expect(find.byTooltip('Añadir Arroz extra en bolsa de un kilogramo'),
          findsOneWidget);
      expect(find.text('S/ 4.80'), findsOneWidget);
      await tester.tap(find.byTooltip('Añadir Arroz extra en bolsa de un kilogramo'));
      await tester.pump();
      expect(additions, 1);
      expect(tester.takeException(), isNull);
      await tester.longPress(find.byType(FvPosProductCard));
      await tester.pump();
      expect(removals, 1);
    });
  }

  testWidgets('sin stock no admite agregar', (tester) async {
    var additions = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(
        width: 150, height: 244,
        child: FvPosProductCard(
          name: 'Leche', price: 'S/ 4.20',
          icon: Icons.local_drink_outlined,
          stockLabel: 'Sin stock', soldOut: true,
          onAdd: () => additions++,
        ),
      ))),
    ));
    final button = tester.widget<IconButton>(
        find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(additions, 0);
  });
}
