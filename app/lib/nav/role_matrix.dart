// Matriz rubro × plan × rol (Prompt Maestro §10). UN motor compartido, no 27 apps:
//   rol de rubro (presentación)  →  rol base real (permisos de la base)  →  permisos granulares  →  plan contratado
// Da, para cada combinación: Inicio, navegación, operaciones permitidas/restringidas, aprobaciones y rutas.
//
// Roles de rubro (mesero, barbero, mecánico…) NO existen todavía en la base: cada uno se apoya en un rol base
// existente (owner/admin/finanzas/cajero/vendedor/tecnico). Si el rol base no cubre exactamente lo que el rubro
// pide, [RubroRole.exact] es false y la diferencia queda escrita en [RubroRole.gap] (migración propuesta, no aplicada).
import '../permissions.dart';
import '../rubros.dart';
import 'navigation_contract.dart';

class RubroRole {
  const RubroRole(this.id, this.label, this.base, {required this.home, this.approvals = const [], this.exact = true, this.gap = ''});

  final String id;
  final String label;

  /// Rol base real: owner | admin | finanzas | cajero | vendedor | tecnico.
  final String base;

  /// Bloques de Inicio en orden (ids de [homeBlocks]).
  final List<String> home;

  /// Permisos que este rol APRUEBA para otros (anulaciones, compras, ajustes).
  final List<String> approvals;
  final bool exact;
  final String gap;
}

/// Bloque de Inicio: qué muestra y qué permiso/función exige. Sin permiso, el bloque no existe para ese usuario.
class HomeBlock {
  const HomeBlock(this.id, this.label, this.permission, {this.feature, this.route});
  final String id;
  final String label;
  final String permission;
  final String? feature;

  /// Función del catálogo a la que lleva (ruta canónica). null = solo informa.
  final String? route;
}

const homeBlocks = <String, HomeBlock>{
  'sell_cta': HomeBlock('sell_cta', 'Botón VENDER', 'sales.create', feature: 'facturar', route: 'pos'),
  'cash_status': HomeBlock('cash_status', 'Estado de mi caja', 'cash.close', feature: 'caja', route: 'caja'),
  'today_sales': HomeBlock('today_sales', 'Ventas de hoy', 'sales.read', feature: 'facturar', route: 'comprobantes'),
  'last_ops': HomeBlock('last_ops', 'Comprobantes y últimas ventas', 'sales.read', feature: 'facturar', route: 'comprobantes'),
  'stock_low': HomeBlock('stock_low', 'Stock bajo', 'products.read', feature: 'stock', route: 'productos'),
  'fiados_total': HomeBlock('fiados_total', 'Fiados por cobrar', 'payments.record', feature: 'fiados', route: 'fiados'),
  'margin': HomeBlock('margin', 'Margen y ganancia', 'reports.profit', feature: 'reportes', route: 'negocio'),
  'purchases': HomeBlock('purchases', 'Compras y recepción', 'purchases.create', feature: 'stock', route: 'compras'),
  'team': HomeBlock('team', 'Equipo', 'team.manage', route: 'equipo'),
  'reports': HomeBlock('reports', 'Reportes', 'reports.view', feature: 'reportes', route: 'reportes'),
  'my_jobs': HomeBlock('my_jobs', 'Mis órdenes / trabajos', 'jobs.create', feature: 'trabajos', route: 'trabajos'),
  'all_jobs': HomeBlock('all_jobs', 'Órdenes de todo el equipo', 'jobs.read_all', feature: 'trabajos', route: 'trabajos'),
  'agenda_today': HomeBlock('agenda_today', 'Agenda de hoy', 'jobs.create', feature: 'agenda', route: 'agenda'),
  'tables': HomeBlock('tables', 'Mesas y comandas', 'sales.create', feature: 'carta_qr', route: 'carta'),
  'collect_due': HomeBlock('collect_due', 'Por cobrar', 'payments.record', feature: 'cobros', route: 'cobranza'),
  'orders': HomeBlock('orders', 'Pedidos y cotizaciones', 'sales.create', feature: 'cotizaciones', route: 'cotizaciones'),
  'pensions_due': HomeBlock('pensions_due', 'Pensiones pendientes', 'payments.record', feature: 'recurrentes', route: 'morosidad'),
  'works_margin': HomeBlock('works_margin', 'Margen por obra', 'reports.profit', feature: 'trabajos', route: 'margen_obra'),
  'my_commissions': HomeBlock('my_commissions', 'Mis ventas y comisiones', 'sales.create', feature: 'comisiones', route: 'comisiones'),
  'clients': HomeBlock('clients', 'Clientes', 'customers.manage', feature: 'clientes', route: 'clientes'),
};

// Roles comunes a todos los rubros.
const _owner = RubroRole('propietario', 'Propietario', 'owner',
    home: ['sell_cta', 'today_sales', 'cash_status', 'fiados_total', 'stock_low', 'last_ops', 'margin', 'purchases', 'collect_due', 'all_jobs', 'agenda_today', 'orders', 'pensions_due', 'works_margin', 'team', 'reports'],
    approvals: ['sales.cancel', 'payments.refund', 'purchases.approve', 'inventory.adjust', 'team.manage', 'subscription.manage']);
