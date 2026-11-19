import 'package:flutter/foundation.dart' show kDebugMode;

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

/// Pantalla B1: el plan Básico ofrece herramientas operativas, sin vitrinas
/// premium ni opciones de otros rubros. Es una decisión de presentación:
/// Access y el servidor siguen validando los derechos efectivos.
const basicCommerceMenuIds = <String>{
  'pos', 'facturar', 'comprobantes', 'cotizaciones',
  'productos', 'inventario', 'clientes', 'fiados', 'me_deben', 'cobranza',
  'caja', 'compras', 'gastos', 'avisos', 'reportes',
  'ajustes', 'datos', 'sunat', 'marca', 'impresora', 'medios',
  'seguridad', 'plan', 'equipo',
};

/// No habilita funciones: primero se verifica este filtro visual y DESPUÉS
/// la licencia efectiva y el rol mediante FeatureEntry.allowed.
bool commerceMenuVisible(String id, String plan) {
  if (!isCommerceDestination(id)) return false;
  if (plan.toUpperCase() == 'BASICO') return basicCommerceMenuIds.contains(id);
  return true; // Próximas fases: experiencias Pro/Empresa, respetando Hub.
}

String commerceMenuGroup(String group) => switch (group) {
  'Vender' => 'Ventas y productos',
  'Clientes y trabajos' => 'Clientes',
  'Cobrar y pagar' => 'Caja, cobros y compras',
  'Mi negocio' => 'Informes',
  'Control del dueño' => 'Control y seguridad',
  'Ajustes' => 'Mi negocio y ajustes',
  _ => group,
};


/// B1: la experiencia del Básico puede comprobarse en la MISMA app real
/// durante `flutter run` en debug. No modifica Hub, RPC, RLS, roles ni Access.has.
/// El modo se elimina por una condición compilada en cualquier build release.
/// Desactívalo en debug con --dart-define=FV_B1_LOCAL_PREVIEW=false.
bool get basicLocalPreview => kDebugMode &&
    const bool.fromEnvironment('FV_B1_LOCAL_PREVIEW', defaultValue: true);

/// En la fase B1, el emulador muestra el catálogo comercial de Básico,
/// aunque la licencia histórica del Hub sea otra. Producción usa el Hub.
String commerceViewPlan(String actualHubPlan) =>
    basicLocalPreview ? 'BASICO' : actualHubPlan.toUpperCase();

/// Visibilidad de un destino; nunca debe utilizarse como autorización.
/// Un empleado sin permiso de rol sigue sin visualizarlo.
bool commerceEntryVisible({
  required String id,
  required String hubPlan,
  required bool roleOk,
  required bool planOk,
  bool? localPreview,
}) {
  if (!roleOk) return false;
  final preview = localPreview ?? basicLocalPreview;
  final visiblePlan = preview ? 'BASICO' : hubPlan.toUpperCase();
  if (!commerceMenuVisible(id, visiblePlan)) return false;
  return planOk || (preview && basicCommerceMenuIds.contains(id));
}
