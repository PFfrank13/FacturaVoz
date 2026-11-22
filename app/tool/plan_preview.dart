// Captura de la comparación de planes con los precios vigentes.
//   flutter test tool/plan_preview.dart
// Renderiza el widget real PlanCompare sobre la aurora, a tamaño de teléfono.
import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:facturavoz/screens/plan_compare.dart';
import 'package:facturavoz/ui/liquid_glass.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

final _root = GlobalKey();

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
    await inter.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (await icons.exists()) {
      final bytes = await icons.readAsBytes();
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  testWidgets('planes con precios vigentes', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 1900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _root,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: FvAurora(child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PlanCompare(rubro: 'bodega', currentPlan: 'BASICO', onChoose: (_) {}),
          )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('S/ 39'), findsOneWidget);
    expect(find.text('S/ 79'), findsOneWidget);
    expect(find.text('S/ 179'), findsOneWidget);
    final boundary = _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('tool/previews/ajustes/planes-precios.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
