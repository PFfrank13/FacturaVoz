import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';

/// FacturaVoz Liquid Glass.
///
/// A Flutter material, not UIKit's: the backdrop is blurred *and* saturated
/// (what makes Apple's glass look vivid instead of milky), lit by a specular
/// sheen from the upper left, and outlined by a rim whose brightness changes
/// around the edge like light refracting through a thick, rounded pane.
///
/// It renders on every phone (Impeller and Skia, iOS, Android and web). With
/// high contrast it becomes an opaque surface with a plain outline.
class FvLiquidGlass extends StatelessWidget {
  const FvLiquidGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.blur = 22,
    this.tint,
    this.strength = 1,
    this.shadow = true,
    this.borderRadius,
    this.tone,
  });

  final Widget child;
  final double radius;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  /// Backdrop blur. Use 0 over the aurora alone, where blurring a smooth field
  /// changes nothing and only costs frames; keep it where content scrolls under.
  final double blur;

  /// Optional color that glows from the upper-left corner, e.g. a module color.
  final Color? tint;

  /// Scales the tint fill: 1 is the standard pane, higher is denser.
  final double strength;
  final bool shadow;

  /// Forces a light or dark pane regardless of the app theme.
  final Brightness? tone;

  static double sigmaFor(double requested) =>
      requested.clamp(0.0, kIsWeb ? 14.0 : 16.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = (tone ?? theme.brightness) == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final shape = borderRadius ?? BorderRadius.circular(radius);
    if (contrast) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: shape,
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Padding(padding: padding, child: child),
      );
    }
    // Rendimiento: dentro de una lista que se desplaza, el desenfoque en vivo (BackdropFilter) se recalcula
    // en cada cuadro por cada tarjeta y hace sentir pesada la app. Ahí se usa vidrio esmerilado: el mismo
    // panel, más denso y sin desenfoque. Las barras fijas (arriba, abajo, menú) mantienen el desenfoque real.
    final inScroll = Scrollable.maybeOf(context) != null;
    final a = (inScroll ? strength * 1.9 : strength).clamp(.4, 3.0);
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  const Color(0xFF1B2B44).withValues(alpha: (.42 * a).clamp(0.0, 1.0)),
                  const Color(0xFF0B1424).withValues(alpha: (.30 * a).clamp(0.0, 1.0)),
                ]
              : [
                  Colors.white.withValues(alpha: (.46 * a).clamp(0.0, 1.0)),
                  Colors.white.withValues(alpha: (.20 * a).clamp(0.0, 1.0)),
                ],
        ),
      ),
      child: CustomPaint(
        painter: tint == null ? null : _TintGlow(tint!, dark),
        foregroundPainter: _GlassOptics(shape, dark),
        child: Padding(padding: padding, child: child),
      ),
    );
    final sigma = inScroll ? 0.0 : sigmaFor(blur);
    final glass = ClipRRect(
      borderRadius: shape,
      child: sigma == 0
          ? pane
          : BackdropFilter(
              filter: ImageFilter.compose(
                outer: _saturate(dark ? 1.5 : 1.8),
                inner: ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode: TileMode.mirror,
                ),
              ),
              child: pane,
            ),
    );
    if (!shadow) return glass;
    // The pane is translucent, so a regular BoxShadow would show through it as
    // a dark slab. The shadow is painted only outside the shape.
    return CustomPaint(
      painter: _OuterShadow(shape, dark, tint),
      child: glass,
    );
  }
}

class _OuterShadow extends CustomPainter {
  const _OuterShadow(this.shape, this.dark, this.tint);
  final BorderRadius shape;
  final bool dark;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = shape.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipPath(Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(80)),
      Path()..addRRect(rrect),
    ));
    void cast(Color color, double blur, double dy, double spread) =>
        canvas.drawRRect(
          rrect.shift(Offset(0, dy)).inflate(spread),
          Paint()
            ..color = color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
        );
    cast(dark ? const Color(0x99000000) : const Color(0x2B1B3550), 18, 12, -4);
    cast(dark ? const Color(0x4D000000) : const Color(0x141B3550), 4, 2, 0);
    if (tint != null) cast(tint!.withValues(alpha: dark ? .30 : .22), 22, 10, -6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) =>
      old.shape != shape || old.dark != dark || old.tint != tint;
}

ColorFilter _saturate(double s) {
  const r = .2126, g = .7152, b = .0722;
  final i = 1 - s;
  return ColorFilter.matrix([
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}

class _TintGlow extends CustomPainter {
  const _TintGlow(this.tint, this.dark);
  final Color tint;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-1, -1),
          radius: 1.35,
          colors: [
            tint.withValues(alpha: dark ? .34 : .26),
            tint.withValues(alpha: 0),
          ],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_TintGlow old) => old.tint != tint || old.dark != dark;
}

