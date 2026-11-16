// Permisos granulares (Prompt Maestro §5). Traducen los ids de diseño (sales.create, cash.close…) a lo que la base
// realmente entrega hoy: my_access().can (finance, sell, collect, clients, jobs, all_jobs, products_edit, team,
// settings, license, import) + la licencia de Solvex Hub (has) + el rol de la membresía.
//
// Reglas:
//  * Denegar por defecto: un id desconocido NUNCA se permite (a diferencia de Access.can, que cae en isAdmin).
//  * Permiso efectivo = función contratada (has) + permiso del rol (can) + rol de la membresía (owner/admin).
//  * Esto solo ordena la pantalla. Lo que manda es la base: RLS, disparadores y set_member_role_impl
//    (un administrador no puede ascender a nadie a administrador ni tocar al propietario).
import 'access.dart';

class PermRule {
  const PermRule({required this.label, this.can = const [], this.feature, this.ownerOnly = false, this.adminOnly = false});

  /// Texto para la ficha del integrante ("Permisos efectivos").
  final String label;

  /// Claves de my_access().can; TODAS deben ser verdaderas.
  final List<String> can;

  /// Función del plan que debe estar contratada (null = ninguna).
  final String? feature;

  /// Solo el propietario (suscripción, propiedad de la empresa).
  final bool ownerOnly;

  /// Propietario o administrador.
  final bool adminOnly;
}

/// Catálogo único de permisos granulares → reglas reales.
const permissionRules = <String, PermRule>{
  'sales.create': PermRule(label: 'Registrar ventas', can: ['sell'], feature: 'facturar'),
  'sales.read': PermRule(label: 'Ver ventas y comprobantes', can: ['sell'], feature: 'facturar'),
  'sales.cancel': PermRule(label: 'Anular comprobantes', can: ['finance'], feature: 'facturar'),
  'sales.discount': PermRule(label: 'Aplicar descuentos y precios', can: ['products_edit'], feature: 'precios'),
  'payments.record': PermRule(label: 'Registrar cobros', can: ['collect'], feature: 'cobros'),
  'payments.refund': PermRule(label: 'Devolver o anular cobros', can: ['finance'], feature: 'cobros'),
  'cash.open': PermRule(label: 'Abrir caja', can: ['collect'], feature: 'caja'),
  'cash.close': PermRule(label: 'Cerrar caja (arqueo)', can: ['collect'], feature: 'caja'),
  'cash.read_all': PermRule(label: 'Ver todas las cajas', can: ['finance'], feature: 'caja'),
  'products.read': PermRule(label: 'Ver productos', can: ['sell']),
  'products.create': PermRule(label: 'Crear productos', can: ['products_edit'], feature: 'stock'),
  'products.update': PermRule(label: 'Editar productos y precios', can: ['products_edit'], feature: 'stock'),
  'inventory.adjust': PermRule(label: 'Ajustar inventario', can: ['products_edit'], feature: 'stock'),
  // La recepción de compras exige administrador en la base (ver FeatureEntry.roleOk de 'compras').
  'purchases.create': PermRule(label: 'Registrar compras', can: ['products_edit'], feature: 'stock', adminOnly: true),
  'purchases.approve': PermRule(label: 'Aprobar compras', can: ['products_edit'], feature: 'stock', adminOnly: true),
  'reports.view': PermRule(label: 'Ver reportes', can: ['finance'], feature: 'reportes'),
  'reports.profit': PermRule(label: 'Ver ganancia y márgenes', can: ['finance'], feature: 'reportes'),
  'customers.manage': PermRule(label: 'Gestionar clientes', can: ['clients'], feature: 'clientes'),
  'jobs.create': PermRule(label: 'Crear órdenes y citas', can: ['jobs']),
  'jobs.read_all': PermRule(label: 'Ver los trabajos de todos', can: ['all_jobs']),
  'team.manage': PermRule(label: 'Gestionar el equipo', can: ['team']),
  'settings.manage': PermRule(label: 'Configurar la empresa', can: ['settings']),
  'data.import': PermRule(label: 'Importar datos', can: ['import']),
  // Prompt §4: el administrador no cambia la suscripción. La base hoy permite 'license' a owner y admin;
  // la pantalla lo restringe al propietario (más estricto, nunca más laxo).
  'subscription.manage': PermRule(label: 'Pagar o cambiar el plan', can: ['license'], ownerOnly: true),
};

/// Decisión pura (probada sin Supabase).
bool permits(String id, {required String role, required bool isAdmin, required bool Function(String) can, required bool Function(String) has}) {
  final r = permissionRules[id];
  if (r == null) return false; // denegar por defecto
  if (r.ownerOnly && role != 'owner') return false;
  if (r.adminOnly && !isAdmin) return false;
  for (final k in r.can) {
    if (!can(k)) return false;
  }
  if (r.feature != null && !has(r.feature!)) return false;
  return true;
}

extension AccessPermissions on Access {
  /// ¿Puede este usuario hacer [id] en la empresa activa? (permiso granular, denegar por defecto)
  bool allows(String id) => permits(id, role: role, isAdmin: isAdmin, can: can, has: has);

  /// Permisos efectivos para mostrar en la ficha del integrante.
  List<String> effectivePermissionLabels() => [
        for (final e in permissionRules.entries)
          if (allows(e.key)) e.value.label,
      ];
}
