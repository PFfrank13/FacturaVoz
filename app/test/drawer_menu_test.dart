import 'package:facturavoz/nav/drawer_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> titles(List<(MenuSectionSpec, List<MenuEntry>)> m) => [for (final (s, _) in m) s.title];
  List<String> ids(List<(MenuSectionSpec, List<MenuEntry>)> m) => [for (final (_, items) in m) ...items.map((e) => e.featureId)];

  test('solo aparece lo que el plan y el rol permiten; las categorías vacías no se muestran', () {
    final m = buildMenu(bodegaMenu, tabs: {'home', 'sell', 'stock', 'cash', 'settings'}, allowed: (id) => id == 'facturar' || id == 'gastos');
    expect(titles(m), ['Vender', 'Mercadería', 'Caja y cobros']);
    expect(ids(m), ['pos', 'facturar', 'productos', 'caja', 'gastos']);
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
}
