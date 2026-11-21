import 'dart:async';
import 'dart:convert';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/logic/data_scope.dart';
import 'package:facturavoz/screens/retail_notifications.dart';
import 'package:facturavoz/services/repo.dart';
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
        if (org == 'eq.oliva' && params['select'] != 'id') {
          await waitForOldCompany?.future;
        }
        final rows = params['select'] == 'id'
            ? [
                if (!read.contains(org)) {'id': 'alert'},
              ]
            : [
                {
                  'id': 'alert',
                  'title': 'Cierre de $org',
                  if (read.contains(org)) 'read_at': '2026-03-01T12:00:00Z',
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

  Future<void> openBell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(leading: const RetailNotificationBell())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bodega-notifications')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'la campana carga el aviso real y actualiza su indicador al marcarlo leído',
    (tester) async {
      await openBell(tester);
      final first = requests.first.url.queryParameters;
      expect(first['select'], 'id');
      expect(first['read_at'], 'is.null');
      expect(first['limit'], '1');
      expect(find.text('Cierre de eq.oliva'), findsOneWidget);
      expect(find.text('Sin leer'), findsOneWidget);
      expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
      await tester.tap(find.text('Marcar todas como leídas'));
      await tester.pumpAndSettle();
      final write = requests.singleWhere((r) => r.method == 'PATCH');
      expect(write.url.queryParameters['org_id'], 'eq.oliva');
      expect(write.url.queryParameters['read_at'], 'is.null');
      expect(find.text('Sin leer'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
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
