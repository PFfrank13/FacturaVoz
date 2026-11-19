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
        color: theme.colorScheme.surface.withValues(alpha:
            contrast ? 1 : theme.brightness == Brightness.dark ? .67 : .70),
        border: Border(bottom: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .65),
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
    final initials = name.trim().split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty).take(2)
      .map((s) => s.substring(0, 1).toUpperCase()).join();
    final dark = t.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF242427), Color(0xFF343439)]
            : const [Color(0xFFF2F2F4), Color(0xFFE8E8EC)],
      )),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(initials.isEmpty ? '—' : initials,
          style: t.textTheme.headlineMedium?.copyWith(
            fontSize: 31, fontWeight: FontWeight.w600, letterSpacing: -1,
            color: t.colorScheme.onSurface.withValues(alpha: .72))),
        if (category != null && category!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 5, right: 5, top: 4),
            child: Text(category!, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(
                fontSize: 10, color: t.colorScheme.onSurfaceVariant))),
      ])),
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
