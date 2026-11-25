import 'package:facturavoz/nav/drawer_menu.dart';
import 'package:facturavoz/rubros.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> titles(List<(MenuSectionSpec, List<MenuEntry>)> m) => [for (final (s, _) in m) s.title];
  List<String> ids(List<(MenuSectionSpec, List<MenuEntry>)> m) => [for (final (_, items) in m) ...items.map((e) => e.featureId)];

  test('solo aparece lo que el plan y el rol permiten; las categorías vacías no se muestran', () {
    final m = buildMenu(bodegaMenu, tabs: {'home', 'sell', 'stock', 'cash', 'settings'}, allowed: (id) => id == 'facturar' || id == 'gastos');
    expect(titles(m), ['Vender', 'Mercadería', 'Caja y cobros', 'Configuración']);
    expect(ids(m), ['pos', 'facturar', 'productos', 'caja', 'gastos', 'ajustes']);
  });

  test('las pestañas se abren como pestaña, no como pantalla repetida', () {
    final m = buildMenu(bodegaMenu, tabs: {'sell', 'stock'}, allowed: (_) => true);
    final pos = m.first.$2.first;
    expect(pos.featureId, 'pos');
    expect(pos.tab, 'sell');
    // Comprobantes no está habilitado como pestaña: no se repite como pantalla aparte.
    expect(ids(m), isNot(contains('comprobantes')));
  });

  test('ninguna función aparece dos veces y los cupones no se repiten si hay Precios y promociones', () {
    final m = buildMenu(bodegaMenu, tabs: {'sell', 'stock', 'compras', 'comprobantes', 'fiados', 'cash', 'clients', 'reportes'}, allowed: (_) => true);
    final all = ids(m);
    expect(all.toSet().length, all.length);
    expect(all, contains('precios'));
    expect(all, isNot(contains('cupones')));
  });

  test('con solo fidelización (sin precios) los cupones sí se ven', () {
    final m = buildMenu(bodegaMenu, tabs: const {}, allowed: (id) => id == 'cupones' || id == 'puntos');
    expect(ids(m), ['cupones', 'puntos']);
    expect(titles(m), ['Clientes y promociones']);
  });

  test('cada categoría tiene su propio color', () {
    expect(bodegaMenu.map((s) => s.color).toSet().length, bodegaMenu.length);
  });

  test('con todas las funciones (Empresa), cada módulo del menú de bodega aparece una vez y en su categoría', () {
    final m = buildMenu(bodegaMenu,
        tabs: {'sell', 'stock', 'compras', 'comprobantes', 'fiados', 'cash', 'clients', 'reportes', 'settings'}, allowed: (_) => true);
    expect(titles(m), ['Vender', 'Mercadería', 'Caja y cobros', 'Clientes y promociones', 'Mi negocio', 'Control del dueño', 'Configuración']);
    final all = ids(m);
    expect(all.toSet().length, all.length);
    for (final id in ['pos', 'comprobantes', 'cotizaciones', 'cuaderno', 'tienda', 'recurrentes', 'productos', 'compras', 'vencimientos', 'reponer',
        'caja', 'fiados', 'cobranza', 'avisos', 'credito', 'gastos', 'escanear', 'banco', 'clientes', 'clientes360', 'precios', 'puntos', 'encuestas',
        'reportes', 'negocio', 'impuestos', 'comisiones', 'agente', 'importar', 'alertas', 'bitacora', 'pin', 'papelera', 'ajustes', 'equipo', 'plan', 'api']) {
      expect(all, contains(id), reason: 'falta $id en el menú');
    }
  });

  test('cada módulo del menú de bodega existe en el catálogo y el rubro lo permite (si el plan lo trae, se ve)', () {
    final catalog = {for (final f in featureCatalog()) f.id: f};
    for (final s in bodegaMenu) {
      for (final id in s.ids) {
        if (featureTab.containsKey(id)) continue; // se abre como pestaña
        expect(catalog.containsKey(id), isTrue, reason: '$id no existe en el catálogo');
        expect(rubroShows(rubroFor('bodega'), id), isTrue, reason: 'el rubro bodega esconde $id');
      }
    }
  });
}
