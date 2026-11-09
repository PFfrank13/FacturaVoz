import 'package:flutter/material.dart';

import '../access.dart';
import 'catalog.dart';
import 'menu.dart';

/// Bodega Basic: a single route to the existing, permission-checked modules.
/// No parallel POS, duplicated financial data, or fictional business metrics.
class RetailBasicModules extends StatelessWidget {
  const RetailBasicModules({super.key});

  static const _primary = <({
    String id, String label, String detail, IconData icon, Color top, Color bottom
  })>[
    (id: 'pos', label: 'Nueva venta', detail: 'Escanear y cobrar',
      icon: Icons.point_of_sale_rounded,
      top: Color(0xFF8355FB), bottom: Color(0xFF4053D3)),
    (id: 'productos', label: 'Inventario', detail: 'Productos y stock',
      icon: Icons.inventory_2_rounded,
      top: Color(0xFF12A6C3), bottom: Color(0xFF1066A0)),
    (id: 'compras', label: 'Compras', detail: 'Recibir mercadería',
      icon: Icons.local_shipping_rounded,
      top: Color(0xFF087EDE), bottom: Color(0xFF294BBE)),
    (id: 'fiados', label: 'Fiados', detail: 'Deudas y abonos',
      icon: Icons.menu_book_rounded,
      top: Color(0xFF69BD21), bottom: Color(0xFF187A40)),
    (id: 'caja', label: 'Caja', detail: 'Arqueo y cierre',
      icon: Icons.account_balance_wallet_rounded,
      top: Color(0xFF139E73), bottom: Color(0xFF086B54)),
    (id: 'reportes', label: 'Reportes', detail: 'Resultados reales',
      icon: Icons.bar_chart_rounded,
      top: Color(0xFF8D4BEE), bottom: Color(0xFF5231A7)),
    (id: 'comprobantes', label: 'Comprobantes', detail: 'Boletas y facturas',
      icon: Icons.receipt_long_rounded,
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
    final salesFeature = featureById('pos');
    final main = [
      for (final tile in _primary)
        if (tile.id != 'pos')
          if (featureById(tile.id) case final feature? when feature.allowed)
            (tile: tile, feature: feature),
    ];
    final extras = [
      for (final tile in _secondary)
        if (featureById(tile.id) case final feature? when feature.allowed)
          (tile: tile, feature: feature),
    ];
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    const lilac = Color(0xFFC7B6FF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 46, width: 46,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF242557) : const Color(0xFFEFEAFF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Image.asset('assets/branding/facturavoz_mark.png',
              fit: BoxFit.contain, semanticLabel: 'FacturaVoz'),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tu bodega, en control',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            Text('FacturaVoz · Plan Básico',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ])),
          const Icon(Icons.storefront_rounded, size: 27, color: Color(0xFF9664EE)),
        ]),
        const SizedBox(height: 15),
        if (salesFeature != null && salesFeature.allowed) ...[
          _saleAction(context, salesFeature),
          const SizedBox(height: 20),
        ],
        Row(children: [
          Expanded(child: Text('Herramientas de tu negocio',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          Text('PLAN BÁSICO', style: theme.textTheme.labelSmall?.copyWith(
            color: dark ? lilac : const Color(0xFF6041B3),
            fontWeight: FontWeight.w900, letterSpacing: .8)),
        ]),
        const SizedBox(height: 5),
        Text('Cada acceso abre su módulo real, según tu rol y licencia.',
          style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 720 ? 4 : (width >= 480 ? 3 : 2);
          final scale = MediaQuery.textScalerOf(context).scale(1.0);
          final extent = 166.0 + (scale > 1 ? (scale - 1) * 105 : 0);
          return GridView.builder(
            key: const ValueKey('retail-basic-modules'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: main.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: extent,
            ),
            itemBuilder: (context, index) {
              if (index == main.length) {
                return _tile(context,
                  key: const ValueKey('retail-module-all'),
                  label: 'Ver todas', detail: 'Más herramientas',
                  icon: Icons.apps_rounded,
                  top: const Color(0xFF69648E),
                  bottom: const Color(0xFF373263),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const MenuScreen())),
                );
              }
              final entry = main[index];
              return _tile(context,
                key: ValueKey('retail-module-${entry.tile.id}'),
                label: entry.tile.label, detail: entry.tile.detail,
                icon: entry.tile.icon,
                top: entry.tile.top, bottom: entry.tile.bottom,
                onTap: () => openFeature(context, entry.feature),
              );
            },
          );
        }),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 15),
          Material(
            color: dark ? const Color(0xFF1C224F) : const Color(0xFFF1F0FA),
            borderRadius: BorderRadius.circular(18),
            child: ExpansionTile(
              key: const ValueKey('retail-other-modules'),
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 15),
              title: Text('Más herramientas',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              subtitle: Text('${extras.length} accesos · Reposición, pagos y ajustes',
                style: theme.textTheme.bodySmall),
              leading: const Icon(Icons.tune_rounded, color: Color(0xFF8866EA)),
              children: [
                for (final extra in extras)
                  ListTile(
                    key: ValueKey('retail-secondary-${extra.tile.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(extra.tile.icon, color: const Color(0xFF8866EA)),
                    title: Text(extra.tile.label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openFeature(context, extra.feature),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 15),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF171C41) : const Color(0xFFF4F1FF),
            border: Border.all(color: dark ? const Color(0xFF49417A) : const Color(0xFFDCD4F7)),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.route_rounded, color: Color(0xFF9271E7), size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tu flujo de trabajo',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Inventario → Compras → Ventas → Caja → Comprobantes → Reportes',
                style: theme.textTheme.bodySmall?.copyWith(color: ink.withValues(alpha: .78))),
            ])),
          ]),
        ),
      ]),
    );
  }

  Widget _saleAction(BuildContext context, FeatureEntry feature) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final action = Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('retail-module-pos'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => openFeature(context, feature),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF804EF5), Color(0xFF5033B7), Color(0xFF273A91)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(
              color: const Color(0xFF7544DC).withValues(alpha: .22),
              blurRadius: 20, offset: const Offset(0, 8),
            )],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 17),
            child: Row(children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .17),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: .30)),
                ),
                child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('EMPEZAR UNA VENTA', style: TextStyle(
                  color: Color(0xFFDED3FF), fontSize: 10.5, letterSpacing: .8,
                  fontWeight: FontWeight.w900)),
                SizedBox(height: 5),
                Text('Nueva venta', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                SizedBox(height: 3),
                Text('Escanea productos, cobra y registra.',
                  style: TextStyle(color: Color(0xFFE7E0FF), fontSize: 12.5)),
              ])),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 24),
            ]),
          ),
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: .96, end: 1),
      builder: (context, value, child) => Transform.scale(
        scale: value, child: Opacity(opacity: value, child: child)),
      child: action,
    );
  }

  Widget _tile(
    BuildContext context, {
    required Key key,
    required String label,
    required String detail,
    required IconData icon,
    required Color top,
    required Color bottom,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF1C2147) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: dark ? const Color(0xFF494875) : const Color(0xFFE6E1F1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: dark ? .10 : .04),
                blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    height: 43, width: 43,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [top, bottom]),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, size: 24, color: Colors.white),
                  ),
                  const Spacer(),
                  Icon(Icons.north_east_rounded, size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: .38)),
                ]),
                const SizedBox(height: 10),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
