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
      filter: ImageFilter.blur(sigmaX: FvLuxe.glassSigma(theme.platform, 18),
          sigmaY: FvLuxe.glassSigma(theme.platform, 18)),
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
  const FvProductPhotoFallback({super.key, required this.name, this.category, this.icon});
  final String name;
  final String? category;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty)
        .take(2).map((part) => part.characters.first.toUpperCase()).join();
    return Semantics(image: true, excludeSemantics: true,
      label: 'Producto sin fotografía: $name',
      child: ColoredBox(color: scheme.surfaceContainerHighest,
        child: CustomPaint(painter: FvEngraving(scheme.primary.withValues(alpha: .10)),
          child: LayoutBuilder(builder: (context, size) {
            final showLabel = size.maxWidth >= 100 && size.maxHeight >= 100 &&
                category?.isNotEmpty == true && MediaQuery.textScalerOf(context).scale(14) <= 22;
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: initials.isEmpty
                  ? Icon(icon ?? Icons.inventory_2_outlined, color: scheme.primary)
                  : Text(initials, style: TextStyle(fontFamily: FvLuxe.editorialFont,
                      fontSize: 37, color: scheme.primary)))),
              if (showLabel) Text(category!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall),
            ]));
          }))),
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
