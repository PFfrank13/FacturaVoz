// Acceso del usuario en la empresa activa: ROL (dueño, administrador, finanzas, cajero, técnico, vendedor) y
// LICENCIA de Solvex Hub (modo, plan y funciones contratadas). Una sola función central para toda la app:
//   Access.instance.has('tienda')   → ¿el plan incluye la tienda?       (oculta lo que no se contrató)
//   Access.instance.can('finance')  → ¿este rol puede ver dinero?        (oculta lo que el rol no permite)
// Ojo: esto solo ORDENA la pantalla. Los permisos reales se aplican en la base de datos (RLS y disparadores).
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/repo.dart';

/// Estado de la licencia tal como lo devuelve my_license().
class LicenseInfo {
  const LicenseInfo({
    this.mode = 'full',
    this.plan = 'EMPRESA',
    this.status = 'prueba',
    this.source = 'dev',
    this.dev = true,
    this.enforced = false,
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
        mode: (j['mode'] ?? 'full') as String,
        plan: (j['plan'] ?? 'EMPRESA') as String,
        status: (j['status'] ?? '') as String,
        source: (j['source'] ?? 'dev') as String,
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

/// ¿El plan incluye [key]? Puro (se prueba con flutter test).
bool planHas(LicenseInfo l, String key) {
  if (!l.enforced || l.dev || l.source == 'local' || coreFeatures.contains(key)) return true;
  final v = l.features[key];
  if (v is bool) return v;
  if (v is num) return v != 0;
  return false;
}

/// Límite numérico del plan (-1 = sin límite).
int planLimit(LicenseInfo l, String key) {
  if (!l.enforced || l.source != 'hub') return -1;
  final v = l.features[key];
  return v is num ? v.toInt() : -1;
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

  bool can(String what) => _can[what] ?? isAdmin;
  bool has(String feature) => planHas(license, feature);
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

  /// Carga rol y licencia de la empresa activa. Si las migraciones v2 aún no corrieron, todo queda habilitado
  /// como antes (nada se rompe).
  Future<void> load() async {
    final org = Repo.activeOrgId;
    if (org == null) {
      loaded = true;
      notifyListeners();
      return;
    }
    try {
      final a = await _db.rpc('my_access', params: {'p_org': org});
      if (a is Map) {
        final m = Map<String, dynamic>.from(a);
        role = (m['role'] ?? 'owner') as String;
        isAdmin = m['is_admin'] == true;
        displayName = (m['display_name'] ?? '') as String;
        welcomed = m['welcomed'] == true || isAdmin;
        _can = m['can'] is Map ? Map<String, dynamic>.from(m['can'] as Map).map((k, v) => MapEntry(k, v == true)) : const {};
      }
    } catch (_) {
      role = 'owner';
      isAdmin = true;
      welcomed = true;
      _can = const {};
    }
    try {
      final l = await _db.rpc('my_license', params: {'p_org': org});
      if (l is Map) license = LicenseInfo.fromJson(Map<String, dynamic>.from(l));
    } catch (_) {
      license = const LicenseInfo();
    }
    loaded = true;
    notifyListeners();
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
    loaded = false;
    notifyListeners();
  }
}
