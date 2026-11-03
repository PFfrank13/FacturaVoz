// Acceso del usuario en la empresa activa: ROL (dueño, administrador, finanzas, cajero, técnico, vendedor) y
// LICENCIA de Solvex Hub (modo, plan y funciones contratadas). Una sola función central para toda la app:
//   Access.instance.has('tienda')   → ¿el plan incluye la tienda?       (oculta lo que no se contrató)
//   Access.instance.can('finance')  → ¿este rol puede ver dinero?        (oculta lo que el rol no permite)
// Ojo: esto solo ORDENA la pantalla. Los permisos reales se aplican en la base de datos (RLS y disparadores).
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'rubros.dart';
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
  });

  final String mode; // full | warning | restricted | blocked
  final String plan; // BASICO | PRO | EMPRESA
  final String status;
  final String source; // local | hub | dev
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
      );
}

/// Funciones básicas que todo plan incluye.
const coreFeatures = {'facturar', 'clientes', 'cobros', 'voz'};

/// ¿El plan incluye [key]? Puro (se prueba con flutter test). El núcleo del rubro va en todos los planes
/// (igual que private.has_feature + private.rubro_core en la base).
/// El Hub define las funciones de cada plan. Nunca confiamos en un plan
/// predeterminado ni en el caché para desbloquear funciones.
bool planHas(LicenseInfo l, String key, {String? rubro}) {
  if (!l.enforced || l.dev || l.source != 'hub' || !l.usable) return false;
  final v = l.features[key];
  return v == true || (v is num && v != 0);
}

/// Límite numérico del plan (-1 = sin límite).
int planLimit(LicenseInfo l, String key) {
  if (!l.enforced || l.source != 'hub' || !l.usable) return 0;
  final v = l.features[key];
  return v is num ? v.toInt() : 0;
}

class Access extends ChangeNotifier {
  Access._();
  static final Access instance = Access._();

  String role = 'owner'; // owner | admin | finanzas | cajero | tecnico | vendedor
  bool isAdmin = true;
  String displayName = '';
  bool welcomed = true;
  Map<String, bool> _can = const {};
  LicenseInfo license = const LicenseInfo();
  bool loaded = false;
  /// No se entra con una licencia cacheada sin validar la sesión ante Supabase.
  bool licenseCheckedOnline = false;
  bool licenseChecking = true;
  bool get licenseReady => licenseCheckedOnline && license.enforced && !license.dev &&
      license.source == 'hub' && license.usable;
  bool get canEnter => licenseReady || (licenseCheckedOnline && license.enforced &&
      !license.dev && license.source == 'hub' && license.mode == 'restricted' && isAdmin);


  bool can(String what) => _can[what] ?? isAdmin;
  /// Rubro de la empresa activa (lo fija la estructura principal al leer los ajustes).
  String? rubro;

  bool has(String feature) => planHas(license, feature, rubro: rubro);
  int limit(String feature) => planLimit(license, feature);

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
    licenseCheckedOnline = false;
    licenseChecking = true;
    final org = Repo.activeOrgId;
    if (org == null) {
      licenseChecking = false;
      loaded = true;
      notifyListeners();
      return;
    }
    // Permisos y licencia no dependen entre sí: se piden a la vez (una espera de red en vez de dos).
    await Future.wait([_loadAccess(org), _loadLicense(org)]);
    licenseChecking = false;
    loaded = true;
    notifyListeners();
  }

  /// Últimas respuestas crudas de la base (para el arranque instantáneo).
  Map<String, dynamic>? rawAccess, rawLicense;

  void _applyAccess(Map<String, dynamic> m) {
    rawAccess = m;
    role = (m['role'] ?? 'owner') as String;
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

  Future<void> _loadAccess(String org) async {
    try {
      final a = await _db.rpc('my_access', params: {'p_org': org});
      if (a is Map) _applyAccess(Map<String, dynamic>.from(a));
    } catch (_) {
      role = 'member';
      isAdmin = false;
      welcomed = true;
      _can = const {};
    }
  }

  Future<void> _loadLicense(String org) async {
    try {
      final l = await _db.rpc('my_license', params: {'p_org': org});
      if (l is Map) {
        _applyLicense(Map<String, dynamic>.from(l));
        licenseCheckedOnline = true;
      } else {
        license = const LicenseInfo();
        rawLicense = null;
      }
    } catch (_) {
      // Fallar cerrado: no se permite operar con una licencia inventada.
      licenseCheckedOnline = false;
      license = const LicenseInfo();
      rawLicense = null;
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
    role = 'owner';
    isAdmin = true;
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
