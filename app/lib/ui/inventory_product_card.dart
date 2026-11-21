import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'motion.dart';
import 'glass_widgets.dart';

/// Presentación del inventario real. Los datos, permisos y cambios de stock
/// siguen siendo responsabilidad de ProductsScreen y sus repositorios.
class FvInventoryProductCard extends StatelessWidget {
  const FvInventoryProductCard({
    super.key,
    required this.name,
    required this.price,
    required this.isService,
    required this.active,
    this.category,
    this.barcode,
    this.stockLabel,
    this.marginLabel,
    this.lowStock = false,
    this.stockIsCritical = false,
    this.photo,
    this.onOpen,
  });

  final String name;
  final String price;
  final bool isService;
  final bool active;
  final String? category;
  final String? barcode;
  final String? stockLabel;
  final String? marginLabel;
  final bool lowStock;
  final bool stockIsCritical;
  final Widget? photo;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final accent = stockIsCritical ? t.colorScheme.error
        : lowStock ? (t.brightness == Brightness.dark ? const Color(0xFFFFC775) : const Color(0xFF805018))
        : t.colorScheme.primary;
    final subtitle = category == null || category!.trim().isEmpty
        ? (isService ? 'Servicio' : 'Producto')
        : category!.trim();
    final indicator = !active ? 'Archivado'
        : stockIsCritical ? 'Por regularizar'
        : lowStock ? 'Stock bajo'
        : 'Disponible';

    return Semantics(
      container: true,
      button: onOpen != null,
      label: '$name, precio $price, $indicator',
      child: FvTactileScale(
        enabled: onOpen != null,
        child: DecoratedBox(
          decoration: FvSurfaces.card(t),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FvTokens.cardRadius),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(FvTokens.cardRadius),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: SizedBox(
                              width: 88,
                              height: 88,
                              child: photo ?? FvProductPhotoFallback(name: name, category: category,
                                icon: isService ? Icons.handyman_outlined : Icons.inventory_2_outlined),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subtitle.toUpperCase(),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w800,
                                    color: muted)),
                                const SizedBox(height: 5),
                                Text(name, maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.titleMedium?.copyWith(
                                    height: 1.17, fontWeight: FontWeight.w800,
                                    letterSpacing: -.3)),
                                const SizedBox(height: 9),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      !active ? Icons.archive_outlined
                                          : stockIsCritical ? Icons.error_outline_rounded
                                          : lowStock ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                                      size: 14,
                                      color: active ? accent : muted),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(indicator, maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.textTheme.labelSmall?.copyWith(
                                          color: active ? accent : muted,
                                          fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (stockLabel != null || marginLabel != null) ...[
                        const SizedBox(height: 13),
                        Wrap(spacing: 7, runSpacing: 6, children: [
                          if (stockLabel != null)
                            _InfoPill(
                              icon: Icons.inventory_2_outlined,
                              text: stockLabel!,
                              ink: stockIsCritical || lowStock
                                  ? accent : t.colorScheme.primary),
                          if (marginLabel != null)
                            _InfoPill(
                              icon: Icons.trending_up_rounded,
                              text: marginLabel!,
                              ink: t.colorScheme.onSurfaceVariant),
                        ]),
                      ],
                      const SizedBox(height: 13),
                      Divider(height: 1, color: t.colorScheme.outlineVariant),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PRECIO UNITARIO',
                                style: t.textTheme.labelSmall?.copyWith(
                                  color: muted, fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w700)),
                              if (barcode != null && barcode!.trim().isNotEmpty)
                                Text(barcode!.trim(), maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.labelSmall?.copyWith(
                                    color: muted)),
                            ],
                          )),
                          const SizedBox(width: 8),
                          Text(price, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleLarge?.copyWith(
                              color: t.colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ])),
                          if (onOpen != null) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded,
                              size: 19, color: muted),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.text,
    required this.ink,
  });
  final IconData icon;
  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: dark ? .19 : .09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: ink),
        const SizedBox(width: 5),
        Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: ink, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
