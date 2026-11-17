import 'package:facturavoz/access.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/pos_cart_review.dart';
import 'package:facturavoz/screens/retail_basic_modules.dart';
import 'package:facturavoz/screens/retail_receipts.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Se ejecuta en un emulador Android real de GitHub Actions, sin tocar Supabase,
/// sin credenciales y sin emitir ventas o comprobantes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
    expect(lines.first.quantity, 2);
    expect(tester.takeException(), isNull);
  });
}
