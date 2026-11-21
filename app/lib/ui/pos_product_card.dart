import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'glass_widgets.dart';
import 'motion.dart';

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
      child: FvTactileScale(
        enabled: !disabled,
        child: AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero : FvTokens.micro,
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: BorderRadius.circular(FvTokens.cardRadius),
            border: Border.all(
              color: isSelected
                  ? FvLuxe.jade.withValues(alpha: .82)
                  : (dark ? FvTokens.strokeDark : const Color(0xFFE5EDF5)),
            ),
            boxShadow: FvTokens.shadow(t.brightness),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FvTokens.cardRadius),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: disabled ? null : onAdd,
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
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: FvLuxe.productBackdrop(t.brightness)),
                              child: photo ?? FvProductPhotoFallback(name: name, category: category, icon: icon),
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
                        Positioned(right: 6, top: 6,
                          child: Semantics(
                            label: isSelected ? '$quantity en el carrito' : null,
                            excludeSemantics: true,
                            child: AnimatedSwitcher(
                              duration: Motion.d(context, const Duration(milliseconds: 260)),
                              reverseDuration: Motion.d(context, const Duration(milliseconds: 140)),
                              // Notification Badge: el contador aparece sin desplazar el botón.
                              transitionBuilder: (child, animation) => FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  alignment: Alignment.topRight,
                                  scale: Tween<double>(begin: .70, end: 1).chain(
                                    CurveTween(curve: const Cubic(.34, 1.36, .64, 1)),
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                              child: !isSelected ? null : DecoratedBox(
                                decoration: BoxDecoration(
                                  color: dark ? FvTokens.emeraldDark : FvLuxe.jade,
                                  borderRadius: BorderRadius.circular(99)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: FvQuantityText(quantity!,
                                    style: TextStyle(
                                      color: dark ? FvTokens.canvasDark : Colors.white,
                                      fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(right: 4, bottom: 4, child: SizedBox.square(
                          dimension: 44,
                          child: IconButton.filled(
                            tooltip: 'Añadir $name',
                            onPressed: disabled ? null : onAdd,
                            icon: const Icon(Icons.add_rounded, size: 23),
                            style: IconButton.styleFrom(
                              backgroundColor: t.colorScheme.primary,
                              foregroundColor: t.colorScheme.onPrimary,
                              disabledBackgroundColor: t.disabledColor.withValues(alpha: 0.2),
                            ),
                          ),
                        )),
                      ])),
                      const SizedBox(height: 10),
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelMedium?.copyWith(
                          color: t.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        )),
                      const SizedBox(height: 7),
                      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
                        child: Text(price, maxLines: 1,
                          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
                            letterSpacing: -.3, fontFeatures: const [FontFeature.tabularFigures()]))),
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
