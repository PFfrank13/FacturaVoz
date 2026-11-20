import 'dart:convert';
import 'dart:io';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/app_state.dart';
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
import 'package:facturavoz/services/repo.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket/testing.dart' as sockets;
import 'package:web_socket/web_socket.dart'
    show TextDataReceived, WebSocketConnectionClosed;
import 'package:web_socket_channel/adapter_web_socket_channel.dart';

// All HTTP responses and device storage in this preview are in memory.
const _org = 'studio-fixture';
const _user = 'cashier-fixture';
const _rows = [
  ('agua', 'Agua mineral', 'Bebidas', 1.80),
  ('leche', 'Leche fresca', 'Lácteos', 4.90),
  ('pan', 'Pan artesanal', 'Panadería', 5.50),
  ('arroz', 'Arroz extra', 'Abarrotes', 4.50),
];

bool _emptyCatalog = false;

Object? _response(http.Request request) {
  final path = request.url.pathSegments.last;
  if (path == 'token') {
    final exp =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'sub': _user, 'exp': exp})),
    );
    return {
      'access_token': 'eyJhbGciOiJub25lIn0.$payload.fixture',
      'token_type': 'bearer',
      'refresh_token': 'fixture',
      'expires_in': 7200,
      'user': {
        'id': _user,
        'aud': 'authenticated',
        'email': 'demo@example.invalid',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
  }
  if (path == 'products') {
    if (_emptyCatalog) return [];
    return [
      for (final (id, name, category, price) in _rows)
        {
          'id': id,
          'name': name,
          'category': category,
          'unit_price': price,
          'active': true,
          'stock': 14,
          'unit': 'NIU',
        },
    ];
  }
  if (path == 'invoices') {
    final invoices = [
      for (var day = 1; day <= 12; day += 3)
        {
          'id': 'invoice-$day',
          'number': 'DEMO-$day',
          'issue_date': todayIso(
            DateTime(DateTime.now().year, DateTime.now().month, day),
          ),
          'status': 'sent',
          'currency': 'PEN',
          'tax_rate': 0,
          'clients': {'name': 'Mercado Oliva'},
          'invoice_items': [
            {
              'description': 'Pan artesanal',
              'quantity': day,
              'unit_price': 5.5,
            },
          ],
        },
    ];
    if (request.headers['Accept']?.contains('vnd.pgrst.object') == true) {
      return invoices.first;
    }
    return invoices;
  }
  if (path == 'quotes') {
    final quote = {
      'id': 'cotizacion-demo',
      'number': 'COT-001',
      'status': 'draft',
      'issue_date': todayIso(),
      'currency': 'PEN',
      'tax_rate': 0,
      'clients': {'name': 'Mercado Oliva'},
      'quote_items': [
        {'description': 'Pan artesanal', 'quantity': 2, 'unit_price': 5.5},
      ],
    };
    return request.headers['Accept']?.contains('vnd.pgrst.object') == true
        ? quote
        : [quote];
  }
  if (path == 'clients') {
    return [
      {'id': 'cliente-demo', 'name': 'Mercado Oliva'},
    ];
  }
  if (path == 'jobs') {
    return [
      {
        'id': 'trabajo-demo',
        'title': 'Entrega de pan',
        'client_id': 'cliente-demo',
        'clients': {'name': 'Mercado Oliva'},
        'status': 'nuevo',
        'amount': 11,
      },
    ];
  }
  if (path == 'credit_balances') {
    return [
      {
        'client_id': 'cliente-demo',
        'client_name': 'Mercado Oliva',
        'balance': 42.50,
        'charges': 50,
        'payments': 7.50,
      },
    ];
  }
  const sales = {'sales_total': 121.0, 'sales_count': 4, 'drafts_count': 0};
  if (path == 'sales_summary') return sales;
  if (path == 'day_summary') {
    return {
      'sales': sales,
      'cash_opening': 100,
      'expected_cash': 221,
      'cash_sales': 121,
      'payments_by_method': {'efectivo': 121},
      'currency': 'PEN',
    };
  }
  if (path == 'org_settings') {
    return [
      {'org_id': _org, 'business_type': 'bodega'},
    ];
  }
  return [];
}

// The screens subscribe to Supabase even when the fixture contains no changes.
// Acknowledge channel joins, leaves and heartbeats over an in-memory socket.
AdapterWebSocketChannel _realtimeFixture(
  String url,
  Map<String, String> headers,
) {
  final (client, server) = sockets.fakes();
  server.events.listen((event) {
    if (event is! TextDataReceived) return;
    final frame = jsonDecode(event.text) as List<dynamic>;
    final [joinRef, ref, topic, action, _] = frame;
    if (action == 'phx_join' ||
        action == 'phx_leave' ||
        action == 'heartbeat') {
      try {
        server.sendText(
          jsonEncode([
            joinRef,
            ref,
            topic,
            'phx_reply',
            {'status': 'ok', 'response': <String, dynamic>{}},
          ]),
        );
      } on WebSocketConnectionClosed {
        // A leave can already be in flight when the app closes the transport.
        return;
      }
    }
  });
  return AdapterWebSocketChannel(client);
}

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
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    for (final channel in [
      'plugins.flutter.io/quick_actions',
      'com.llfbandit.record/messages',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = call.arguments['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'preview',
      realtimeClientOptions: const RealtimeClientOptions(
        transport: _realtimeFixture,
      ),
      httpClient: MockClient(
        (req) async => http.Response(
          jsonEncode(_response(req)),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'demo@example.invalid',
      password: 'fixture',
    );
    Repo.activeOrgId = _org;
    AppState.instance.profile = Profile(
      businessName: 'Mercado Oliva',
      currency: 'PEN',
      taxRate: 18,
      taxLabel: 'IGV',
      address: 'Dirección de muestra',
    );
    AppState.instance.orgs = const [
      Org(id: _org, name: 'Mercado Oliva', taxId: '', role: 'owner'),
    ];
    Access.instance
      ..rubro = 'bodega'
      ..role = 'owner'
      ..isAdmin = true
      ..licenseCheckedOnline = true
      ..license = LicenseInfo(
        source: 'hub',
        plan: 'EMPRESA',
        mode: 'full',
        status: 'activa',
        enforced: true,
        activated: true,
        features: {
          for (final entry in catalog)
            if (entry.feature != null) entry.feature!: true,
        },
      );
    LiveHub.instance.start();
  });
  tearDownAll(() async {
    LiveHub.instance.stop();
    await Supabase.instance.dispose();
  });

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
    'inicio': (_) => InicioScreen(onNavigate: (_) {}),
    'cobrado': (_) => const PosPaymentSuccessScreen(
      invoiceId: 'invoice-1',
      method: 'efectivo',
      currency: 'PEN',
      total: 5.50,
    ),
    for (final entry in catalog) entry.id: entry.builder,
    'navegacion': (_) => const MainShell(),
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
        _emptyCatalog = entry.key.endsWith('-muestra');
        LiveCache.clear();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
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
          if (_emptyCatalog)
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
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('../../tool/previews/signature/$name.png'),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets('Venta por búsqueda y filtro a ${width.toInt()} dp', (
      tester,
    ) async {
      _emptyCatalog = false;
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