const _admin = RubroRole('administrador', 'Administrador', 'admin',
    home: ['sell_cta', 'today_sales', 'cash_status', 'fiados_total', 'stock_low', 'last_ops', 'margin', 'purchases', 'collect_due', 'all_jobs', 'agenda_today', 'orders', 'pensions_due', 'works_margin', 'team', 'reports'],
    approvals: ['sales.cancel', 'payments.refund', 'purchases.approve', 'inventory.adjust']);
const _finanzas = RubroRole('finanzas', 'Finanzas / contabilidad', 'finanzas',
    home: ['today_sales', 'margin', 'collect_due', 'fiados_total', 'cash_status', 'pensions_due', 'works_margin', 'reports'],
    approvals: ['sales.cancel', 'payments.refund']);

/// Roles por rubro (los comunes van primero en [rolesFor]).
const rubroRoles = <String, List<RubroRole>>{
  'bodega': [
    RubroRole('cajero', 'Cajero', 'cajero', home: ['sell_cta', 'cash_status', 'last_ops', 'stock_low']),
    RubroRole('vendedor', 'Vendedor', 'vendedor', home: ['sell_cta', 'last_ops', 'my_commissions', 'stock_low']),
    RubroRole('almacenero', 'Almacenero', 'cajero', home: ['stock_low', 'purchases'], exact: false,
        gap: 'Debe ajustar stock y recibir compras sin vender ni ver caja. Hoy no hay rol base así: usa Cajero y el ajuste lo aprueba el dueño.'),
    RubroRole('compras', 'Encargado de compras', 'cajero', home: ['purchases', 'stock_low'], exact: false,
        gap: 'La recepción de compras exige administrador en la base; falta un permiso purchases.create sin administración.'),
  ],
  'restaurante': [
    RubroRole('mesero', 'Mesero', 'vendedor', home: ['tables', 'sell_cta', 'my_commissions']),
    RubroRole('cocinero', 'Cocinero', 'vendedor', home: ['tables'], exact: false,
        gap: 'Solo debe ver comandas (pendiente → listo). Con Vendedor también puede vender; falta un rol de cocina.'),
    RubroRole('jefe_cocina', 'Encargado de cocina', 'vendedor', home: ['tables', 'stock_low'], exact: false, gap: 'Igual que cocinero + inventario de insumos.'),
    RubroRole('cajero', 'Cajero', 'cajero', home: ['sell_cta', 'cash_status', 'last_ops']),
    RubroRole('encargado_salon', 'Encargado de salón', 'vendedor', home: ['tables', 'sell_cta', 'last_ops']),
  ],
  'servicios_tecnicos': [
    RubroRole('tecnico', 'Técnico', 'tecnico', home: ['my_jobs', 'agenda_today']),
    RubroRole('instalador', 'Instalador', 'tecnico', home: ['my_jobs', 'agenda_today']),
    RubroRole('supervisor', 'Supervisor', 'vendedor', home: ['all_jobs', 'agenda_today', 'clients'], exact: false,
        gap: 'Debe ver todas las órdenes sin cobrar; Vendedor también vende y cobra.'),
    RubroRole('cobranza', 'Encargado de cobranza', 'cajero', home: ['collect_due', 'cash_status', 'clients']),
  ],
  'salon': [
    RubroRole('barbero', 'Barbero', 'tecnico', home: ['agenda_today', 'my_jobs']),
    RubroRole('estilista', 'Estilista', 'tecnico', home: ['agenda_today', 'my_jobs']),
    RubroRole('recepcion', 'Recepcionista', 'cajero', home: ['agenda_today', 'sell_cta', 'cash_status', 'clients']),
    RubroRole('agenda', 'Encargado de agenda', 'vendedor', home: ['agenda_today', 'clients']),
  ],
  'consultorio': [
    RubroRole('profesional', 'Profesional de salud', 'tecnico', home: ['agenda_today', 'my_jobs'], exact: false,
        gap: 'Debe ver el historial clínico de SUS pacientes; hoy las notas privadas son por autor. Lo administrativo queda fuera.'),
    RubroRole('recepcion', 'Recepcionista', 'cajero', home: ['agenda_today', 'sell_cta', 'cash_status', 'clients']),
    RubroRole('asistente', 'Asistente administrativo', 'finanzas', home: ['today_sales', 'collect_due', 'reports']),
  ],
  'taller': [
    RubroRole('asesor', 'Asesor de servicio', 'vendedor', home: ['all_jobs', 'orders', 'clients']),
    RubroRole('mecanico', 'Mecánico', 'tecnico', home: ['my_jobs']),
    RubroRole('jefe_taller', 'Jefe de taller', 'vendedor', home: ['all_jobs', 'stock_low'], exact: false, gap: 'Supervisa órdenes y repuestos sin cobrar.'),
    RubroRole('almacenero', 'Almacenero (repuestos)', 'cajero', home: ['stock_low', 'purchases'], exact: false, gap: 'Igual que el almacenero de bodega.'),
    RubroRole('cajero', 'Cajero', 'cajero', home: ['sell_cta', 'cash_status', 'collect_due']),
  ],
  'mayorista': [
    RubroRole('vendedor', 'Vendedor de campo', 'vendedor', home: ['orders', 'clients', 'my_commissions']),
    RubroRole('almacenero', 'Almacenero', 'cajero', home: ['stock_low', 'purchases'], exact: false, gap: 'Igual que el almacenero de bodega.'),
    RubroRole('despachador', 'Despachador', 'tecnico', home: ['my_jobs'], exact: false, gap: 'Debe ver pedidos por despachar; hoy se modela como trabajo asignado.'),
    RubroRole('cobrador', 'Cobrador', 'cajero', home: ['collect_due', 'clients']),
  ],
  'educacion': [
    RubroRole('coordinador', 'Coordinador académico', 'vendedor', home: ['agenda_today', 'clients'], exact: false,
        gap: 'Académico sin cobrar. Vendedor también puede cobrar.'),
    RubroRole('docente', 'Docente', 'tecnico', home: ['agenda_today'], exact: false,
        gap: 'Solo sus grupos y horarios. Datos de menores: acceso por grupo asignado (falta en la base).'),
    RubroRole('recepcion', 'Recepcionista', 'cajero', home: ['pensions_due', 'agenda_today', 'clients']),
    RubroRole('administrativo', 'Administrativo', 'finanzas', home: ['pensions_due', 'collect_due', 'reports']),
    RubroRole('cajero', 'Cajero', 'cajero', home: ['pensions_due', 'cash_status']),
  ],
  'construccion': [
    RubroRole('jefe_obra', 'Jefe de obra', 'vendedor', home: ['all_jobs', 'clients'], exact: false, gap: 'Ve sus obras y avances sin cobrar.'),
    RubroRole('supervisor', 'Supervisor', 'tecnico', home: ['my_jobs']),
    RubroRole('operario', 'Operario', 'tecnico', home: ['my_jobs']),
    RubroRole('compras', 'Responsable de compras', 'cajero', home: ['purchases'], exact: false, gap: 'Igual que el encargado de compras de bodega.'),
  ],
};

