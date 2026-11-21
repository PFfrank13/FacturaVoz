import 'dart:io';

import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/assistant.dart';
import 'package:facturavoz/screens/home.dart';
import 'package:facturavoz/screens/shell.dart';
import 'package:facturavoz/screens/clients.dart';
import 'package:facturavoz/screens/client_profile.dart';
import 'package:facturavoz/screens/jobs.dart';
import 'package:facturavoz/screens/quotes.dart';
import 'package:facturavoz/screens/retail_settlements.dart';
import 'package:facturavoz/screens/security.dart';
import 'package:facturavoz/screens/sell_hub.dart';
import 'package:facturavoz/screens/settings_v2.dart';
import 'package:facturavoz/screens/store_v2.dart';
import 'package:facturavoz/screens/welcome_employee.dart';
import 'package:facturavoz/screens/menu.dart';
import 'package:facturavoz/screens/workbook_import.dart';
import 'package:facturavoz/screens/license_gate.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:facturavoz/screens/inicio.dart';
import 'package:facturavoz/screens/pos.dart';
import 'package:facturavoz/screens/login.dart';
import 'package:facturavoz/screens/emit_sunat.dart';
import 'package:facturavoz/screens/invoice_detail.dart';
import 'package:facturavoz/screens/onboarding.dart';
import 'package:facturavoz/screens/employee_login.dart';
import 'package:facturavoz/screens/products.dart';
import 'package:facturavoz/screens/pos_payment.dart';
import 'package:facturavoz/screens/pos_payment_success.dart';
import 'package:facturavoz/services/live.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/retail_fixture.dart';