/// Specular sheen, refracting rim and inner thickness.
class _GlassOptics extends CustomPainter {
  const _GlassOptics(this.shape, this.dark);
  final BorderRadius shape;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final rrect = shape.toRRect(bounds);
    canvas.save();
    canvas.clipRRect(rrect);
    // Sheen: a soft band of light across the top, strongest at the left.
    final sheen = Rect.fromLTWH(0, 0, size.width, math.min(size.height, 64));
    canvas.drawRect(
      sheen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: dark ? .12 : .42),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(sheen),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.85, -1.05),
          radius: .9,
          colors: [
            Colors.white.withValues(alpha: dark ? .10 : .30),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    // Inner thickness: a darker lip along the lower edge.
    canvas.drawRRect(
      rrect.deflate(1.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.transparent,
            (dark ? Colors.black : const Color(0xFF29496A))
                .withValues(alpha: dark ? .35 : .10),
          ],
          stops: const [0, .6, 1],
        ).createShader(bounds),
    );
    canvas.restore();
    // Rim: bright where light enters (upper left) and exits (lower right),
    // nearly clear on the sides, like a refracting rounded edge.
    canvas.drawRRect(
      rrect.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: dark
              ? const [
                  Color(0x66FFFFFF), // right
                  Color(0x33FFFFFF), // bottom-right
                  Color(0x14FFFFFF), // bottom
                  Color(0x1FFFFFFF), // left-bottom
                  Color(0xB3FFFFFF), // upper-left
                  Color(0x40FFFFFF), // top
                  Color(0x66FFFFFF),
                ]
              : const [
                  Color(0xCCFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x80FFFFFF),
                  Color(0x99FFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xE6FFFFFF),
                  Color(0xCCFFFFFF),
                ],
          stops: const [0, .12, .3, .55, .66, .82, 1],
        ).createShader(bounds),
    );
    if (!dark) {
      // A faint cool outline keeps white glass legible on pale backgrounds.
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = const Color(0x1F2B4A6B),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassOptics old) =>
      old.shape != shape || old.dark != dark;
}

/// The colored field behind the glass. Large, soft light sources (jade, ice
/// blue, turquoise and a warm coral) give the panes something to refract. It
/// drifts with [scroll] for parallax, without running a ticker of its own.
class FvAurora extends StatelessWidget {
  const FvAurora({super.key, this.scroll, this.child});
  final ValueListenable<double>? scroll;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final base = dark ? const Color(0xFF050A13) : const Color(0xFFF2F6FB);
    if (contrast) return ColoredBox(color: base, child: child);
    final listenable = scroll ?? const _Still();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(dark, listenable),
        child: child,
      ),
    );
  }
}

class _Still extends ValueListenable<double> {
  const _Still();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  double get value => 0;
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.dark, this.scroll) : super(repaint: scroll);
  final bool dark;
  final ValueListenable<double> scroll;

  static const _darkLights = [
    // (x, y, radius in widths, color, alpha)
    (-.05, .02, .95, Color(0xFF13D6A0), .42),
    (1.05, .18, .85, Color(0xFF3D8BFF), .38),
    (.45, .55, .80, Color(0xFF19C6E6), .20),
    (1.0, .86, .80, Color(0xFFFF7A59), .24),
    (-.1, 1.0, .85, Color(0xFF7B61FF), .22),
  ];
  static const _lightLights = [
    (-.05, .0, .95, Color(0xFF7FF0C8), .65),
    (1.05, .16, .85, Color(0xFF9CC8FF), .70),
    (.5, .55, .8, Color(0xFF8FE7F5), .40),
    (1.0, .88, .8, Color(0xFFFFBE98), .55),
    (-.1, 1.0, .85, Color(0xFFCFC2FF), .50),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF07101E), Color(0xFF050A13), Color(0xFF080A16)]
              : const [Color(0xFFF4F9FC), Color(0xFFF2F6FB), Color(0xFFF7F4FA)],
        ).createShader(rect),
    );
    // Light sources sit at fixed positions within one screen-height and slide
    // a fraction of the scroll, so the glass above them shifts color as you go.
    final drift = -(scroll.value * .18) % (size.height * 2);
    for (final (x, y, r, color, alpha) in dark ? _darkLights : _lightLights) {
      final center = Offset(
        x * size.width,
        ((y * size.height + drift) % (size.height * 1.4)) - size.height * .1,
      );
      final radius = r * math.max(size.width, 360.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.dark != dark || old.scroll != scroll;
}
