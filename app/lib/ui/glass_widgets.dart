import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'liquid_glass.dart';
export 'liquid_glass.dart';
import 'motion.dart';

/// Liquid glass across the status strip and toolbar.
class FvGlassTopBar extends StatelessWidget {
  const FvGlassTopBar({super.key});

  @override
  Widget build(BuildContext context) => const FvLiquidGlass(
    borderRadius: BorderRadius.zero,
    shadow: false,
    blur: 24,
    strength: 1.25,
    child: SizedBox.expand(),
  );
}

/// A single optical surface shared by the floating dock and the wide-screen rail.
class FvFloatingGlassDock extends StatelessWidget {
  const FvFloatingGlassDock({super.key, required this.child, this.radius = 34});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => FvLiquidGlass(
    radius: radius,
    blur: 24,
    strength: 1.15,
    child: child,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initials = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty)
        .take(2).map((part) => part.characters.first.toUpperCase()).join();
    final group = category?.trim();
    final seed = (group == null || group.isEmpty ? name : group).toLowerCase();
    // Keep each category recognisable as the list is filtered or reordered.
    final palette = _catalogInks[seed.runes.fold<int>(0, (hash, rune) => (hash * 31 + rune) % 997) % _catalogInks.length];
    final contrast = MediaQuery.highContrastOf(context);
    final dark = theme.brightness == Brightness.dark;
    final paper = contrast ? scheme.surface : dark ? palette.dark : palette.paper;
    final ink = contrast ? scheme.onSurface : dark ? palette.paper : palette.dark;
    return Semantics(
      image: true, excludeSemantics: true, label: 'Producto sin fotografía: $name',
      child: ColoredBox(color: paper, child: LayoutBuilder(builder: (context, size) {
        final showLabel = size.maxWidth >= 100 && size.maxHeight >= 100 &&
            group != null && group.isNotEmpty && MediaQuery.textScalerOf(context).scale(14) <= 22;
        return Stack(alignment: Alignment.center, fit: StackFit.expand, children: [
          if (!contrast) CustomPaint(painter: _CatalogCorner(ink.withValues(alpha: dark ? .14 : .10))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: initials.isEmpty
                  ? Icon(icon ?? Icons.inventory_2_outlined, color: ink)
                  : Text(initials, style: TextStyle(fontFamily: FvLuxe.editorialFont,
                      fontSize: 37, height: 1.1, letterSpacing: -1.2, color: ink)))),
              if (showLabel) Text(group, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: ink)),
            ]),
          ),
        ]);
      })),
    );
  }
}

const _catalogInks = [
  (paper: Color(0xFFCAF1E4), dark: Color(0xFF154C46)),
  (paper: Color(0xFFD5E2FF), dark: Color(0xFF253F73)),
  (paper: Color(0xFFFFDBCF), dark: Color(0xFF733E39)),
  (paper: Color(0xFFEDE8B6), dark: Color(0xFF444D26)),
];

class _CatalogCorner extends CustomPainter {
  const _CatalogCorner(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final corner = size.shortestSide * .40;
    final mark = Path()..moveTo(size.width - corner, 0)..lineTo(size.width, 0)
        ..lineTo(size.width, corner)..close();
    canvas.drawPath(mark, Paint()..color = color);
  }
  @override
  bool shouldRepaint(_CatalogCorner oldDelegate) => color != oldDelegate.color;
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
