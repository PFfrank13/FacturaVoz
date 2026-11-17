// Acceso del usuario en la empresa activa: ROL (dueño, administrador, finanzas, cajero, técnico, vendedor) y
// LICENCIA de Solvex Hub (modo, plan y funciones contratadas). Una sola función central para toda la app:
//   Access.instance.has('tienda')   → ¿el plan incluye la tienda?       (oculta lo que no se contrató)
//   Access.instance.can('finance')  → ¿este rol puede ver dinero?        (oculta lo que el rol no permite)
// Ojo: esto solo ORDENA la pantalla. Los permisos reales se aplican en la base de datos (RLS y disparadores).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/repo.dart';

/// Estado de la licencia tal como lo devuelve my_license().
class LicenseInfo {
  const LicenseInfo({
    this.mode = 'blocked',
    this.plan = 'BASICO',
    this.status = 'pendiente',
    this.source = 'none',
    this.dev = false,
    this.enforced = true,
    this.features = const {},
    this.message = '',
    this.payUrl = '',
    this.periodEnd,
    this.cutAt,
    this.isTrial = false,
    this.trialRequested = false,
    this.stale = false,
    this.activated = false,
    this.reconciling = false,
  });

  final String mode; // full | warning | restricted | blocked
  final String plan; // BASICO | PRO | EMPRESA
  final String status;
  final String source; // 'hub' (y 'local' solo hasta la FASE B de v3.4); none = no se pudo leer
  final bool dev;
  final bool enforced;
  final Map<String, dynamic> features;
  final String message;
  final String payUrl;
  final DateTime? periodEnd;
  final DateTime? cutAt;
  final bool isTrial;
  final bool trialRequested;
  final bool stale;

  /// La empresa activó el código de licencia del Hub (requisito de la base para operar).
  final bool activated;

  /// Venía del modo local heredado y espera que el backend verifique su licencia con el Hub.
  final bool reconciling;

  bool get usable => mode == 'full' || mode == 'warning';

  /// Días que quedan de prueba o de periodo pagado (null si no aplica).
  int? daysLeft([DateTime? now]) {
    final end = periodEnd;
    if (end == null) return null;
    final d = end.difference(now ?? DateTime.now()).inHours;
    return d < 0 ? 0 : (d / 24).ceil();
  }

  static DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

  factory LicenseInfo.fromJson(Map<String, dynamic> j) => LicenseInfo(
        mode: (j['mode'] ?? 'blocked') as String,
        plan: (j['plan'] ?? 'BASICO') as String,
        status: (j['status'] ?? '') as String,
        source: (j['source'] ?? 'none') as String,
        dev: j['dev'] == true,
        enforced: j['enforced'] == true,
        features: j['features'] is Map ? Map<String, dynamic>.from(j['features'] as Map) : const {},
        message: (j['message'] ?? '') as String,
        payUrl: (j['pay_url'] ?? '') as String,
        periodEnd: _date(j['period_end']),
        cutAt: _date(j['cut_at']),
        isTrial: j['is_trial'] == true,
        trialRequested: j['trial_requested'] == true,
        stale: j['stale'] == true,
        activated: j['activated'] == true,
        reconciling: j['reconciling'] == true,
      );
}

/// Fuente comercial aceptada: el Hub y, solo durante la transición v3.4, la licencia local heredada (la FASE B la elimina).
bool _commercialSource(String s) => s == 'hub' || s == 'local';

/// Funciones básicas que todo plan incluye.
const coreFeatures = {'facturar', 'clientes', 'cobros', 'voz'};

/// The backend computes effective per-tenant features from the Solvex Hub license.
/// Never accept an unverified cached or expired license as authorization.
bool planHas(LicenseInfo l, String key, {String? rubro}) {
  if (!l.enforced || l.dev || l.stale || !_commercialSource(l.source) || !l.usable) return false;
  return l.features[key] == true;
}

/// Límite numérico del plan (-1 = sin límite).
int planLimit(LicenseInfo l, String key) {
  if (!l.enforced || l.dev || l.stale || !_commercialSource(l.source) || !l.usable) return 0;
  final v = l.features[key];
  return v is num && v.isFinite && v == v.truncateToDouble() && v >= -1 ? v.toInt() : 0;
}

class Access extends ChangeNotifier {
  Access._();
  static final Access instance = Access._();

  String role = 'member'; // owner | admin | finanzas | cajero | tecnico | vendedor
  bool isAdmin = false;
  String displayName = '';
  bool welcomed = true;
  Map<String, bool> _can = const {};
  LicenseInfo license = const LicenseInfo();
  bool loaded = false;
  /// No se entra con una licencia cacheada sin validar la sesión ante Supabase.
  bool licenseCheckedOnline = false;
  bool licenseChecking = true;
  // v3.4: Solvex Hub es la única fuente comercial. 'local' solo existe hasta la FASE B (20261210), que la base
  // garantiza que no deja ninguna; aceptarla mientras tanto evita cortar el servicio durante la transición.
  bool get licenseReady => licenseCheckedOnline && license.enforced && !license.dev &&
      !license.stale && _commercialSource(license.source) && license.usable;
  bool get canEnter => licenseReady || (licenseCheckedOnline && license.enforced &&
      !license.dev && _commercialSource(license.source) && license.mode == 'restricted' && isAdmin);

