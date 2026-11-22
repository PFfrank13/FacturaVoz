// Capturas de la isla dinámica en un iPhone simulado con el motor de Flutter.
//
//   flutter test tool/island_iphone_preview.dart
//
// No es el simulador de Xcode: renderiza el MainShell real (tienda ficticia,
// sin red) a 393×852 pt con la franja superior de 59 pt de un iPhone 15 Pro, y
// dibuja encima la barra de estado y la Dynamic Island física (126×37 pt) para
// comprobar cómo la isla de FacturaVoz se integra con ellas. Los cuadros se
// guardan en tool/previews/isla/<OUT>/ (OUT por defecto: despues).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:facturavoz/screens/shell.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/retail_fixture.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'despues');
const _device = Size(393, 852);
const _strip = 59.0;
final _root = GlobalKey();

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
  await inter.load();
  await (FontLoader('DM Serif Text')
        ..addFont(rootBundle.load('assets/fonts/DMSerifText-Regular.ttf')))
      .load();
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (await icons.exists()) {
    final bytes = await icons.readAsBytes();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
}

/// iOS status bar and the hardware Dynamic Island, painted above the app.
class _IosChrome extends CustomPainter {
  const _IosChrome(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = dark ? Colors.white : Colors.black;
    final time = TextPainter(
      text: TextSpan(
        text: '9:41',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    time.paint(canvas, Offset(58 - time.width / 2, 29.5 - time.height / 2));
    final pen = Paint()..color = ink;
    // Cellular bars.
    for (var i = 0; i < 4; i++) {
      final h = 4.0 + i * 2.4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(299 + i * 5.0, 35 - h, 3.2, h),
          const Radius.circular(1),
        ),
        pen,
      );
    }
    // Wi-Fi arcs.
    final wifi = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final r in const [3.5, 7.5, 11.5]) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(329, 36), radius: r),
        -math.pi * .75,
        math.pi * .5,
        false,
        wifi,
      );
    }
    // Battery.
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(344, 23.5, 25, 12.5),
      const Radius.circular(3.6),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = ink.withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(346, 25.5, 19, 8.5),
        const Radius.circular(2),
      ),
      pen,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(370.5, 27.5, 1.6, 4.5),
        const Radius.circular(1),
      ),
      pen..color = ink.withValues(alpha: .4),
    );
    // Hardware Dynamic Island: 126×37 pt, 11 pt from the top edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, 11 + 18.5),
          width: 126,
          height: 37,
        ),
        const Radius.circular(18.5),
      ),
      Paint()..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(_IosChrome old) => old.dark != dark;
}

Widget _phone(bool dark) => RepaintBoundary(
  key: _root,
  child: Stack(
    textDirection: TextDirection.ltr,
    children: [
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const MainShell(),
      ),
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _IosChrome(dark))),
      ),
    ],
  ),
);

Future<void> _save(WidgetTester tester, String name) async {
  final boundary =
      _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('tool/previews/isla/$_out/$name.png')
      ..createSync(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await startRetailFixture();
    await _loadFonts();
  });
  tearDownAll(stopRetailFixture);

  for (final dark in const [false, true]) {
    final mode = dark ? 'oscuro' : 'claro';
    testWidgets('iPhone simulado ($mode)', (tester) async {
      tester.view
        ..physicalSize = _device
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: _strip, bottom: 34);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_phone(dark));
      await tester.pumpAndSettle();
      await _save(tester, 'iphone-$mode-reposo');
      final pill = find.byKey(const ValueKey('dynamic-island'));
      if (pill.evaluate().isEmpty) return;
      await tester.tap(pill);
      if (!dark) {
        // A 60 fps strip of the transition, for the motion video.
        for (var f = 0; f < 42; f++) {
          await tester.pump(const Duration(milliseconds: 16));
          await _save(tester, 'movimiento/f${f.toString().padLeft(3, '0')}');
        }
      }
      await tester.pumpAndSettle();
      await _save(tester, 'iphone-$mode-expandida');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
