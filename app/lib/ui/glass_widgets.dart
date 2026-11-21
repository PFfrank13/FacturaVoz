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
    final dark = theme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        color: contrast ? theme.colorScheme.surface : null,
        gradient: contrast ? null : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xE719393C), Color(0xE01C2B35), Color(0xD52B313B)]
              : const [Color(0xDBDAF3EB), Color(0xC7F8FBFA), Color(0xDCECEAF4)],
          stops: const [0, .56, 1],
        ),
        border: Border(
          bottom: BorderSide(
            color: contrast ? theme.colorScheme.outline :
                dark ? const Color(0x598FBFBA) : const Color(0x3D61958B),
            width: contrast ? 1 : .8,
          ),
        ),
      ),
      child: const SizedBox.expand(),
    );
    final sigma = FvLuxe.glassSigma(theme.platform, 16);
    return contrast ? pane : ClipRect(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: pane,
    ));
  }
}

/// One frosted pane with a polished rim lets the page move beneath the lighting.
class FvFloatingGlassDock extends StatelessWidget {
  const FvFloatingGlassDock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    const radius = 34.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: contrast ? null : [
          BoxShadow(
            color: dark ? const Color(0x66030F13) : const Color(0x30244943),
            offset: const Offset(0, 5),
            blurRadius: 14,
            spreadRadius: -3,
          ),
        ],
      ),
      child: FvGlassSurface(
        radius: radius,
        blur: 18,
        child: CustomPaint(
          foregroundPainter: contrast ? null : _DockEdge(dark),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: contrast ? theme.colorScheme.surface : null,
              borderRadius: BorderRadius.circular(radius),
              border: contrast ? Border.all(color: theme.colorScheme.outline) : null,
              gradient: contrast ? null : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xA62C4546), Color(0x8817242D), Color(0xA62A3144)]
                    : const [Color(0x90EBFAF2), Color(0x54FFFFFF), Color(0x8FDFEBEF)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DockEdge extends CustomPainter {
  const _DockEdge(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final rim = RRect.fromRectAndRadius(bounds.deflate(.9), const Radius.circular(33));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .30, .62, .84, 1],
        colors: dark
            ? const [Color(0xC4D7FFF2), Color(0x40579D91), Color(0x244F6476), Color(0x9CB9D7EF), Color(0x6265788A)]
            : const [Colors.white, Color(0xFFFAFFFC), Color(0x5778A6A0), Color(0xCCCFE5FC), Colors.white],
      ).createShader(bounds);
    canvas.drawRRect(rim, edge);
  }

  @override
  bool shouldRepaint(_DockEdge oldDelegate) => dark != oldDelegate.dark;
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
