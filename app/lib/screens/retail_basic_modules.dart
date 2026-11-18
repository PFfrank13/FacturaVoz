import 'package:flutter/material.dart';

import '../access.dart';
import '../permissions.dart';
import '../ui/theme.dart';
import 'catalog.dart';

/// Entrada histórica para Básico: mantiene el contrato de navegación y tests.
/// No dibuja nada para Pro, Empresa o licencias no verificadas.
class RetailBasicModules extends StatelessWidget {
  const RetailBasicModules({super.key});

  @override
  Widget build(BuildContext context) =>
      Access.instance.license.plan == 'BASICO'
          ? const _RetailPlanDashboard(basic: true)
          : const SizedBox.shrink();
}

/// El mismo diseño operativo para Pro y Empresa. La elección de accesos
/// se basa SOLO en funciones concedidas por Hub y permisos reales del rol.
class RetailPlanModules extends StatelessWidget {
  const RetailPlanModules({super.key});

  @override
  Widget build(BuildContext context) =>
      Access.instance.license.plan != 'BASICO'
          ? const _RetailPlanDashboard(basic: false)
          : const SizedBox.shrink();
}

typedef _RetailAction = ({
  String id,
  String label,
  String detail,
  IconData icon,
});

class _RetailPlanDashboard extends StatelessWidget {
  const _RetailPlanDashboard({required this.basic});

  final bool basic;

  static const _common = <_RetailAction>[
    (id: 'comprobantes', label: 'Comprobantes',
      detail: 'Historial y emisión', icon: Icons.receipt_long_rounded),
    (id: 'compras', label: 'Compras',
      detail: 'Recibir mercadería', icon: Icons.local_shipping_rounded),
    (id: 'reportes', label: 'Reportes',
      detail: 'Resultados del negocio', icon: Icons.bar_chart_rounded),
    (id: 'clientes', label: 'Clientes',
      detail: 'Historial de compras', icon: Icons.people_alt_rounded),
  ];

  static const _extra = <_RetailAction>[
    (id: 'cotizaciones', label: 'Cotizaciones',
      detail: 'Presupuestos y pedidos', icon: Icons.request_quote_rounded),
    (id: 'precios', label: 'Promociones',
      detail: 'Ofertas y descuentos', icon: Icons.local_offer_rounded),
    (id: 'recurrentes', label: 'Recurrentes',
      detail: 'Facturación periódica', icon: Icons.event_repeat_rounded),
    (id: 'comisiones', label: 'Comisiones',
      detail: 'Ventas por vendedor', icon: Icons.emoji_events_rounded),
    (id: 'tienda', label: 'Tienda en línea',
      detail: 'Catálogo y pedidos', icon: Icons.storefront_rounded),
    (id: 'clientes360', label: 'Análisis de clientes',
      detail: 'Actividad y segmentos', icon: Icons.insights_rounded),
  ];

  /// Colores funcionales: reconocimiento rápido sin saturar el tablero.
  static Color _toneFor(String id) => switch (id) {
    'comprobantes' => const Color(0xFF0D9488),
    'compras' => const Color(0xFF287DB1),
    'reportes' => const Color(0xFFC38128),
    'clientes' || 'clientes360' => const Color(0xFF2A936B),
    'cotizaciones' => const Color(0xFF4A7C9F),
    'precios' => const Color(0xFFC17B39),
    'recurrentes' => const Color(0xFF329394),
    'comisiones' => const Color(0xFFAC6671),
    _ => const Color(0xFF297E9D),
  };

