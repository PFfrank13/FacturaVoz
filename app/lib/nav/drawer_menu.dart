// Menú lateral por categorías (v3.7): todo lo que el plan contratado y el rol permiten, agrupado como piensa el
// bodeguero y sin repetir nada. Lo que el plan no incluye no aparece. Lógica pura: se prueba en test/drawer_menu_test.dart.
import 'package:flutter/material.dart';

class MenuSectionSpec {
  const MenuSectionSpec(this.title, this.color, this.icon, this.ids);
  final String title;
  final Color color;
  final IconData icon;

  /// Ids de funciones del catálogo (catalog.dart), en el orden en que se ven.
  final List<String> ids;
}

/// Categorías del menú de Bodega / Minimarket. Cada una con su color propio para reconocerla de un vistazo.
const bodegaMenu = <MenuSectionSpec>[
  MenuSectionSpec('Vender', Color(0xFF0E8C74), Icons.point_of_sale_rounded,
      ['pos', 'facturar', 'comprobantes', 'cotizaciones', 'cuaderno', 'tienda', 'recurrentes']),
  MenuSectionSpec('Mercadería', Color(0xFF2F6FDC), Icons.inventory_2_rounded,
      ['productos', 'compras', 'vencimientos', 'reponer']),
  MenuSectionSpec('Caja y cobros', Color(0xFFC77417), Icons.account_balance_wallet_rounded,
      ['caja', 'fiados', 'cobranza', 'avisos', 'credito', 'gastos', 'escanear', 'banco']),
  MenuSectionSpec('Clientes y promociones', Color(0xFFC2407E), Icons.loyalty_rounded,
      ['clientes', 'clientes360', 'precios', 'cupones', 'puntos', 'encuestas']),
  MenuSectionSpec('Mi negocio', Color(0xFF6A5AE0), Icons.insights_rounded,
      ['reportes', 'negocio', 'impuestos', 'comisiones', 'agente', 'importar']),
  MenuSectionSpec('Control del dueño', Color(0xFF8A4B2F), Icons.shield_rounded,
      ['alertas', 'bitacora', 'pin', 'papelera']),
  // Igual que la web: los ajustes del negocio, el equipo, el plan y las conexiones (API, plan Empresa).
  MenuSectionSpec('Configuración', Color(0xFF4F6480), Icons.settings_rounded,
      ['ajustes', 'equipo', 'plan', 'api']),
];

/// Funciones que ya son una pestaña del shell: se abren como pestaña (no como pantalla aparte) para no duplicar.
const featureTab = <String, String>{
  'pos': 'sell',
  'productos': 'stock',
  'compras': 'compras',
  'comprobantes': 'comprobantes',
  'fiados': 'fiados',
  'caja': 'cash',
  'clientes': 'clients',
  'reportes': 'reportes',
  'ajustes': 'settings',
};

/// Un ítem del menú: una pestaña del shell o una función del catálogo.
class MenuEntry {
  const MenuEntry(this.featureId, {this.tab});
  final String featureId;
  final String? tab;
  bool get isTab => tab != null;

  @override
  bool operator ==(Object other) => other is MenuEntry && other.featureId == featureId && other.tab == tab;
  @override
  int get hashCode => Object.hash(featureId, tab);
  @override
  String toString() => tab == null ? featureId : '$featureId→$tab';
}

/// Arma las secciones visibles. [tabs] = pestañas que el plan y el rol permiten; [allowed] = ¿el catálogo permite
/// esa función (plan, rol y rubro)? Cada función aparece una sola vez y las secciones vacías no se muestran.
List<(MenuSectionSpec, List<MenuEntry>)> buildMenu(
  List<MenuSectionSpec> spec, {
  required Set<String> tabs,
  required bool Function(String featureId) allowed,
}) {
  final seen = <String>{};
  final out = <(MenuSectionSpec, List<MenuEntry>)>[];
  for (final s in spec) {
    final items = <MenuEntry>[];
    for (final id in s.ids) {
      if (seen.contains(id)) continue;
      // "Precios y promociones" ya incluye los cupones: no se repiten.
      if (id == 'cupones' && seen.contains('precios')) continue;
      final tab = featureTab[id];
      if (tab != null && tabs.contains(tab)) {
        items.add(MenuEntry(id, tab: tab));
      } else if (tab == null && allowed(id)) {
        items.add(MenuEntry(id));
      } else {
        continue;
      }
      seen.add(id);
    }
    if (items.isNotEmpty) out.add((s, items));
  }
  return out;
}
