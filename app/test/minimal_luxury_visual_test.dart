import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/demo_pos_gallery.dart';
import 'package:facturavoz/ui/glass_widgets.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('neutral tokens', () {
    expect(FvTokens.canvas, const Color(0xFFF2F7FC));
    expect(FvTokens.canvasDark, const Color(0xFF0E1723));
    expect(buildTheme(Brightness.light).scaffoldBackgroundColor,
        FvTokens.canvas);
  });
  testWidgets('glass respects high contrast', (tester) async {
    for (final contrast in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(highContrast: contrast),
          child: const Scaffold(body: FvGlassTopBar()),
        ),
      ));
      expect(find.byType(BackdropFilter),
          contrast ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('inventory previews products without stock mutation', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: SingleChildScrollView(
        child: FvDemoInventoryGallery(loadPhotos: false))),
    ));
    expect(find.text('Vista de muestra'), findsOneWidget);
    expect(find.text('Ejemplo · sin stock registrado'), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('display-only gallery has no real payment', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: FvDemoPosGallery(loadPhotos: false)),
    ));
    expect(find.text('Vista de demostración'), findsOneWidget);
    expect(find.byType(FvProductPhotoFallback), findsWidgets);
    await tester.tap(find.byTooltip('Añadir Agua mineral 625 ml'));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('demo-gallery-scroll')),
        const Offset(0, -950));
    await tester.pumpAndSettle();
    expect(find.text('1 artículo de muestra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
