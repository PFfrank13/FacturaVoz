import 'package:flutter/material.dart';
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

/// A lit product well: a soft key light from above, a cool rim from the side
/// and a contact shadow, so cut-out product photos sit on a surface.
class FvProductStudio extends StatelessWidget {
  const FvProductStudio({super.key, required this.child, this.radius = 18});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: contrast ? null : _StudioLight(dark),
        child: child,
      ),
    );
  }
}

class _StudioLight extends CustomPainter {
  const _StudioLight(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: dark
          ? const [Color(0xFF203552), Color(0xFF111D31)]
          : const [Color(0xFFFFFFFF), Color(0xFFE5EEF7)],
    ).createShader(r));
    canvas.drawRect(r, Paint()..shader = RadialGradient(
      center: const Alignment(0, -1.1), radius: 1.05,
      colors: [Colors.white.withValues(alpha: dark ? .20 : .95), Colors.white.withValues(alpha: 0)],
    ).createShader(r));
    canvas.drawRect(r, Paint()..shader = RadialGradient(
      center: const Alignment(1.2, .3), radius: .9,
      colors: [const Color(0xFF5BD5FF).withValues(alpha: dark ? .16 : .14), const Color(0x005BD5FF)],
    ).createShader(r));
    // Contact shadow where products rest.
    final floor = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .86),
      width: size.width * .62, height: size.height * .09);
    canvas.drawOval(floor, Paint()
      ..color = Colors.black.withValues(alpha: dark ? .45 : .16)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * .035));
  }

  @override
  bool shouldRepaint(_StudioLight old) => old.dark != dark;
}

/// Visual for products whose owners have not uploaded a photo: a monogram
/// with a gradient fill and the category, sitting in the studio light.
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
    return Semantics(
      image: true, excludeSemantics: true, label: 'Producto sin fotografía: $name',
      child: CustomPaint(
        painter: contrast ? null : _MonogramGlow(palette.$1, dark),
        child: LayoutBuilder(builder: (context, size) {
          final showLabel = size.maxWidth >= 100 && size.maxHeight >= 100 &&
              group != null && group.isNotEmpty && MediaQuery.textScalerOf(context).scale(14) <= 22;
          final mark = initials.isEmpty
              ? Icon(icon ?? Icons.inventory_2_outlined, size: 44, color: Colors.white)
              : Text(initials, style: const TextStyle(fontFamily: 'Inter',
                  fontSize: 44, height: 1.05, letterSpacing: -2, fontWeight: FontWeight.w800,
                  color: Colors.white));
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: contrast
                  ? DefaultTextStyle.merge(style: TextStyle(color: scheme.onSurface), child: mark)
                  : ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (r) => LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [palette.$1, palette.$2],
                      ).createShader(r),
                      child: mark))),
              if (showLabel) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(group.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: dark ? const Color(0xFFB9C8DA) : const Color(0xFF52627A),
                    letterSpacing: 1.1, fontWeight: FontWeight.w700, fontSize: 10)),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

// (light, deep) gradient pairs per category.
const _catalogInks = [
  (Color(0xFF3EE6B0), Color(0xFF0E8C7A)),
  (Color(0xFF7CC8FF), Color(0xFF3B5BDB)),
  (Color(0xFFFFA48A), Color(0xFFE0457B)),
  (Color(0xFFFFD36E), Color(0xFFE07B24)),
  (Color(0xFFC3A6FF), Color(0xFF6D4AE0)),
];

class _MonogramGlow extends CustomPainter {
  const _MonogramGlow(this.color, this.dark);
  final Color color;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = RadialGradient(
      radius: .55,
      colors: [color.withValues(alpha: dark ? .30 : .26), color.withValues(alpha: 0)],
    ).createShader(r));
  }
  @override
  bool shouldRepaint(_MonogramGlow old) => old.color != color || old.dark != dark;
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