Future<void> _fonts() async {
  for (final entry in {
    'Inter': [
      'Inter-Regular.otf',
      'Inter-Medium.otf',
      'Inter-SemiBold.otf',
      'Inter-Bold.otf',
    ],
    'monospace': ['DejaVuSans.ttf'],
    'DM Serif Text': ['DMSerifText-Regular.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final font in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/$font'));
    }
    await loader.load();
  }
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final bytes = await File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = featureCatalog();
  setUpAll(() async {
    await _fonts();
    await startRetailFixture();
  });
  tearDownAll(stopRetailFixture);

  final screens = <String, WidgetBuilder>{
    'assistant': (_) => const RangeSalesScreen(range: 'this_month'),
    'home': (_) => const HomeScreen(),
    'clients': (_) => const ClientsScreen(),
    'client-profile': (_) =>
        const ClientProfileScreen(clientId: 'cliente-demo'),
    'jobs': (_) => const JobDetailScreen(jobId: 'trabajo-demo'),
    'quotes': (_) => const QuoteDetailScreen(quoteId: 'cotizacion-demo'),
    'retail-settlements': (_) => const RetailSettlementScreen(),
    'security': (_) => const ChangePinScreen(),
    'sell-hub': (_) => const SellHubScreen(),
    'settings-v2': (_) => const JobFlowScreen(),
    'store-v2': (_) => const StoreOptionsScreen(),
    'welcome-employee': (_) => const EmployeeWelcomeScreen(),
    'menu': (_) => const MenuScreen(),
    'workbook-import': (_) => const WorkbookHistoryScreen(),
    'license-gate': (_) => const LicenseVerificationScreen(),
    'buscar': (_) => const UniversalSearchScreen(),
    'funciones': (_) => const AllFunctionsScreen(),
    'licencia': (_) => const LicenseGateScreen(),
    'bienvenida': (_) => OnboardingScreen(onDone: () {}),
    'acceso-empresa': (context) => Scaffold(
      body: FilledButton(
        onPressed: () => showEmployeeLogin(context),
        child: const Text('Abrir acceso de empresa'),
      ),
    ),
    'emision': (_) => EmitSunatScreen(
      company: FiscalCompany(ruc: '00000000000', env: 'beta'),
      invoice: InvoiceRecord.fromJson({
        'id': 'invoice-1',
        'number': 'DEMO-1',
        'issue_date': todayIso(),
        'status': 'sent',
        'currency': 'PEN',
        'tax_rate': 0,
        'invoice_items': [
          {'description': 'Pan artesanal', 'quantity': 1, 'unit_price': 5.50},
        ],
      }),
    ),
    'detalle': (_) => const InvoiceDetailScreen(invoiceId: 'invoice-1'),
    'acceso': (_) => const LoginScreen(),
    'pos-muestra': (_) => const PosScreen(),
    'inventario-muestra': (_) => const ProductsScreen(),
    'pago': (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => choosePosPayment(
            context,
            currency: 'PEN',
            total: 5.50,
            items: [
              LineItem(
                description: 'Pan artesanal',
                quantity: 1,
                unitPrice: 5.50,
              ),
            ],
          ),
          child: const Text('Abrir cobro'),
        ),
      ),
    ),
    'inicio': (_) => const InicioScreen(),
    'cobrado': (_) => const PosPaymentSuccessScreen(
      invoiceId: 'invoice-1',
      method: 'efectivo',
      currency: 'PEN',
      total: 5.50,
    ),
    for (final entry in catalog) entry.id: entry.builder,
    'navegacion': (_) => const MainShell(),
    'notificaciones': (_) => const MainShell(),
    'isla': (_) => const MainShell(),
    'inicio-scroll': (_) => const MainShell(),
  };
  const core = {
    'navegacion',
    'inicio',
    'pos',
    'productos',
    'compras',
    'fiados',
    'caja',
    'reportes',
    'comprobantes',
    'ajustes',
    'cobrado',
  };
  for (final entry in screens.entries) {
    final variants = core.contains(entry.key)
        ? [
            (390.0, 844.0, false, 1.0),
            (320.0, 720.0, true, 1.4),
            (768.0, 1024.0, true, 1.0),
            (1280.0, 850.0, false, 1.0),
          ]
        : [(390.0, 844.0, false, 1.0)];
    for (final (width, height, dark, scale) in variants) {
      final name = '${entry.key}-${width.toInt()}';
      testWidgets('Signature $name', (tester) async {
        fixtureAlertRead = false;
        emptyRetailCatalog = entry.key.endsWith('-muestra');
        LiveCache.clear();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: child!,
                ),
              ),
            ),
            home: Builder(builder: entry.value),
          ),
        );
        if (entry.key == 'acceso-empresa') {
          await tester.tap(find.text('Abrir acceso de empresa'));
        }
        if (entry.key == 'pago') await tester.tap(find.text('Abrir cobro'));
        final context = tester.element(find.byKey(const ValueKey('capture')));
        final assets = <String>[
          if (emptyRetailCatalog)
            for (final name in [
              'water',
              'milk',
              'rice',
              'oil',
              'bread',
              'cookies',
            ])
              'assets/demo/$name.webp',
          if ([
            'acceso',
            'bienvenida',
            'presentacion',
            'tipo',
            'clientes',
            'inicio',
          ].contains(entry.key))
            for (final name in [
              'bodega',
              'mini_market',
              'restaurante',
              'servicios_tecnicos',
              'salon',
              'consultorio',
              'construccion',
              'mayorista',
              'taller',
              'educacion',
            ])
              'assets/photos/$name.webp',
        ];
        await tester.runAsync(
          () => Future.wait([
            for (final asset in assets)
              precacheImage(AssetImage(asset), context),
          ]),
        );
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (entry.key == 'isla') {
          await tester.tap(find.byKey(const ValueKey('dynamic-island')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('dynamic-island-notice')), findsOneWidget);
          expect(find.text('Diferencia en cierre de caja'), findsOneWidget);
        }
        if (entry.key == 'notificaciones') {
          await tester.tap(find.byKey(const ValueKey('bodega-notifications')));
          await tester.pumpAndSettle();
          expect(find.text('Diferencia en cierre de caja'), findsOneWidget);
        }
        if (entry.key == 'inicio-scroll') {
          await tester.dragFrom(const Offset(110, 510), const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('bodega-notifications')).hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('../../tool/previews/signature/$name.png'),
        );
        if (entry.key == 'inicio-scroll' || name == 'navegacion-320') {
          // The four fixture receipts fit above the dock when scrolled to the
          // end, including when large text makes the dock use two rows.
          await tester.dragFrom(const Offset(110, 510), const Offset(0, -3500));
          await tester.pumpAndSettle();
          final lastReceipt = find.byKey(const ValueKey('invoice-10'));
          final dock = find.byKey(const ValueKey('bodega-premium-bottom-dock'));
          expect(lastReceipt.hitTestable(), findsOneWidget);
          expect(tester.getBottomLeft(lastReceipt).dy,
              lessThanOrEqualTo(tester.getTopLeft(dock).dy));
        }
        if (name == 'navegacion-390') {
          for (final label in ['Ventas', 'Inventario', 'Caja']) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.tap(find.byKey(const ValueKey('bodega-dock-more')));
          await tester.pumpAndSettle();
          final receipts = find.widgetWithText(
            NavigationDrawerDestination,
            'Comprobantes',
          );
          expect(
            find.widgetWithText(NavigationDrawerDestination, 'Fiados'),
            findsOneWidget,
          );
          await tester.ensureVisible(receipts);
          await tester.tap(receipts);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(AppBar, 'Comprobantes'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets('Venta por búsqueda y filtro a ${width.toInt()} dp', (
      tester,
    ) async {
      emptyRetailCatalog = false;
      LiveCache.clear();
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: PosScreen(embedded: true)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bebidas'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Añadir Pan artesanal'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Agua');
      await tester.tap(find.byTooltip('Añadir Agua mineral'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpAndSettle();
      final side = width >= 900;
      final review = find.byKey(
        ValueKey(side ? 'retail-pos-desktop-charge' : 'retail-pos-charge'),
      );
      expect(review, findsOneWidget);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Agregar uno'), findsOneWidget);
      await tester.tap(find.byTooltip('Agregar uno'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
