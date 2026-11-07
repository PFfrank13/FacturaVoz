// Tiempo real y datos al instante.
//
// LiveHub: escucha los cambios de la empresa activa en la base (Supabase Realtime) y avisa a las pantallas.
//   - Un canal por tabla: si una tabla aún no está publicada (migración sin aplicar), solo esa deja de avisar.
//   - Varios cambios seguidos (p. ej. importar 500 filas) se juntan en un solo aviso (250 ms).
// LiveCache: guarda en memoria lo último que cada pantalla cargó (por empresa), para mostrarlo YA al volver
//   y refrescarlo detrás. Se borra al cambiar de empresa y al cerrar sesión; nunca se guarda en disco.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import 'repo.dart';
import 'v2_repo.dart';

class LiveHub {
  LiveHub._();
  static final LiveHub instance = LiveHub._();

  /// Tablas que las pantallas pueden escuchar.
  static const tables = [
    'invoices',
    'payments',
    'clients',
    'products',
    'retail_receipts',
    'retail_suppliers',
    'retail_stock_ledger',
    'expenses',
    'quotes',
    'jobs',
    'cash_movements',
    'credit_ledger',
    'service_reminders',
    'agent_tasks',
    'recurring_invoices',
    'payment_notices',
    'payment_claims',
    'owner_alerts',
    'organization_members',
    'org_invites',
    'org_settings',
    'trash',
    'surveys',
    'promotions',
    'coupons',
    'loyalty_ledger',
  ];

  final Map<String, ValueNotifier<int>> _ticks = {};
  final Map<String, Timer> _timers = {};
  final List<RealtimeChannel> _channels = [];
  String? _org;

  ValueNotifier<int> tick(String table) => _ticks.putIfAbsent(table, () => ValueNotifier<int>(0));

  /// Se dispara cuando cambia CUALQUIERA de las tablas indicadas (más `AppState.dataVersion`: cambios hechos en esta app).
  Listenable of(List<String> names) => Listenable.merge([for (final n in names) tick(n), AppState.instance.dataVersion]);

  /// Empieza a escuchar la empresa activa (si ya escucha esa, no hace nada).
  void start() {
    final org = Repo.activeOrgId;
    if (org == null || (org == _org && _channels.isNotEmpty)) return;
    stop();
    _org = org;
    for (final t in tables) {
      try {
        final ch = Supabase.instance.client
            .channel('live-$t-$org')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: t,
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: org),
              callback: (_) => _bump(t),
            )
            .subscribe((status, error) {
              if (_org == org && status == RealtimeSubscribeStatus.subscribed) _bump(t);
            });
        _channels.add(ch);
      } catch (_) {}
    }
  }

  void stop() {
    for (final c in _channels) {
      try {
        c.unsubscribe();
      } catch (_) {}
    }
    _channels.clear();
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _org = null;
  }

  void _bump(String table) {
    _timers[table]?.cancel();
    _timers[table] = Timer(const Duration(milliseconds: 250), () => tick(table).value++);
  }
}

class LiveCache {
  LiveCache._();

  /// Precarga en segundo plano lo que más se abre (clientes, productos, fiados, trabajos) apenas inicia sesión,
  /// para que esas pantallas aparezcan YA la primera vez. Si algo falla o el rol no tiene permiso, se ignora.
  static Future<void> warmUp() async {
    final org = Repo.activeOrgId;
    if (org == null) return;
    Future<void> w(String key, Future<Object?> Function() f) async {
      try {
        final v = await f();
        if (org == Repo.activeOrgId) put(key, v);
      } catch (_) {}
    }

    await Future.wait([
      w('clients.all', Repo.listClients),
      w('products.all', Repo.listProducts),
      w('fiados.list', V2Repo.creditBalances),
      w('jobs.open', () => V2Repo.jobs(openOnly: true)),
    ]);
  }
  static final Map<String, Object?> _m = {};

  static String _k(String k) => '${Repo.activeOrgId}|$k';

  static T? get<T>(String key) {
    final v = _m[_k(key)];
    return v is T ? v : null;
  }

  static void put(String key, Object? value) {
    if (value == null) {
      _m.remove(_k(key));
    } else {
      _m[_k(key)] = value;
    }
  }

  static void clear() => _m.clear();
}

/// Para pantallas con estado: se recargan solas cuando cambian sus tablas (tiempo real) o cuando esta app guarda algo.
///   - `liveTables`: tablas a escuchar. `reloadLive()`: tu función de carga. Llama `startLive()` en initState y `stopLive()` en dispose.
mixin LiveReload<T extends StatefulWidget> on State<T> {
  List<String> get liveTables;
  Future<void> reloadLive();

  Listenable? _liveSource;
  AppLifecycleListener? _lifecycle;
  Timer? _fallback;
  bool _reloading = false;
  bool _reloadAgain = false;

  void startLive() {
    stopLive();
    LiveHub.instance.start();
    _liveSource = LiveHub.instance.of(liveTables)..addListener(_onLive);
    _lifecycle = AppLifecycleListener(onResume: _onLive);
    // Re-read authoritative queries even when replication is unavailable.
    _fallback = Timer.periodic(const Duration(seconds: 30), (_) => _onLive());
  }

  void stopLive() {
    _liveSource?.removeListener(_onLive);
    _liveSource = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _fallback?.cancel();
    _fallback = null;
    _reloadAgain = false;
  }

  Future<void> _onLive() async {
    if (!mounted || _liveSource == null) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (_reloading) { _reloadAgain = true; return; }
    _reloading = true;
    try {
      do {
        _reloadAgain = false;
        await reloadLive();
      } while (_reloadAgain && mounted && _liveSource != null);
    } catch (_) {
      // Screens own their error presentation. The next resume/poll retries reads.
    } finally { _reloading = false; }
  }
}
