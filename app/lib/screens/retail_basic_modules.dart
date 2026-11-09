import 'package:flutter/material.dart';

import '../access.dart';
import 'catalog.dart';
import 'menu.dart';

/// The Basic bodega dashboard follows the same visual order as the retail
/// flowchart. Every tile points to an existing authorized, functioning screen.
class RetailBasicModules extends StatelessWidget {
  const RetailBasicModules({super.key});

  static const _primary = <({String id, String label, IconData icon, Color top, Color bottom})>[
    (id: 'pos', label: 'Nueva venta', icon: Icons.shopping_cart_checkout_rounded,
      top: Color(0xFF7947FF), bottom: Color(0xFF3655E3)),
    (id: 'productos', label: 'Inventario', icon: Icons.inventory_2_rounded,
      top: Color(0xFF12A6C3), bottom: Color(0xFF1066A0)),
    (id: 'compras', label: 'Compras', icon: Icons.local_shipping_rounded,
      top: Color(0xFF087EDE), bottom: Color(0xFF294BBE)),
    (id: 'fiados', label: 'Fiados', icon: Icons.groups_rounded,
      top: Color(0xFF69BD21), bottom: Color(0xFF187A40)),
    (id: 'caja', label: 'Caja', icon: Icons.account_balance_wallet_rounded,
      top: Color(0xFF139E73), bottom: Color(0xFF086B54)),
    (id: 'reportes', label: 'Reportes', icon: Icons.bar_chart_rounded,
      top: Color(0xFF8D4BEE), bottom: Color(0xFF5231A7)),
    (id: 'comprobantes', label: 'Comprobantes', icon: Icons.receipt_long_rounded,
      top: Color(0xFF4776EA), bottom: Color(0xFF2852BC)),
  ];
  static const _secondary = <({String id, String label, IconData icon})>[
    (id: 'reponer', label: 'Reponer', icon: Icons.add_box_rounded),
    (id: 'clientes', label: 'Clientes', icon: Icons.people_alt_rounded),
    (id: 'gastos', label: 'Gastos', icon: Icons.receipt_long_outlined),
    (id: 'ajustes', label: 'Configuración', icon: Icons.settings_rounded),
    (id: 'medios', label: 'Medios de pago', icon: Icons.qr_code_2_rounded),
    (id: 'impresora', label: 'Impresora', icon: Icons.print_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    if (Access.instance.rubro != 'bodega') return const SizedBox.shrink();
    final main = [
      for (final tile in _primary)
        if (featureById(tile.id) case final feature? when feature.allowed)
          (tile: tile, feature: feature),
    ];
    final extras = [
      for (final tile in _secondary)
        if (featureById(tile.id) case final feature? when feature.allowed)
          (tile: tile, feature: feature),
    ];
    const lilac = Color(0xFFC7B6FF);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.storefront_rounded, color: lilac, size: 23),
          SizedBox(width: 8),
          Expanded(child: Text('Plan Básico · Bodega / Tienda',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
        ]),
        const SizedBox(height: 4),
        Text('Tus herramientas, en el orden en que las usas cada día.',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        GridView.builder(
          key: const ValueKey('retail-basic-modules'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: main.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 9,
            crossAxisSpacing: 8,
            mainAxisExtent: 91,
          ),
          itemBuilder: (context, index) {
            if (index == main.length) {
              return _tile(context,
                key: const ValueKey('retail-module-all'),
                label: 'Ver todas',
                icon: Icons.apps_rounded,
                top: const Color(0xFF57538E),
                bottom: const Color(0xFF302A66),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MenuScreen())),
              );
            }
            final entry = main[index];
            return _tile(context,
              key: ValueKey('retail-module-${entry.tile.id}'),
              label: entry.tile.label,
              icon: entry.tile.icon,
              top: entry.tile.top, bottom: entry.tile.bottom,
              onTap: () => openFeature(context, entry.feature),
            );
          },
        ),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C224F),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFF50417F)),
            ),
            child: ExpansionTile(
              key: const ValueKey('retail-other-modules'),
              title: const Text('Más herramientas del negocio',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              subtitle: const Text('Reponer, clientes, pagos y ajustes'),
              leading: const Icon(Icons.tune_rounded, color: lilac),
              children: [
                for (final extra in extras)
                  ListTile(
                    key: ValueKey('retail-secondary-${extra.tile.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(extra.tile.icon, color: lilac),
                    title: Text(extra.tile.label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openFeature(context, extra.feature),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF171C41),
            border: Border.all(color: const Color(0xFF49417A)),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Orden recomendado de trabajo',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text('1. Inventario  ·  2. Compras  ·  3. Nueva venta',
              style: TextStyle(fontSize: 11.5)),
            SizedBox(height: 3),
            Text('4. Caja  ·  5. Comprobantes  ·  6. Reportes',
              style: TextStyle(fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _tile(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required Color top,
    required Color bottom,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity, height: 57,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft,
                end: Alignment.bottomRight, colors: [top, bottom]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
              boxShadow: [
                BoxShadow(color: top.withValues(alpha: .16), blurRadius: 9, offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.3, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
