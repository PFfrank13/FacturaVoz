/// Presentation only. Historical business types and Hub grants are unchanged.
const sectorOnlyNavigation = {
  'carta', 'platos', 'paquetes', 'historial', 'placas', 'corte',
  'morosidad', 'margen_obra', 'tipo', 'trabajos', 'agenda',
};

bool isCommerceDestination(String id) => !sectorOnlyNavigation.contains(id);

String commerceExperience(String plan) => switch (plan.toUpperCase()) {
  'BASICO' => 'Básico · Bodega / Tienda',
  'PRO' => 'Pro · Minimarket',
  'EMPRESA' => 'Empresa · Hiperbodega',
  _ => 'Mi plan',
};

/// Ordering is not authorization: callers must filter every entry by Access.
List<String> commerceHomeOrder(String plan) => switch (plan.toUpperCase()) {
  'PRO' => const ['productos', 'fiados', 'caja', 'tienda', 'reponer', 'precios', 'reportes', 'equipo'],
  'EMPRESA' => const ['productos', 'caja', 'fiados', 'reportes', 'equipo', 'tienda', 'reponer', 'bitacora'],
  _ => const ['productos', 'fiados', 'caja', 'clientes', 'reponer', 'tienda', 'reportes', 'equipo'],
};
