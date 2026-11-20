import 'dart:io';
import 'dart:typed_data';

import 'package:facturavoz/ui/credit_luxe_widgets.dart';
import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/retail_visual.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

// Fixture visual: no pertenece a un negocio real.
Widget _screen() => MaterialApp(
  theme: buildTheme(Brightness.light),
  debugShowCheckedModeBanner: false,
  home: RepaintBoundary(
    key: const ValueKey('fiados-preview'),
    child: Scaffold(
      appBar: AppBar(title: const Text('Fiados')),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: FvLuxe.ambient(Brightness.light)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(builder: (context) => RetailVisual.hero(
                context: context,
                eyebrow: 'CLIENTES · CUENTAS POR COBRAR',
                title: 'Tus fiados, al día',
                subtitle: 'Vista de prueba sin clientes ni cobros reales.',
                icon: Icons.menu_book_rounded)),
              const SizedBox(height: 14),
              const FvCreditBalanceCard(
                name: 'María Torres',
                amount: 'S/ 63.50',
                hasBalance: true,
                overdue: true,
                dueLabel: 'Vencido desde 18 nov',
                lastMovement: '19 nov · 11:40'),
              const SizedBox(height: 12),
              const FvCreditBalanceCard(
                name: 'Luis Mendoza',
                amount: 'S/ 29.90',
                hasBalance: true,
                dueLabel: 'Paga hasta 25 nov',
                lastMovement: '20 nov · 09:20'),
              const SizedBox(height: 12),
              const FvCreditBalanceCard(
                name: 'Ana Flores',
                amount: 'S/ 0.00',
                hasBalance: false,
                lastMovement: '18 nov · 16:05'),
            ]),
        ),
      ),
    ),
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

  testWidgets('Fiados reales de Flutter, datos ilustrativos', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const ValueKey('fiados-preview')),
      matchesGoldenFile('previews/fiados.png'));
    expect(tester.takeException(), isNull);
  });
}
