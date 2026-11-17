import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/retail_visual.dart';

void main() {
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
        expect(find.text('PASO 3 DE 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
