import 'package:facturavoz/access.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/screens/retail_basic_modules.dart';
import 'package:facturavoz/screens/retail_receipts.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Se ejecuta en un emulador Android real de GitHub Actions, sin tocar Supabase,
/// sin credenciales y sin emitir ventas o comprobantes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('SIGNATURE_CAPTURES')) return;
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
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
    await tester.pumpWidget(MaterialApp(
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
    await tester.pumpWidget(MaterialApp(
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
    await tester.pumpWidget(MaterialApp(
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
    await tester.pumpWidget(MaterialApp(
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
    await tester.pumpWidget(MaterialApp(
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

}
