import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/retail_receipts.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 390.0, 600.0]) {
      for (final scale in [1.0, 1.4]) {
        testWidgets('Acciones de comprobantes ${brightness.name} ${width}px x$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var opens = 0;
          await tester.pumpWidget(MaterialApp(
            theme: buildTheme(brightness),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  RetailReceiptActionTile(
                    key: const ValueKey('receipt-emit-action'),
                    icon: Icons.note_add_rounded,
                    label: '1. Emitir comprobante',
                    caption: 'Elige boleta o factura, revisa cliente y productos, confirma en SUNAT',
                    onTap: () => opens++,
                  ),
                  const SizedBox(height: 12),
                  const RetailReceiptActionTile(
                    icon: Icons.admin_panel_settings_rounded,
                    label: '3. Configuración SUNAT',
                    caption: 'RUC, entorno, usuario SOL y certificado digital',
                    onTap: null,
                  ),
                ]),
              )),
            ),
          ));
          await tester.pumpAndSettle();
          expect(find.text('1. Emitir comprobante'), findsOneWidget);
          expect(find.text('3. Configuración SUNAT'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('receipt-emit-action')));
          expect(opens, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