  @override
  Widget build(BuildContext context) {
    final a = Access.instance;
    if (a.rubro != 'bodega' || !a.licenseReady ||
        (basic && a.license.plan != 'BASICO') ||
        (!basic && a.license.plan == 'BASICO')) {
      return const SizedBox.shrink();
    }
    final pos = featureById('pos');
    List<({ _RetailAction action, FeatureEntry feature })> allowed(List<_RetailAction> actions) => [
      for (final action in actions)
        // El catálogo legado no exige permiso explícito para Comprobantes
        // ni Comisiones. No ofrecer accesos que el rol no puede operar.
        if ((action.id != 'comprobantes' || a.allows('sales.read')) &&
            (action.id != 'comisiones' || a.can('sell') || a.can('finance')))
          if (featureById(action.id) case final f? when f.allowed)
            (action: action, feature: f),
    ];
    final common = allowed(_common);
    final premium = basic ? <({ _RetailAction action, FeatureEntry feature })>[] : allowed(_extra);
    // Las cuatro funciones operativas no desaparecen al contratar Pro/Empresa.
    // Las herramientas adicionales viven en un carrusel discreto, no en otro menú.
    final actions = common.take(4).toList();
    final theme = Theme.of(context);
    final colors = DsColors.of(context);
    final title = switch (a.license.plan) {
      'BASICO' => 'Básico',
      'PRO' => 'Pro',
      'EMPRESA' => 'Empresa',
      final other => other,
    };
    final compactWidth = MediaQuery.sizeOf(context).width < 370;
    final foreground = theme.colorScheme.onPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: colors.elevated,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(Icons.storefront_rounded, color: colors.primaryText, size: 24),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tu negocio, al día',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.ink, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            const SizedBox(height: Gap.xs),
            Text('FacturaVoz · Plan $title',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
          ])),
        ]),
        if (pos != null && pos.allowed) ...[
          const SizedBox(height: 20),
          Material(
            color: colors.primary,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: InkWell(
              key: const ValueKey('retail-module-pos'),
              borderRadius: BorderRadius.circular(Radii.lg),
              onTap: () => openFeature(context, pos),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                child: Row(children: [
                  Container(
                    height: 46, width: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.md),
                      color: foreground.withValues(alpha: .15),
                    ),
                    child: Icon(Icons.point_of_sale_rounded, color: foreground, size: 25),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nueva venta', style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground, fontWeight: FontWeight.w800)),
                    const SizedBox(height: Gap.xs),
                    Text(compactWidth ? 'Escanea, cobra y registra' :
                      'Escanea, cobra y registra en un solo flujo',
                      style: theme.textTheme.bodySmall?.copyWith(color: foreground.withValues(alpha: .92))),
                  ])),
                  Icon(Icons.arrow_forward_rounded, color: foreground),
                ]),
              ),
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Tu espacio de trabajo',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: Gap.xs),
          Text('Accede directamente a lo que usas cada día',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
          const SizedBox(height: Gap.md),
          LayoutBuilder(builder: (context, layout) {
            final columns = layout.maxWidth >= 720 ? 4
                : (layout.maxWidth >= 480 ? 3 : 2);
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.25;
            return GridView.builder(
              key: ValueKey(basic ? 'retail-basic-modules' : 'retail-plan-modules'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: largeText ? 152 : 124,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder: (context, i) {
                final entry = actions[i];
                final tone = _toneFor(entry.action.id);
                return Material(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: InkWell(
                    key: ValueKey('retail-module-${entry.action.id}'),
                    onTap: () => openFeature(context, entry.feature),
                    hoverColor: colors.primary.withValues(alpha: .05),
                    splashColor: colors.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: colors.line),
                        boxShadow: Brand.softShadow(theme.brightness == Brightness.dark, a: .04),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: tone.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(entry.action.icon, color: tone, size: 20),
                          ),
                          const Spacer(),
                          Icon(Icons.north_east_rounded, color: colors.muted, size: 15),
                        ]),
                        const Spacer(),
                        Text(entry.action.label, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.ink, fontWeight: FontWeight.w800)),
                        const SizedBox(height: Gap.xs),
                        Text(entry.action.detail, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.muted, fontSize: 11)),
                      ]),
                    ),
                  ),
                );
              },
            );
          }),
        ],
        if (premium.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Herramientas de tu plan',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: Gap.xs),
          Text('Funciones adicionales incluidas en tu licencia',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
          const SizedBox(height: Gap.md),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(1) > 1.25 ? 168 : 142,
            child: ListView.separated(
              key: const ValueKey('retail-plan-premium'),
              scrollDirection: Axis.horizontal,
              itemCount: premium.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final entry = premium[i];
                final tone = _toneFor(entry.action.id);
                return SizedBox(
                  width: 174,
                  child: Material(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: InkWell(
                      key: ValueKey('retail-extra-${entry.action.id}'),
                      onTap: () => openFeature(context, entry.feature),
                      hoverColor: colors.primary.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: colors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: tone.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(entry.action.icon, color: tone, size: 20),
                              ),
                              const Spacer(),
                              Icon(Icons.north_east_rounded, color: colors.muted, size: 15),
                            ]),
                            const Spacer(),
                            Text(entry.action.label, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.ink, fontWeight: FontWeight.w800)),
                            const SizedBox(height: Gap.xs),
                            Text(entry.action.detail, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }
}
