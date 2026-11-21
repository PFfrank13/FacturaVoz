import 'dart:ui' as ui;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import '../test/support/retail_fixture.dart';
import 'package:facturavoz/screens/shell.dart';
import 'package:facturavoz/access.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/screens/retail_basic_modules.dart';
import 'package:facturavoz/screens/retail_receipts.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Se ejecuta en un emulador Android real de GitHub Actions, sin tocar Supabase,
/// sin credenciales y sin emitir ventas o comprobantes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const captureKey = ValueKey('android-preview');
  const captures = bool.fromEnvironment('SIGNATURE_CAPTURES');
  Future<void> pumpScreen(WidgetTester tester, Widget app) => tester.pumpWidget(
    captures ? RepaintBoundary(key: captureKey, child: app) : app,
  );

  Future<void> capture(WidgetTester tester, String name) async {
    if (!captures) return;
    await tester.pumpAndSettle();
    final surface = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
    final image = await surface.toImage(pixelRatio: 1.5);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('No se pudo capturar $name');
      final report = binding.reportData ??= <String, dynamic>{};
      final frames = report.putIfAbsent('screenshots', () => <Map<String, Object>>[])
          as List<Map<String, Object>>;
      frames.add({'screenshotName': name, 'bytes': bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)});
    } finally {
      image.dispose();
    }
  }

  void setLicense(String plan) {
    final a = Access.instance;
    a.rubro = 'bodega';
    a.role = 'owner';
    a.isAdmin = true;
    a.licenseCheckedOnline = true;
    a.license = LicenseInfo(
      source: 'hub',
      plan: plan,
      status: 'activa',
      mode: 'full',
      enforced: true,
      activated: true,
      features: const {
        'facturar': true,
        'stock': true,
        'caja': true,
        'fiados': true,
        'clientes': true,
        'reportes': true,
        'cobros': true,
        'cotizaciones': true,
        'precios': true,
        'voz': true,
        'copiloto': false,
      },
    );
  }

  tearDown(() {
    final a = Access.instance;
    a.rubro = null;
    a.role = 'member';
    a.isAdmin = false;
    a.licenseCheckedOnline = false;
    a.license = const LicenseInfo();
  });

  testWidgets('Android muestra tablero Bodega Básico sin menús premium', (tester) async {
    setLicense('BASICO');
    await pumpScreen(tester, MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: SingleChildScrollView(
        child: RetailBasicModules(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retail-module-pos')), findsOneWidget);
    await capture(tester, 'plan-basico');
    expect(find.byKey(const ValueKey('retail-basic-modules')), findsOneWidget);
    expect(find.text('FacturaVoz · Plan Básico'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.textContaining('Copiloto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android muestra tablero Empresa sin duplicados de navegación', (tester) async {
    setLicense('EMPRESA');
    await pumpScreen(tester, MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(body: SingleChildScrollView(
        child: RetailPlanModules(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retail-plan-modules')), findsOneWidget);
    await capture(tester, 'plan-empresa');
    expect(find.text('FacturaVoz · Plan Empresa'), findsOneWidget);
    expect(find.text('Nueva venta'), findsOneWidget);
    expect(find.text('Todas mis funciones'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android renderiza y permite tocar acción de comprobantes', (tester) async {
    var touched = 0;
    await pumpScreen(tester, MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(
        child: RetailReceiptActionTile(
          icon: Icons.receipt_long_rounded,
          label: '1. Emitir comprobante',
          caption: 'Revisar cliente y productos; confirmar en SUNAT al final',
          onTap: () => touched++,
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1. Emitir comprobante'), findsOneWidget);
    await tester.tap(find.text('1. Emitir comprobante'));
    await tester.pumpAndSettle();
    expect(touched, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android mantiene carrito y control de cantidades', (tester) async {
    final lines = <LineItem>[
      LineItem(productId: 'p1', description: 'Aceite vegetal',
        quantity: 1, unitPrice: 9.50),
    ];
    await pumpScreen(tester, MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: PosCartReviewScreen(
        currency: 'PEN',
        taxRate: 18,
        productImages: const {},
        lines: () => lines,
        onChangeQuantity: (id, change) => lines.first.quantity += change,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retail-continue-payment')), findsOneWidget);
    await tester.tap(find.byTooltip('Agregar uno').first);
    await tester.pumpAndSettle();
    await capture(tester, 'carrito');
    expect(lines.first.quantity, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Android valida efectivo insuficiente y vuelto sin registrar ventas',
      (tester) async {
    PosPaymentApproval? result;
    await pumpScreen(tester, MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: Builder(builder: (context) => Scaffold(body: Center(
        child: FilledButton(
          key: const ValueKey('phase4-open-cash'),
          onPressed: () async {
            result = await confirmPosPayment(context,
                method: 'efectivo', currency: 'PEN', total: 7.85);
          },
          child: const Text('Abrir prueba de cobro'),
        ),
      ))),
    ));
    await tester.tap(find.byKey(const ValueKey('phase4-open-cash')));
    await tester.pumpAndSettle();
    expect(find.text('Cobro efectivo'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirmar pago');
    await tester.enterText(find.byType(TextField).first, '7.84');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '10.00');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(find.textContaining('Vuelto: S/ 2.15'), findsWidgets);
    await capture(tester, 'efectivo');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result?.method, 'efectivo');
    expect(result?.note, contains('Vuelto:'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android abre avisos desde Inicio y actualiza la campana al leer', (tester) async {
    await startRetailFixture();
    try {
      fixtureAlertRead = false;
      await pumpScreen(tester, MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const MainShell(),
      ));
      await tester.pumpAndSettle();
      final bell = find.byKey(const ValueKey('bodega-notifications'));
      final menu = find.byKey(const ValueKey('bodega-open-menu'));
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getCenter(menu).dx, lessThan(64));
      expect(tester.getCenter(bell).dx, greaterThan(width - 64));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NavigationDrawerDestination, 'Comprobantes'), findsOneWidget);
      // A tap on the scrim closes the drawer as it would in the app.
      await tester.tapAt(Offset(width - 5, 140));
      await tester.pumpAndSettle();
      await capture(tester, 'inicio-bodega');
      final plot = find.byKey(const ValueKey('retail-trend-plot'));
      final plotBounds = tester.getRect(plot);
      await tester.tapAt(Offset(plotBounds.right - 2, plotBounds.center.dy));
      await tester.pumpAndSettle();
      expect(find.textContaining('· S/ 55.00'), findsOneWidget);
      await capture(tester, 'tendencia-diaria');
      final island = find.byKey(const ValueKey('dynamic-island'));
      await tester.tap(island);
      await tester.pumpAndSettle();
      final notice = find.byKey(const ValueKey('dynamic-island-notice'));
      expect(notice, findsOneWidget);
      expect(find.text('Diferencia en cierre de caja'), findsOneWidget);
      await capture(tester, 'isla-aviso');
      await tester.tap(notice);
      await tester.pumpAndSettle();
      expect(find.text('Alertas del negocio'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(120, 480), const Offset(0, -270));
      await tester.pumpAndSettle();
      expect(bell.hitTestable(), findsOneWidget);
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.text('Diferencia en cierre de caja'), findsOneWidget);
      await capture(tester, 'notificaciones');
      await tester.tap(find.text('Marcar todas como leídas'));
      await tester.pumpAndSettle();
      expect(fixtureAlertRead, isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await stopRetailFixture();
    }
  });

}