List<RubroRole> rolesFor(String rubro) => [_owner, _admin, _finanzas, ...?rubroRoles[rubro]];

/// Resultado para una combinación rubro × plan × rol.
class RoleExperience {
  const RoleExperience({required this.nav, required this.home, required this.allowed, required this.restricted, required this.approvals});
  final List<String> nav;
  final List<String> home;
  final List<String> allowed;
  final List<String> restricted;
  final List<String> approvals;
}

/// Motor: lo mismo para la app real (allows = Access.allows, has = Access.has) y para la simulación/documentación.
RoleExperience roleExperience({required String rubro, required RubroRole role, required bool Function(String perm) allows, required bool Function(String feature) has}) {
  bool block(String id) {
    final b = homeBlocks[id];
    return b != null && allows(b.permission) && (b.feature == null || has(b.feature!));
  }

  final spec = rubroFor(rubro);
  final nav = <String>[
    for (final d in spec?.nav ?? const <RubroNav>[])
      if (navContracts[d.id] case final c?)
        if ((c.permission == null || allows(c.permission!)) && (c.feature == null || has(c.feature!))) d.id,
  ];
  final allowed = [for (final k in permissionRules.keys) if (allows(k)) k];
  return RoleExperience(
    nav: nav,
    home: [for (final id in role.home) if (block(id)) id],
    allowed: allowed,
    restricted: [for (final k in permissionRules.keys) if (!allowed.contains(k)) k],
    approvals: [for (final a in role.approvals) if (allowed.contains(a)) a],
  );
}

/// Simulación sin Supabase: rol base + plan del rubro (planMatrix). Para pruebas y para la matriz documentada.
RoleExperience simulateExperience(String rubro, String plan, RubroRole role) {
  final can = baseCan(role.base);
  final features = planMatrix(rubro, plan) ?? const <String>{};
  bool has(String f) => features.contains(f);
  return roleExperience(
    rubro: rubro,
    role: role,
    has: has,
    allows: (p) => permits(p, role: role.base, isAdmin: role.base == 'owner' || role.base == 'admin', can: (k) => can[k] ?? false, has: has),
  );
}

/// Rol de rubro más cercano para el usuario actual (hasta que exista rubro_role en la base).
RubroRole roleForUser(String? rubro, String baseRole) {
  if (baseRole == 'owner') return _owner;
  if (baseRole == 'admin') return _admin;
  if (baseRole == 'finanzas') return _finanzas;
  for (final r in rubroRoles[rubro] ?? const <RubroRole>[]) {
    if (r.base == baseRole && r.exact) return r;
  }
  for (final r in rubroRoles[rubro] ?? const <RubroRole>[]) {
    if (r.base == baseRole) return r;
  }
  // Sin preset: Inicio mínimo y seguro para el rol base.
  return RubroRole('base_$baseRole', baseRole, baseRole, home: const ['sell_cta', 'cash_status', 'my_jobs', 'agenda_today']);
}
