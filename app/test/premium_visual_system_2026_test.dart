import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/retail_visual.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:facturavoz/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('Tarjetas premium sin blur y tema coherente: $brightness', () {
      final t = buildTheme(brightness);
      final decoration = FvSurfaces.card(t);
      expect(t.useMaterial3, isTrue);
      expect(decoration.gradient, isNotNull);
      expect(decoration.borderRadius, BorderRadius.circular(FvTokens.cardRadius));
      expect(t.colorScheme.onSurface, brightness == Brightness.light
          ? FvTokens.ink : FvTokens.inkDark);
    });

    for (final width in <double>[320, 360, 768, 1024]) {
      testWidgets('Cristal, tarjeta y cabecera legibles a $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    const FvGlassSurface(
                      padding: EdgeInsets.all(16),
                      child: Row(children: [
                        Icon(Icons.storefront_rounded),
                        SizedBox(width: 12),
                        Expanded(child: Text('FacturaVoz · Navegación premium')),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    const SoftCard(
                      child: Text('Importes y documentos siempre legibles'),
                    ),
                    const SizedBox(height: 12),
                    Builder(builder: (context) => RetailVisual.hero(
                      context: context,
                      chapter: RetailChapter.reports,
                      eyebrow: 'Ventas · Bodega',
                      title: 'Resumen del negocio',
                      subtitle: 'Ventas, caja, inventario y comprobantes.',
                      icon: Icons.analytics_rounded,
                    )),
                  ]),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(find.text('Resumen del negocio'), findsOneWidget);
        expect(find.text('Importes y documentos siempre legibles'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Alto contraste elimina blur, conserva interacción y texto',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(highContrast: true),
        child: Scaffold(
          body: Center(
            child: FvGlassSurface(
              blur: 18,
              padding: const EdgeInsets.all(14),
              child: TextButton(onPressed: () {}, child: const Text('Continuar')),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
