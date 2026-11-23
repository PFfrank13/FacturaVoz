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
    final isSelected = quantity != null;
    final disabled = soldOut && !isSelected;
    final accent = dark ? FvTokens.emeraldDark : FvLuxe.jade;
    final still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      container: true,
      label: '$name, $price, ${stockLabel ?? 'stock no indicado'}',
      child: FvTactileScale(
        enabled: !disabled,
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: isSelected ? [
              BoxShadow(color: accent.withValues(alpha: .38), blurRadius: 22, spreadRadius: -4),
            ] : const [],
          ),
          child: FvLiquidGlass(
            radius: 26,
            blur: 0,
            strength: dark ? 1.5 : 1.4,
            tint: isSelected ? accent : null,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: disabled ? null : onAdd,
                onLongPress: onRemove,
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: Stack(children: [
                        Positioned.fill(
                          child: FvProductStudio(
                            radius: 19,
                            child: Opacity(
                              opacity: disabled ? .45 : 1,
                              child: photo ?? FvProductPhotoFallback(name: name, category: category, icon: icon),
                            ),
                          ),
                        ),
                        if (stockLabel != null)
                          Positioned(
                            left: 7, top: 7,
                            child: FvLiquidGlass(
                              radius: 99, blur: 12, shadow: false, strength: 1.6,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Text(stockLabel!, maxLines: 1,
                                  style: t.textTheme.labelSmall?.copyWith(
                                    fontSize: 10.5,
                                    color: soldOut ? t.colorScheme.error : t.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        Positioned(right: 7, top: 7,
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
                                  gradient: LinearGradient(colors: [
                                    Color.lerp(accent, Colors.white, .2)!, accent]),
                                  borderRadius: BorderRadius.circular(99),
                                  boxShadow: [BoxShadow(color: accent.withValues(alpha: .5), blurRadius: 10)],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  child: FvQuantityText(quantity!,
                                    style: TextStyle(
                                      color: dark ? FvTokens.canvasDark : Colors.white,
                                      fontSize: 11.5, fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(right: 4, bottom: 4, child: SizedBox.square(
                          dimension: 44,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: disabled ? null : [
                                BoxShadow(color: accent.withValues(alpha: .55), blurRadius: 14, offset: const Offset(0, 5)),
                              ],
                            ),
                            child: IconButton.filled(
                              tooltip: 'Añadir $name',
                              onPressed: disabled ? null : onAdd,
                              icon: const Icon(Icons.add_rounded, size: 24),
                              style: IconButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: dark ? FvTokens.canvasDark : Colors.white,
                                disabledBackgroundColor: t.disabledColor.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        )),
                      ])),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelLarge?.copyWith(
                              color: t.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            )),
                          const SizedBox(height: 5),
                          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
                            child: Text(price, maxLines: 1,
                              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800,
                                fontFamily: 'Inter', letterSpacing: -.6,
                                fontFeatures: const [FontFeature.tabularFigures()]))),
                        ]),
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