  /// Por qué no se pudo leer la licencia (null = se leyó). Se muestra tal cual; nunca da acceso.
  String? licenseError;


  bool can(String what) => _can[what] ?? isAdmin;
  /// Rubro de la empresa activa (lo fija la estructura principal al leer los ajustes).
  String? rubro;

  bool has(String feature) => licenseReady && planHas(license, feature, rubro: rubro);
  int limit(String feature) => licenseReady ? planLimit(license, feature) : 0;
  int _generation = 0;

  String get roleLabel => roleName(role);

  static String roleName(String r) => switch (r) {
        'owner' => 'Propietario',
        'admin' => 'Administrador',
        'finanzas' => 'Finanzas',
        'cajero' => 'Cajero',
        'tecnico' => 'Técnico',
        'vendedor' => 'Vendedor',
        _ => 'Integrante',
      };

  static SupabaseClient get _db => Supabase.instance.client;

  /// Carga rol y licencia de la empresa activa. Si Supabase no responde, nunca habilita módulos por defecto.
  void invalidateLicenseCheck() {
    licenseCheckedOnline = false;
    licenseChecking = true;
    notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_generation;
    licenseCheckedOnline = false;
    licenseChecking = true;
    isAdmin = false;
    role = 'member';
    _can = const {};
    license = const LicenseInfo();
    rawAccess = null;
    rawLicense = null;
    notifyListeners();
    final org = Repo.activeOrgId;
    if (org == null) {
      licenseChecking = false;
      loaded = true;
      notifyListeners();
      return;
    }
    // Permisos y licencia no dependen entre sí: se piden a la vez (una espera de red en vez de dos).
    await Future.wait([_loadAccess(org, generation), _loadLicense(org, generation)]);
    if (generation != _generation || org != Repo.activeOrgId) return;
    licenseChecking = false;
    loaded = true;
    notifyListeners();
    // Al tener sesión y licencia: comprobar los cobros/abonos/movimientos que quedaron pendientes de confirmar.
    if (licenseReady) unawaited(Repo.resolvePendingFinancial().catchError((_) => 0));
  }

  /// Últimas respuestas crudas de la base (para el arranque instantáneo).
  Map<String, dynamic>? rawAccess, rawLicense;

  void _applyAccess(Map<String, dynamic> m) {
    rawAccess = m;
    role = (m['role'] ?? 'member') as String;
    isAdmin = m['is_admin'] == true;
    displayName = (m['display_name'] ?? '') as String;
    welcomed = m['welcomed'] == true || isAdmin;
    _can = m['can'] is Map ? Map<String, dynamic>.from(m['can'] as Map).map((k, v) => MapEntry(k, v == true)) : const {};
  }

  void _applyLicense(Map<String, dynamic> m) {
    rawLicense = m;
    license = LicenseInfo.fromJson(m);
  }

  /// Arranque instantáneo: usa lo último guardado mientras la red confirma.
  void applyCached(Map<String, dynamic>? access, Map<String, dynamic>? lic) {
    if (access != null) _applyAccess(access);
    if (lic != null) _applyLicense(lic);
    licenseCheckedOnline = false;
    licenseChecking = true;
    loaded = true;
    notifyListeners();
  }

  Future<void> _loadAccess(String org, int generation) async {
    try {
      final a = await _db.rpc('my_access', params: {'p_org': org});
      if (generation != _generation || org != Repo.activeOrgId) return;
      if (a is Map) _applyAccess(Map<String, dynamic>.from(a));
    } catch (_) {
      if (generation != _generation || org != Repo.activeOrgId) return;
      role = 'member';
      isAdmin = false;
      welcomed = true;
      _can = const {};
    }
  }

  Future<void> _loadLicense(String org, int generation) async {
    try {
      final l = await _db.rpc('my_license', params: {'p_org': org});
      if (generation != _generation || org != Repo.activeOrgId) return;
      if (l is Map) {
        _applyLicense(Map<String, dynamic>.from(l));
        licenseCheckedOnline = true;
        licenseError = null;
      } else {
        license = const LicenseInfo();
        rawLicense = null;
        licenseError = 'El servidor no devolvió la licencia.';
      }
    } catch (e) {
      if (generation != _generation || org != Repo.activeOrgId) return;
      // Fallar cerrado: no se permite operar con una licencia inventada, pero se dice POR QUÉ.
      licenseCheckedOnline = false;
      license = const LicenseInfo();
      rawLicense = null;
      licenseError = switch (e) {
        PostgrestException(code: '42501') => 'Tu usuario no pertenece a esta empresa.',
        PostgrestException(code: 'PGRST202') => 'El servidor no tiene la función de licencias actualizada.',
        PostgrestException(:final message) => 'Error del servidor al leer la licencia: $message',
        AuthException() => 'Tu sesión expiró. Vuelve a iniciar sesión.',
        _ => 'No hay conexión con el servidor. Revisa tu internet.',
      };
    }
  }

  Future<void> markWelcomed() async {
    welcomed = true;
    notifyListeners();
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      await _db.rpc('mark_welcomed', params: {'p_org': org});
    } catch (_) {}
  }

  void clear() {
    _generation++;
    role = 'member';
    isAdmin = false;
    welcomed = true;
    _can = const {};
    license = const LicenseInfo();
    rawAccess = null;
    rawLicense = null;
    loaded = false;
    licenseCheckedOnline = false;
    licenseChecking = true;
    notifyListeners();
  }
}
