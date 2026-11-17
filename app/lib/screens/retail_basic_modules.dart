import 'package:flutter/material.dart';

import '../access.dart';
import 'catalog.dart';

/// Inicio operativo de Bodega Básico. La navegación principal está exclusivamente
/// en el NavigationDrawer del MainShell; aquí solo hay acciones directas de trabajo.
/// Ningún acceso aparece si no está autorizado por el Hub y el rol del usuario.
class RetailBasicModules extends StatelessWidget {
  const RetailBasicModules({super.key});

  static const _actions = <({String id, String label, String detail, IconData icon})>[
    (id: 'comprobantes', label: 'Comprobantes',
      detail: 'Emitidos e historial', icon: Icons.receipt_long_rounded),
    (id: 'compras', label: 'Compras',
      detail: 'Recibir mercadería', icon: Icons.local_shipping_rounded),
    (id: 'reportes', label: 'Reportes',
      detail: 'Resultados del negocio', icon: Icons.bar_chart_rounded),
    (id: 'clientes', label: 'Clientes',
      detail: 'Historial de compras', icon: Icons.people_alt_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final a = Access.instance;
    if (a.rubro != 'bodega' || a.license.plan != 'BASICO') {
      return const SizedBox.shrink();
    }
    final pos = featureById('pos');
    final actions = [
      for (final action in _actions)
        if (featureById(action.id) case final f? when f.allowed)
          (action: action, feature: f),
    ];
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final foreground = t.colorScheme.onSurface;
    final subtle = t.colorScheme.onSurfaceVariant;
    const accent = Color(0xFF6366F1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? .20 : .10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tu bodega, en control',
              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
            const SizedBox(height: 2),
            Text('FacturaVoz · Plan Básico', style: t.textTheme.bodySmall?.copyWith(color: subtle)),
          ])),
        ]),
        if (pos != null && pos.allowed) ...[
          const SizedBox(height: 20),
          Material(
            color: accent,
            borderRadius: BorderRadius.circular(17),
            child: InkWell(
              key: const ValueKey('retail-module-pos'),
              borderRadius: BorderRadius.circular(17),
              onTap: () => openFeature(context, pos),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: Row(children: [
                  Container(
                    height: 47, width: 47,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: Colors.white.withValues(alpha: .16),
                    ),
                    child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nueva venta', style: TextStyle(color: Colors.white,
                      fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                    SizedBox(height: 3),
                    Text('Escanea, cobra y registra en un solo flujo',
                      style: TextStyle(color: Color(0xFFE0E7FF), fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ]),
              ),
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 25),
          Text('Acciones rápidas', style: t.textTheme.titleMedium?.copyWith(
            color: foreground, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Operaciones frecuentes, sin menús intermedios',
            style: t.textTheme.bodySmall?.copyWith(color: subtle)),
          const SizedBox(height: 13),
          LayoutBuilder(builder: (context, c) {
            final columns = c.maxWidth >= 720 ? 4 : (c.maxWidth >= 480 ? 3 : 2);
            return GridView.builder(
              key: const ValueKey('retail-basic-modules'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 124,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final entry = actions[index];
                return Material(
                  color: t.colorScheme.surface,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    key: ValueKey('retail-module-${entry.action.id}'),
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => openFeature(context, entry.feature),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: dark ? Colors.white12 : const Color(0xFFE3E7EF)),
                      ),
                      padding: const EdgeInsets.all(13),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(entry.action.icon, color: accent, size: 24),
                        const Spacer(),
                        Text(entry.action.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(entry.action.detail, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(color: subtle, fontSize: 11)),
                      ]),
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ]),
    );
  }
}
