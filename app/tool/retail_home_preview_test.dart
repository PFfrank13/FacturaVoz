import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:facturavoz/ui/ds.dart';
import 'package:facturavoz/ui/glass_widgets.dart';
import 'package:facturavoz/ui/retail_home_premium.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Real Flutter pixels for a supervised visual review. Figures are fixtures
/// copied from the example screenshot; never presented as a live data read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory('tool/goldens').createSync(recursive: true);
  setUpAll(() async {
    final appFonts = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      appFonts.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
    }
    await appFonts.load();

    // Widget tests use Ahem blocks unless real glyph fonts are installed.
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null || sdk.isEmpty) {
      throw StateError('FLUTTER_ROOT is needed for visual previews');
    }
    final iconFile = File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (!iconFile.existsSync()) {
      throw StateError('Missing MaterialIcons: ${iconFile.path}');
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(iconFile.readAsBytes().then(ByteData.sublistView));
    await icons.load();
  });
  for (final width in <double>[320, 390]) {
    testWidgets('Inicio Flutter preview $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: RepaintBoundary(
          key: const ValueKey('retail-home-preview'),
          child: Scaffold(
            appBar: AppBar(
              flexibleSpace: const FvGlassTopBar(),
              leading: const Icon(Icons.menu_rounded),
              title: const Text('Inicio'),
            ),
            body: SingleChildScrollView(
              key: const ValueKey('preview-scroll'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RetailPremiumHero(
                      name: 'Solvex',
                      currency: 'PEN',
                      total: 29.50,
                      count: 2,
                      loaded: true,
                      showMonth: true,
                      todayTotal: 0,
                      drafts: 1,
                      goal: null,
                      series: const [0, 0, 0, 0, 0, 18, 0, 0, 0, 0, 0, 11.50, 0, 0],
                      onGoal: () {},
                    ),
                    RetailHomeShortcuts(
                      items: const [
                        RetailHomeShortcut('sell', 'Venta rápida',
                            Icons.shopping_bag_rounded, Color(0xFFD97763)),
                        RetailHomeShortcut('stock', 'Inventario',
                            Icons.inventory_2_rounded, Color(0xFF5785C6)),
                        RetailHomeShortcut('comprobantes', 'Comprobantes',
                            Icons.receipt_long_rounded, Color(0xFF927BC5)),
                        RetailHomeShortcut('cash', 'Caja',
                            Icons.point_of_sale_rounded, Color(0xFFD39552)),
                      ],
                      onSelect: (_) {},
                    ),
                    const SizedBox(height: 22),
                    const Text('Hoy', style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: DsStat(label: 'Ventas de hoy',
                        value: 'S/ 0.00', detail: '0 ventas',
                        accent: Color(0xFF527CC2),
                        icon: Icons.trending_up_rounded)),
                      SizedBox(width: 10),
                      Expanded(child: DsStat(label: 'Estado de mi caja',
                        value: 'Sin abrir', detail: 'Toca para abrirla',
                        accent: Color(0xFFD08C48),
                        icon: Icons.point_of_sale_rounded)),
                    ]),
                    const SizedBox(height: 10),
                    const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: DsStat(label: 'Fiados por cobrar',
                        value: 'S/ 0.00', detail: '0 clientes',
                        accent: Color(0xFFAC7494),
                        icon: Icons.menu_book_rounded)),
                      SizedBox(width: 10),
                      Expanded(child: DsStat(label: 'Stock bajo',
                        value: '0', detail: 'Todo en orden',
                        accent: Color(0xFF338B72),
                        icon: Icons.inventory_2_rounded)),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('retail-home-preview')),
        matchesGoldenFile('goldens/retail_home_${width.toInt()}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
