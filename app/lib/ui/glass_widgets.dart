import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'motion.dart';

/// Glass belongs to navigation, not the merchandise grid.
class FvGlassTopBar extends StatelessWidget {
  const FvGlassTopBar({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contrast = MediaQuery.highContrastOf(context);
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: contrast
            ? [theme.colorScheme.surface, theme.colorScheme.surface]
            : theme.brightness == Brightness.dark
                ? const [Color(0xDE1D3343), Color(0xD21B293D)]
                : const [Color(0xE8FFFFFF), Color(0xC4E6F4F5)],
        ),
        border: Border(bottom: BorderSide(
          color: theme.brightness == Brightness.dark
            ? const Color(0xFF3C596B).withValues(alpha: .65)
            : Colors.white.withValues(alpha: .94),
          width: .5,
        )),
      ),
      child: const SizedBox.expand(),
    );
    return contrast ? pane : ClipRect(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: pane,
    ));
  }
}

/// One floating navigation dock, with a bounded 20px blur.
class FvFloatingGlassDock extends StatelessWidget {
  const FvFloatingGlassDock({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => FvGlassSurface(
    blur: 20, radius: FvTokens.sheetRadius, child: child,
  );
}

/// Typographic visual for products whose owners have not uploaded a photo.
class FvProductPhotoFallback extends StatelessWidget {
  const FvProductPhotoFallback({super.key, required this.name, this.category});
  final String name;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final descriptor = '$name ${category ?? ''}'.toLowerCase();
    final pictogram = descriptor.contains('agua') || descriptor.contains('bebida')
        ? Icons.water_drop_outlined
        : descriptor.contains('leche') || descriptor.contains('lácteo')
            ? Icons.local_drink_outlined
            : descriptor.contains('pan') || descriptor.contains('galleta')
                ? Icons.bakery_dining_outlined
                : descriptor.contains('arroz') || descriptor.contains('abarrote')
                    ? Icons.shopping_basket_outlined
                    : Icons.inventory_2_outlined;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: FvLuxe.productBackdrop(t.brightness)),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 95 || constraints.maxHeight < 94;
        return Semantics(
          label: 'Producto sin fotografía: $name',
          image: true,
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pictogram, size: compact ? 27 : 38,
                color: t.colorScheme.primary),
              if (!compact && category != null && category!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 6, top: 6),
                  child: Text(category!,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant))),
            ],
          )),
        );
      }),
    );
  }
}

/// Demo photographs can fail offline; the UI degrades to typography.
class FvNetworkProductPhoto extends StatelessWidget {
  const FvNetworkProductPhoto({
    super.key, required this.url, required this.name, this.category});
  final String url, name;
  final String? category;
  @override
  Widget build(BuildContext context) => Image.network(
    url, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Fotografía ilustrativa de $name',
    errorBuilder: (_, __, ___) =>
      FvProductPhotoFallback(name: name, category: category),
    loadingBuilder: (context, child, progress) => progress == null
        ? child : Shimmer(child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const SizedBox.expand())),
  );
}
