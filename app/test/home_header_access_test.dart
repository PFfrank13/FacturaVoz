import 'package:facturavoz/access.dart';
import 'package:facturavoz/screens/home.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:facturavoz/ui/motion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/shared_preferences'), (call) async => call.method == 'getAll' ? <String, Object>{} : true);
    await Supabase.initialize(url: 'http://127.0.0.1:1', publishableKey: 'local-widget-fixture', authOptions: const FlutterAuthClientOptions(autoRefreshToken: false, localStorage: EmptyLocalStorage()));
    MotionPrefs.userReduced.value = true;
  });
  tearDownAll(() async { MotionPrefs.userReduced.value = null; await Supabase.instance.dispose(); });
  setUp(() => Access.instance.clear());
  tearDown(() => Access.instance.clear());
  for (final width in [320.0, 768.0]) {
    testWidgets('summary error is not a zero sale at $width and can retry', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retried = false;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(
        body: SingleChildScrollView(child: HomeHeader(name: 'Tienda de prueba', currency: 'PEN',
          total: 0, count: 0, drafts: 0, draftsTotal: 0, loaded: false, goal: null,
          series: const [], onGoal: () {}, onMenu: () {}, canEditGoal: false,
          summaryError: 'No pudimos actualizar el resumen.', onRetrySummary: () => retried = true)),
      )));
      await tester.pump(const Duration(seconds: 1)); // Aurora has a repeating ambient animation.
      expect(find.text('No pudimos actualizar el resumen.'), findsOneWidget);
      expect(find.text('Aún sin ventas emitidas este mes'), findsNothing);
      expect(find.text('Copiloto'), findsNothing);
      expect(find.text('Fijar meta'), findsNothing);
      await tester.tap(find.text('Reintentar resumen'));
      expect(retried, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('role without financial access sees no totals or goal', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(
      body: HomeHeader(name: 'Tienda de prueba', currency: 'PEN', total: 150, count: 2,
        drafts: 0, draftsTotal: 0, loaded: false, goal: null, series: const [],
        onGoal: () {}, onMenu: () {}, showMetrics: false, canEditGoal: false),
    )));
    await tester.pump(const Duration(seconds: 1)); // Aurora has a repeating ambient animation.
    expect(find.text('Vendido este mes (con IGV)'), findsNothing);
    expect(find.text('Fijar meta'), findsNothing);
    expect(find.text('Menú'), findsOneWidget);
  });
}
