import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// Tarjeta POS sin lógica de negocio. La pantalla propietaria mantiene
/// _add, precios, promociones, stock, permisos e idempotencia de cobro.
class FvPosProductCard extends StatelessWidget {
  const FvPosProductCard({
    super.key,
    required this.name,
    required this.price,
    required this.icon,
    required this.onAdd,
    this.photo,
    this.category,
    this.stockLabel,
    this.quantity,
    this.onRemove,
    this.soldOut = false,
  });

  final String name;
  final String price;
  final IconData icon;
  final Widget? photo;
  final String? category;
  final String? stockLabel;
  final String? quantity;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;
  final bool soldOut;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final muted = t.colorScheme.onSurfaceVariant;
    final isSelected = quantity != null;
    final disabled = soldOut && !isSelected;
    return Semantics(
      container: true,
      label: '$name, $price, ${stockLabel ?? 'stock no indicado'}',
      child: AnimatedContainer(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero : FvTokens.micro,
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(FvTokens.cardRadius),
          border: Border.all(
            color: isSelected
                ? FvTokens.positive(t.brightness).withValues(alpha: 0.38)
                : (dark ? FvTokens.strokeDark : Colors.transparent),
          ),
          boxShadow: FvTokens.shadow(t.brightness),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FvTokens.cardRadius),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: disabled ? null : () {
                HapticFeedback.lightImpact();
                onAdd();
              },
              onLongPress: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Stack(children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: ColoredBox(
                            color: dark ? FvTokens.fieldDark : const Color(0xFFF9FAFB),
                            child: photo ?? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, color: muted, size: 43),
                                if (category != null && category!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5, left: 5, right: 5),
                                    child: Text(category!, maxLines: 1,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.textTheme.labelSmall?.copyWith(color: muted)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (stockLabel != null)
                        Positioned(
                          left: 6, top: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: dark ? FvTokens.surfaceDark : Colors.white.withValues(alpha: 0.93),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                              child: Text(stockLabel!, maxLines: 1,
                                style: t.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: soldOut ? t.colorScheme.error : muted,
                                  fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      if (isSelected)
                        Positioned(right: 6, top: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: FvTokens.positive(t.brightness),
                              borderRadius: BorderRadius.circular(99)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(quantity!, style: const TextStyle(
                                color: Colors.white, fontSize: 11,
                                fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                    ])),
                    const SizedBox(height: 10),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelMedium?.copyWith(
                        color: t.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      )),
                    const SizedBox(height: 7),
                    Row(children: [
                      Expanded(child: Text(price, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ))),
                      const SizedBox(width: 4),
                      SizedBox.square(
                        dimension: 43,
                        child: IconButton.filled(
                          tooltip: 'Añadir $name',
                          onPressed: disabled ? null : () {
                            HapticFeedback.lightImpact();
                            onAdd();
                          },
                          icon: const Icon(Icons.add_rounded, size: 23),
                          style: IconButton.styleFrom(
                            backgroundColor: FvTokens.ink,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: t.disabledColor.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
