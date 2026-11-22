import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/retail_visual.dart';
import 'package:facturavoz/ui/retail_icon.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Retail surfaces respect ${brightness.name} theme with controlled depth', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness),
        home: Scaffold(body: Builder(builder: (context) => Center(
          child: RetailVisual.hero(
            context: context,
            chapter: RetailChapter.cash,
            eyebrow: 'Caja · Hoy',
            title: 'Control de caja',
            subtitle: 'Movimientos reales del negocio',
            icon: Icons.account_balance_wallet_rounded,
            footer: Row(children: [
              Expanded(child: RetailVisual.microStat('Ventas del día', 'S/ 100')),
              const SizedBox(width: 12),
              Expanded(child: RetailVisual.microStat('Operaciones', '3 ventas')),
            ]),
          ),
        ))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Control de caja'), findsOneWidget);
      expect(find.text('Ventas del día'), findsOneWidget);
      expect(find.text('S/ 100'), findsOneWidget);
      expect(find.text('3 ventas'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Control de caja'));
      final subtitle = tester.widget<Text>(find.text('Movimientos reales del negocio'));
      // Heroes are deep glass in both themes; text is measured against it.
      const paper = RetailVisual.heroGlass;
      for (final text in [title, subtitle]) {
        final values = [paper.computeLuminance(), text.style!.color!.computeLuminance()]..sort();
        expect((values.last + .05) / (values.first + .05), greaterThanOrEqualTo(4.5));
      }
      expect(find.byType(Image), findsNothing);
      expect(tester.widget<RetailIcon>(find.byType(RetailIcon)).icon, Icons.account_balance_wallet_rounded);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 600.0]) {
    for (final scale in [1.0, 1.4]) {
      testWidgets('Retail UI fits narrow screens and large text', (tester) async {
        tester.view.physicalSize = Size(width, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: Builder(builder: (context) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                RetailVisual.hero(
                  context: context,
                  chapter: RetailChapter.purchases,
                  eyebrow: 'Plan Básico · Compras',
                  title: 'Recibe mercadería',
                  subtitle: 'Productos del proveedor ingresados al inventario.',
                  icon: Icons.local_shipping_rounded,
                  footer: Row(children: [
                    Expanded(child: RetailVisual.microStat('Productos', '12 seleccionados')),
                    const SizedBox(width: 8),
                    Expanded(child: RetailVisual.microStat('Compra', 'S/ 1,234.00')),
                  ]),
                ),
                RetailVisual.section(
                  number: 2, title: 'Productos recibidos',
                  subtitle: 'Buscar productos y cantidades',
                  icon: Icons.inventory_2_rounded,
                ),
                RetailVisual.panel(context, child: const Text('Datos reales del inventario')),
                const SizedBox(height: 12),
                RetailVisual.journey(step: 3, label: 'Confirmar pago'),
              ],
            ))),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Recibe mercadería'), findsOneWidget);
        // En 320 px y fuente grande, el ListView construye la etapa 3
        // solo al desplazarla a pantalla; no es un error de renderizado.
        await tester.scrollUntilVisible(
          find.text('Paso 3 de 4'),
          170,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Paso 3 de 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
