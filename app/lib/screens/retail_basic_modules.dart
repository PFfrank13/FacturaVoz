import 'package:flutter/material.dart';

import '../access.dart';
import 'catalog.dart';

/// Single navigation source for the Base retail journey. Only real, authorized
/// destinations are rendered; no fake preview cards or unconnected buttons.
class RetailBasicModules extends StatelessWidget {
  const RetailBasicModules({super.key});

  static const _items = <({String id, String label, IconData icon})>[
    (id: 'pos', label: 'Venta rápida', icon: Icons.point_of_sale_rounded),
    (id: 'productos', label: 'Inventario', icon: Icons.inventory_2_rounded),
    (id: 'compras', label: 'Compras', icon: Icons.local_shipping_rounded),
    (id: 'fiados', label: 'Fiados', icon: Icons.group_rounded),
    (id: 'caja', label: 'Caja', icon: Icons.account_balance_wallet_rounded),
    (id: 'reportes', label: 'Reportes', icon: Icons.bar_chart_rounded),
    (id: 'comprobantes', label: 'Comprobantes', icon: Icons.receipt_long_rounded),
    (id: 'clientes', label: 'Clientes', icon: Icons.people_alt_rounded),
    (id: 'ajustes', label: 'Configuración', icon: Icons.settings_rounded),
    (id: 'medios', label: 'Medios de pago', icon: Icons.qr_code_2_rounded),
    (id: 'impresora', label: 'Impresora', icon: Icons.print_rounded),
    (id: 'sunat', label: 'Facturación SUNAT', icon: Icons.verified_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final item in _items)
        if (featureById(item.id) case final feature? when feature.allowed)
          (item: item, feature: feature),
    ];
    if (entries.isEmpty || Access.instance.rubro != 'bodega') {
      return const SizedBox.shrink();
    }

    const purple = Color(0xFF8953F5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.storefront_rounded, color: purple),
          SizedBox(width: 10),
          Expanded(child: Text('Plan Básico · Bodega / Tienda',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 5),
        Text('Tus herramientas, en orden de trabajo. Cada acceso abre su módulo real.',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 13),
        GridView.builder(
          key: const ValueKey('retail-basic-modules'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 100,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final featured = entry.item.id == 'pos';
            return Material(
              color: featured ? const Color(0xFF45258A) :
                Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                key: ValueKey('retail-module-${entry.item.id}'),
                borderRadius: BorderRadius.circular(17),
                onTap: () => openFeature(context, entry.feature),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: featured ? const Color(0xFFC39DFF) :
                        purple.withValues(alpha: .33),
                      width: featured ? 1.5 : 1,
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(entry.item.icon, color: featured ? Colors.white : purple, size: 30),
                    const SizedBox(height: 9),
                    Text(entry.item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: featured ? Colors.white :
                            Theme.of(context).colorScheme.onSurface,
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}
