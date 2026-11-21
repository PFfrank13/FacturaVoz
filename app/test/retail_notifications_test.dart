import 'dart:async';
import 'dart:convert';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/logic/data_scope.dart';
import 'package:facturavoz/screens/retail_notifications.dart';
import 'package:facturavoz/services/repo.dart';
import 'package:facturavoz/services/live.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  final read = <String>{};
  var alertNumber = 1;
  Completer<void>? waitForOldCompany;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final params = request.url.queryParameters;
        final org = params['org_id'];
        if (request.url.pathSegments.last != 'owner_alerts' || org == null) {
          throw StateError('Unscoped request to ${request.url}');
        }
        if (request.method == 'PATCH') {
          read.add(org);
          return http.Response('', 204, request: request);
        }
        if (org == 'eq.oliva') {
          await waitForOldCompany?.future;
        }
        final rows = [
          if (!read.contains(org) || params['read_at'] != 'is.null')
            {
              'id': 'alert-$alertNumber',
              'title': 'Cierre de $org',
              'body': 'Detalle $alertNumber',
              'created_at': '2026-03-0${alertNumber}T12:00:00Z',
              if (read.contains(org)) 'read_at': '2026-03-08T12:00:00Z',
            },
        ];
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final expires =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'sub': 'test', 'exp': expires})),
    );
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJub25lIn0.$payload.fixture',
        'token_type': 'bearer',
        'refresh_token': 'fixture',
        'user': {
          'id': 'test',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    read.clear();
    alertNumber = 1;
    waitForOldCompany = null;
    Repo.activeOrgId = 'oliva';
    Access.instance
      ..isAdmin = true
      ..licenseCheckedOnline = true
      ..license = const LicenseInfo(
        mode: 'full',
        source: 'hub',
        features: {'antifraude': true},
      );
  });

  Future<void> mountHeader(WidgetTester tester) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffold,
          drawer: const Drawer(child: Text('Menú de mi negocio')),
          appBar: RetailNotificationHeader(
            title: 'Inicio',
            onMenu: () => scaffold.currentState!.openDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openBell(WidgetTester tester) async {
    await mountHeader(tester);
    await tester.tap(find.byKey(const ValueKey('bodega-notifications')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'la campana carga el aviso real y actualiza su indicador al marcarlo leído',
    (tester) async {
      await openBell(tester);
      final first = requests.first.url.queryParameters;
      expect(first['select'], 'id,title,body,severity,created_at');
      expect(first['read_at'], 'is.null');
      expect(first['limit'], '1');
      expect(find.text('Cierre de eq.oliva'), findsOneWidget);
      expect(find.textContaining('Sin leer'), findsOneWidget);
      expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
      await tester.tap(find.text('Marcar todas como leídas'));
      await tester.pumpAndSettle();
      final write = requests.singleWhere((r) => r.method == 'PATCH');
      expect(write.url.queryParameters['org_id'], 'eq.oliva');
      expect(write.url.queryParameters['read_at'], 'is.null');
      expect(find.textContaining('Sin leer'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
    },
  );

  testWidgets('menú, isla y campana ocupan sus posiciones a 320 dp', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.reset);
    await mountHeader(tester);
    final menu = find.byKey(const ValueKey('bodega-open-menu'));
    final bell = find.byKey(const ValueKey('bodega-notifications'));
    final island = find.byKey(const ValueKey('dynamic-island'));
    expect(tester.getCenter(menu).dx, lessThan(52));
    expect(tester.getCenter(island).dx, closeTo(160, 1));
    expect(tester.getCenter(bell).dx, greaterThan(268));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Menú de mi negocio'), findsOneWidget);
  });

  testWidgets('la isla anuncia una alerta nueva una sola vez', (tester) async {
    await mountHeader(tester);
    final card = find.byKey(const ValueKey('dynamic-island-notice'));
    expect(card, findsNothing);
    alertNumber = 2;
    LiveHub.instance.tick('owner_alerts').value++;
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(find.text('Detalle 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    LiveHub.instance.tick('owner_alerts').value++;
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    alertNumber = 1;
    LiveHub.instance.tick('owner_alerts').value++;
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    await tester.tap(find.byKey(const ValueKey('dynamic-island')));
    await tester.pumpAndSettle();
    expect(find.text('Detalle 1'), findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Alertas del negocio'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
  });

  testWidgets('la isla no anuncia al volver del centro ni al reanudar la app', (
    tester,
  ) async {
    await mountHeader(tester);
    final card = find.byKey(const ValueKey('dynamic-island-notice'));
    alertNumber = 2;
    LiveHub.instance.tick('owner_alerts').value++;
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    alertNumber = 3;
    LiveHub.instance.tick('owner_alerts').value++;
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    alertNumber = 4;
    LiveHub.instance.tick('owner_alerts').value++;
    await tester.pumpAndSettle();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    await tester.tap(find.byKey(const ValueKey('dynamic-island')));
    await tester.pumpAndSettle();
    expect(find.text('Detalle 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'la isla retira datos al cambiar de empresa mientras está abierta',
    (tester) async {
      await mountHeader(tester);
      await tester.tap(find.byKey(const ValueKey('dynamic-island')));
      await tester.pumpAndSettle();
      expect(find.text('Cierre de eq.oliva'), findsOneWidget);
      Repo.activeOrgId = 'nueva';
      dataScope.value++;
      await tester.pumpAndSettle();
      expect(find.text('Cierre de eq.oliva'), findsNothing);
      expect(find.byKey(const ValueKey('dynamic-island-notice')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dynamic-island')));
      await tester.pumpAndSettle();
      expect(find.text('Cierre de eq.nueva'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final admin in [false, true]) {
    testWidgets(
      'respeta rol y licencia antes de consultar alertas (admin $admin)',
      (tester) async {
        Access.instance
          ..isAdmin = admin
          ..license = LicenseInfo(
            mode: 'warning',
            source: 'hub',
            message: 'Tu prueba termina mañana.',
            features: {'antifraude': !admin},
          );
        await openBell(tester);
        expect(find.text('Tu prueba termina mañana.'), findsOneWidget);
        expect(find.text('Alertas del negocio'), findsNothing);
        await tester.tap(find.text('Tu plan'));
        await tester.pumpAndSettle();
        expect(find.text('Mi plan'), findsOneWidget);
        expect(requests, isEmpty);
      },
    );
  }

  testWidgets(
    'descarta la respuesta de la empresa anterior aunque llegue tarde',
    (tester) async {
      waitForOldCompany = Completer<void>();
      await tester.pumpWidget(
        const MaterialApp(home: RetailNotificationsScreen()),
      );
      await tester.pump();
      expect(requests.last.url.queryParameters['org_id'], 'eq.oliva');
      Repo.activeOrgId = 'nueva';
      dataScope.value++;
      await tester.pumpAndSettle();
      expect(find.text('Cierre de eq.nueva'), findsOneWidget);
      waitForOldCompany!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cierre de eq.oliva'), findsNothing);
      expect(find.text('Cierre de eq.nueva'), findsOneWidget);
    },
  );
}
