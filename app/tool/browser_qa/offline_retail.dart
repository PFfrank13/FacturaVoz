import 'dart:convert';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/app_state.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:facturavoz/services/live.dart';
import 'package:facturavoz/services/repo.dart';
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

bool emptyRetailCatalog = false;
bool fixtureAlertRead = false;
final _pushedAlerts = <Map<String, Object?>>[];

/// Adds a strictly newer, unread fictitious alert (QA recordings only).
void pushFixtureAlert({
  required String title,
  required String body,
  String severity = 'good',
}) {
  final now = DateTime.now();
  _pushedAlerts.add({
    'id': 'alert-live-${_pushedAlerts.length}',
    'kind': 'demo',
    'title': title,
    'body': body,
    'severity': severity,
    'created_at': now.toIso8601String(),
    'read_at': null,
  });
}

const _salePrice = 5.50;
late List<({int quantity, String date})> _sales;

Map<String, num> _summary(Iterable<({int quantity, String date})> sales) => {
  'sales_total': sales.fold(0.0, (total, sale) => total + sale.quantity * _salePrice),
  'sales_count': sales.length,
  'drafts_count': 0,
};

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
  if (path == 'owner_alerts') {
    if (request.method == 'PATCH') {
      fixtureAlertRead = true;
      return [];
    }
    if (request.url.queryParameters['read_at'] == 'is.null' &&
        fixtureAlertRead) {
      return _pushedAlerts.reversed.take(1).toList();
    }
    if (_pushedAlerts.isNotEmpty &&
        request.url.queryParameters['limit'] == '1') {
      return [_pushedAlerts.last];
    }
    return [
      ..._pushedAlerts.reversed,
      {
        'id': 'alert-demo',
        'kind': 'cash_difference',
        'title': 'Diferencia en cierre de caja',
        'body': 'Revisa el arqueo del turno de la tarde.',
        'severity': 'bad',
        'created_at': '${todayIso()}T16:00:00',
        'read_at': fixtureAlertRead ? todayIso() : null,
      },
    ];
  }
  if (path == 'products') {
    if (emptyRetailCatalog) return [];
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
      for (final sale in _sales)
        {
          'id': 'invoice-${sale.quantity}',
          'number': 'DEMO-${sale.quantity}',
          'issue_date': sale.date,
          'status': 'sent',
          'currency': 'PEN',
          'tax_rate': 0,
          'clients': {'name': 'Mercado Oliva'},
          'invoice_items': [
            {
              'description': 'Pan artesanal',
              'quantity': sale.quantity,
              'unit_price': _salePrice,
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
  if (path == 'sales_summary' || path == 'sales_series') {
    final params = jsonDecode(request.body) as Map<String, dynamic>;
    final from = params['p_from'] as String;
    final until = params['p_to'] as String;
    final sales = _sales.where((sale) => params['p_currency'] == 'PEN' &&
        sale.date.compareTo(from) >= 0 && sale.date.compareTo(until) < 0);
    if (path == 'sales_summary') return _summary(sales);
    return [
      for (final sale in sales)
        {'bucket': sale.date, 'total': sale.quantity * _salePrice},
    ];
  }
  if (path == 'day_summary') {
    final params = jsonDecode(request.body) as Map<String, dynamic>;
    final sales = _summary(_sales.where((sale) => sale.date == params['p_day']));
    final collected = sales['sales_total']!;
    return {
      'sales': sales,
      'cash_opening': 100,
      'expected_cash': 100 + collected,
      'cash_sales': collected,
      'payments_by_method': {'efectivo': collected},
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

Future<void> startOfflineRetailBackend({DateTime? salesDate}) async {
  final date = salesDate ?? DateTime.now();
  final today = DateTime.utc(date.year, date.month, date.day);
  _sales = [
    for (final quantity in const [1, 4, 7, 10])
      (quantity: quantity, date: todayIso(today.subtract(Duration(days: 10 - quantity)))),
  ];
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
        for (final entry in featureCatalog())
          if (entry.feature != null) entry.feature!: true,
      },
    );
  LiveHub.instance.start();
}

Future<void> stopRetailFixture() async {
  LiveHub.instance.stop();
  await Supabase.instance.dispose();
}
