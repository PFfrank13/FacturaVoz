import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, ImageFilter, TimingsCallback;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Sistema de movimiento y tacto de FacturaVoz.
/// Todo respeta "Reducir animaciones" del sistema (MediaQuery.disableAnimations).

// ───────────────────────── Tacto ─────────────────────────

/// Vibraciones con intención: cada tipo de evento "se siente" distinto.
class Haptics {
  static void tap() => HapticFeedback.selectionClick();
  static void select() => HapticFeedback.selectionClick();
  static void soft() => HapticFeedback.lightImpact();
  static void heavy() => HapticFeedback.heavyImpact();

  /// Doble toque suave: algo salió bien.
  static Future<void> success() async {
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    HapticFeedback.selectionClick();
  }

  static void warning() => HapticFeedback.mediumImpact();

  static Future<void> error() async {
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    HapticFeedback.heavyImpact();
  }
}

bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

// ───────────────────────── Navegación ─────────────────────────

/// Ruta "premium": la pantalla nueva crece levemente desde el 94 % con fundido (eje Z),
/// la anterior se aleja. Mantiene las Hero animations.
class PremiumRoute<T> extends PageRouteBuilder<T> {
  PremiumRoute({required WidgetBuilder builder, super.fullscreenDialog})
      : super(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            if (MediaQuery.of(context).disableAnimations) return child;
            final easing = CurveTween(curve: Curves.easeOutCubic);
            final a = animation.drive(easing);
            final s = secondary.drive(easing);
            return FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.86).animate(s),
              child: ScaleTransition(
                scale: Tween<double>(begin: 1, end: 0.99).animate(s),
                child: FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween<double>(begin: 0.985, end: 1).animate(a), child: child),
                ),
              ),
            );
          },
        );
}

Future<T?> pushPremium<T>(BuildContext context, Widget page) {
  final route = Theme.of(context).platform == TargetPlatform.iOS && !reduceMotion(context)
      ? CupertinoPageRoute<T>(builder: (_) => page)
      : PremiumRoute<T>(builder: (_) => page);
  return Navigator.of(context).push<T>(route);
}

/// Cambia de contenido con "fade through" (Material motion): sale con fundido, entra creciendo.
class FadeThrough extends StatelessWidget {
  const FadeThrough({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : Motion.medium,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, a) => still
          ? c
          : FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(a),
                child: c,
              ),
            ),
      child: child,
    );
  }
}

/// Respuesta táctil discreta para tarjetas y acciones, sin cambiar sus callbacks.
/// Se cancela al desplazarse para evitar que un scroll parezca una pulsación.
/// Sólo transforma la capa visual: no altera el tamaño, el hit testing ni la lógica.
class FvTactileScale extends StatefulWidget {
  const FvTactileScale({
    super.key,
    required this.child,
    this.pressedScale = 0.985,
    this.enabled = true,
  });

  final Widget child;
  final double pressedScale;
  final bool enabled;

  @override
  State<FvTactileScale> createState() => _FvTactileScaleState();
}

class _FvTactileScaleState extends State<FvTactileScale> {
  int? _pointer;
  Offset? _start;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _end(int pointer) {
    if (_pointer != pointer) return;
    _pointer = null;
    _start = null;
    _setPressed(false);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (event) {
          if (!widget.enabled || _pointer != null) return;
          _pointer = event.pointer;
          _start = event.position;
          _setPressed(true);
        },
        onPointerMove: (event) {
          if (_pointer != event.pointer) return;
          if (_start != null && (event.position - _start!).distance > 12) {
            _setPressed(false);
          }
        },
        onPointerUp: (event) => _end(event.pointer),
        onPointerCancel: (event) => _end(event.pointer),
        child: AnimatedScale(
          scale: widget.enabled && !reduceMotion(context) && _pressed
              ? widget.pressedScale : 1,
          duration: Motion.d(context, _pressed ? Motion.instant : Motion.fast),
          curve: _pressed ? Motion.enter : Motion.spring,
          child: widget.child,
        ),
      );
}

// ───────────────────────── Carga ─────────────────────────

/// Brillo que recorre el contenido (esqueletos de carga).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.35);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.transparent, base, Colors.transparent],
          stops: const [0.25, 0.5, 0.75],
          transform: _SlideGradient(_c.value),
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// Bloque gris redondeado para esqueletos.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 10, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

// ───────────────────────── Celebración ─────────────────────────

/// Check animado a pantalla completa (no bloquea): "listo", "cobrado", "aceptada".
void showSuccess(BuildContext context, String message, {IconData icon = Icons.check_rounded}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  Haptics.success();
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _SuccessToast(message: message, icon: icon, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _SuccessToast extends StatefulWidget {
  const _SuccessToast({required this.message, required this.icon, required this.onDone});
  final String message;
  final IconData icon;
  final VoidCallback onDone;

  @override
  State<_SuccessToast> createState() => _SuccessToastState();
}

class _SuccessToastState extends State<_SuccessToast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final inT = Curves.easeOutBack.transform((t / 0.28).clamp(0.0, 1.0));
          final outT = ((t - 0.78) / 0.22).clamp(0.0, 1.0);
          final check = Curves.easeOutCubic.transform(((t - 0.12) / 0.3).clamp(0.0, 1.0));
          return Center(
            child: Opacity(
              opacity: (1 - outT) * (t < 0.1 ? t / 0.1 : 1),
              child: Transform.scale(
                scale: 0.7 + 0.3 * inT - 0.08 * outT,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      width: 210,
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                      decoration: BoxDecoration(
                        color: Brand.lightInk.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: CustomPaint(painter: _CheckPainter(check), child: Center(child: Opacity(opacity: widget.icon == Icons.check_rounded ? 0 : check, child: Icon(widget.icon, color: Colors.white, size: 30)))),
                        ),
                        const SizedBox(height: 14),
                        Text(widget.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..shader = Brand.heroGradient.createShader(Offset.zero & size));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - 4), -math.pi / 2, 2 * math.pi * t, false, ring);
    final p1 = Offset(size.width * 0.30, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.66);
    final p3 = Offset(size.width * 0.72, size.height * 0.38);
    final path = Path()..moveTo(p1.dx, p1.dy);
    final first = (t / 0.45).clamp(0.0, 1.0);
    path.lineTo(p1.dx + (p2.dx - p1.dx) * first, p1.dy + (p2.dy - p1.dy) * first);
    if (t > 0.45) {
      final second = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
      path.lineTo(p2.dx + (p3.dx - p2.dx) * second, p2.dy + (p3.dy - p2.dy) * second);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

// ───────────────────────── Piezas de tablero ─────────────────────────

/// Punto "en vivo" que late.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.color = Brand.ok, this.size = 8});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          if (!reduceMotion(context))
            Container(
              width: s + s * 1.4 * _c.value,
              height: s + s * 1.4 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
          Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
        ]),
      ),
    );
  }
}

/// Anillo de progreso animado (margen, avance de cobro…). [value] entre 0 y 1.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 84, this.stroke = 10, this.color, this.child});
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, c, t.colorScheme.surfaceContainerHighest, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    if (v <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [color.withValues(alpha: 0.55), color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Barras dobles por periodo (p. ej. ingresos vs. gastos por mes) que crecen al aparecer.
class DualBars extends StatelessWidget {
  const DualBars({super.key, required this.labels, required this.a, required this.b, this.height = 150, this.aColor, this.bColor});
  final List<String> labels;
  final List<double> a;
  final List<double> b;
  final double height;
  final Color? aColor;
  final Color? bColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ca = aColor ?? t.colorScheme.primary;
    final cb = bColor ?? Brand.gold;
    final maxV = [...a, ...b, 1.0].reduce(math.max);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, k, _) => SizedBox(
        height: height + 22,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _bar(height * (a[i] / maxV) * k, ca),
                  const SizedBox(width: 3),
                  _bar(height * (b[i] / maxV) * k, cb),
                ]),
                const SizedBox(height: 6),
                Text(labels[i], style: t.textTheme.labelSmall),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _bar(double h, Color c) => Container(
        width: 11,
        height: math.max(h, 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [c.withValues(alpha: 0.65), c]),
        ),
      );
}

/// Barra segmentada (antigüedad de deudas, gastos por categoría…).
class SegmentBar extends StatelessWidget {
  const SegmentBar({super.key, required this.values, required this.colors, this.height = 12});
  final List<double> values;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (s, v) => s + v);
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, k, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: total <= 0
              ? ColoredBox(color: track)
              : Row(children: [
                  for (var i = 0; i < values.length; i++)
                    if (values[i] > 0)
                      Expanded(
                        flex: math.max(1, (values[i] / total * 1000 * k).round()),
                        child: Container(color: colors[i % colors.length], margin: const EdgeInsets.only(right: 2)),
                      ),
                  if (k < 1) Expanded(flex: math.max(1, ((1 - k) * 1000).round()), child: ColoredBox(color: track)),
                ]),
        ),
      ),
    );
  }
}

/// Indicador de tablero: icono, etiqueta, cifra y variación.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.icon, required this.label, required this.value, this.delta, this.deltaGood = true, this.color});
  final IconData icon;
  final String label;
  final String value;

  /// Texto como "+12 %" (null = sin comparación). [deltaGood] decide si se pinta verde o rojo.
  final String? delta;
  final bool deltaGood;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    final dark = t.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.colorScheme.surface, borderRadius: BorderRadius.circular(22), boxShadow: Brand.softShadow(dark, a: 0.06)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 19, color: c),
          ),
          const Spacer(),
          if (delta != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: (deltaGood ? Brand.ok : Brand.bad).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
              child: Text(delta!, style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: deltaGood ? Brand.ok : Brand.bad)),
            ),
        ]),
        const SizedBox(height: 12),
        Text(label, style: t.textTheme.bodySmall),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: t.colorScheme.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}

/// Título de sección con acción opcional a la derecha.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(children: [
        Expanded(child: Text(text, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

/// Orbe de IA que "respira" y reacciona al nivel de voz ([level] 0..1).
class AiOrb extends StatefulWidget {
  const AiOrb({super.key, this.size = 150, this.level = 0, this.active = false, this.thinking = false});
  final double size;
  final double level;
  final bool active;
  final bool thinking;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _OrbPainter(still ? 0 : _c.value, widget.level, widget.active, widget.thinking),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t, this.level, this.active, this.thinking);
  final double t;
  final double level;
  final bool active;
  final bool thinking;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width * 0.32;
    final breathe = math.sin(t * 2 * math.pi) * 0.04;
    final r = base * (1 + breathe + (active ? level * 0.35 : 0));
    // halo
    canvas.drawCircle(
      c,
      r * 1.55,
      Paint()
        ..shader = RadialGradient(colors: [
          (active ? Brand.goldDeep : Brand.lilac).withValues(alpha: 0.30),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r * 1.55)),
    );
    // tres lóbulos que giran (sensación de "vida")
    for (var i = 0; i < 3; i++) {
      final ang = t * 2 * math.pi * (thinking ? 3 : 1) + i * 2 * math.pi / 3;
      final off = Offset(math.cos(ang), math.sin(ang)) * r * 0.18;
      final colors = [
        [Brand.indigo, Brand.lilac],
        [Brand.lilac, const Color(0xFFB58BF5)],
        [Brand.gold, Brand.goldDeep],
      ][i];
      canvas.drawCircle(
        c + off,
        r * 0.92,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..shader = LinearGradient(colors: [colors[0].withValues(alpha: 0.85), colors[1].withValues(alpha: 0.75)])
              .createShader(Rect.fromCircle(center: c + off, radius: r)),
      );
    }
    // brillo
    canvas.drawCircle(
      c - Offset(r * 0.3, r * 0.35),
      r * 0.35,
      Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.55), Colors.transparent]).createShader(Rect.fromCircle(center: c - Offset(r * 0.3, r * 0.35), radius: r * 0.35)),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t || old.level != level || old.active != active || old.thinking != thinking;
}

/// Ejecuta [fn] como mucho una vez cada [ms] (evita dobles toques).
class Throttle {
  Throttle([this.ms = 600]);
  final int ms;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  bool get ready {
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < ms) return false;
    _last = now;
    return true;
  }
}

/// Retraso cancelable reutilizable.
class Debouncer {
  Debouncer([this.ms = 350]);
  final int ms;
  Timer? _t;
  void call(VoidCallback fn) {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: ms), fn);
  }

  void dispose() => _t?.cancel();
}

// ───────────────────────── Fase "Revolución": piezas visuales ─────────────────────────

/// Fondo "aurora": tres manchas de luz que flotan muy despacio sobre un degradado.
/// Barato (un solo CustomPainter, sin blur en tiempo real) y se detiene con "Reducir animaciones".
class Aurora extends StatefulWidget {
  const Aurora({super.key, required this.child, this.gradient = Brand.heroGradient, this.borderRadius});
  final Widget child;
  final Gradient gradient;
  final BorderRadius? borderRadius;

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: widget.gradient),
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _AuroraPainter(still ? 0.15 : (_c.value * 150).floorToDouble() / 150)), // ~11 repintados/s: el movimiento es lento y así se ahorran cuadros
              ),
            ),
          ),
          widget.child,
        ]),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = [
      (const Color(0xFFFFB199), 0.75, 0.15, 0.55, 0.0),
      (const Color(0xFF8FE3FF), 0.15, 0.85, 0.50, 0.33),
      (const Color(0xFFE6B8FF), 0.95, 0.95, 0.45, 0.66),
    ];
    for (final (color, bx, by, r, phase) in blobs) {
      final a = 2 * math.pi * (t + phase);
      final c = Offset(size.width * (bx + 0.08 * math.cos(a)), size.height * (by + 0.10 * math.sin(a)));
      final radius = size.longestSide * r;
      canvas.drawCircle(
        c,
        radius,
        Paint()..shader = RadialGradient(colors: [color.withValues(alpha: 0.38), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

/// Línea de tendencia que se dibuja de izquierda a derecha, con relleno suave y punto final.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 44, this.color = Colors.white});
  final List<double> values;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, k, _) => SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, k, color))),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.k, this.color);
  final List<double> v;
  final double k;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = v.reduce(math.max);
    final minV = v.reduce(math.min);
    final span = (maxV - minV).abs() < 0.01 ? 1.0 : maxV - minV;
    Offset pt(int i) => Offset(size.width * i / (v.length - 1), size.height - 4 - (size.height - 8) * ((v[i] - minV) / span));
    final upto = ((v.length - 1) * k).clamp(0.0, (v.length - 1).toDouble());
    final last = upto.floor();
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i <= last; i++) {
      final p0 = pt(i - 1), p1 = pt(i);
      final mid = (p0.dx + p1.dx) / 2;
      line.cubicTo(mid, p0.dy, mid, p1.dy, p1.dx, p1.dy);
    }
    var end = pt(last);
    if (last < v.length - 1) {
      final f = upto - last;
      final a = pt(last), b = pt(last + 1);
      end = Offset(a.dx + (b.dx - a.dx) * f, a.dy + (b.dy - a.dy) * f);
      line.lineTo(end.dx, end.dy);
    }
    final fill = Path.from(line)
      ..lineTo(end.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)])
            .createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(end, 4.5, Paint()..color = color);
    canvas.drawCircle(end, 9, Paint()..color = color.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.k != k || old.v != v || old.color != color;
}

/// Acceso rápido: icono en degradado + texto, con rebote al tocar y número opcional (badge).
class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap, required this.colors, this.badge = 0});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final List<Color> colors;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge pendientes' : label,
      child: GestureDetector(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: _Springy(
          child: SizedBox(
            width: 76,
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                    boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Icon(icon, color: Colors.white, size: 27),
                ),
                if (badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      constraints: const BoxConstraints(minWidth: 20),
                      decoration: BoxDecoration(color: Brand.bad, borderRadius: BorderRadius.circular(99), border: Border.all(color: t.scaffoldBackgroundColor, width: 2)),
                      child: Text('$badge', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ]),
              const SizedBox(height: 7),
              // Una sola línea que se achica si no entra ("Escanear" ya no se parte ni se corta).
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false, textAlign: TextAlign.center, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Encoge al presionar y rebota al soltar (sin depender de un onTap propio).
class _Springy extends StatefulWidget {
  const _Springy({required this.child});
  final Widget child;

  @override
  State<_Springy> createState() => _SpringyState();
}

class _SpringyState extends State<_Springy> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: Duration(milliseconds: _down ? 90 : 450),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      );
}

/// Insignia de segmento/estado con icono (Clientes 360, recurrentes…).
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

// ═════════════════════════ v2.0 · Sistema central de movimiento ═════════════════════════
// Una sola fuente de duraciones, curvas y resortes: así toda la app "se mueve igual".
// Reglas (errores que ya tuvimos y no deben volver):
//  · Sombras y radios NUNCA con curvas que rebotan (easeOutBack/elastic dan valores negativos): usa Motion.shadow.
//  · Los rebotes solo en escalas (scale) y nunca por debajo de 0.
//  · Respeta "Reducir animaciones" del sistema y el interruptor de la app (reduceMotion(context)).
class _ControlSpring extends Curve {
  const _ControlSpring();

  static final _simulation = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 360, damping: 32), 0, 1, 0,
  );
  static const _settlingTime = 0.36;

  @override
  double transformInternal(double t) =>
      _simulation.x(t * _settlingTime) / _simulation.x(_settlingTime);
}

class Motion {
  static const instant = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);
  static const page = Duration(milliseconds: 420);
  static const count = Duration(milliseconds: 900);
  static const stagger = Duration(milliseconds: 55);

  static const standard = Curves.easeOutCubic;
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;

  /// Rebote suave para escalas (botones, chips). NO usar en sombras ni tamaños que puedan quedar negativos.
  static const Curve spring = _ControlSpring();

  /// Para sombras, radios y opacidades: sin rebote.
  static const shadow = Curves.easeOutCubic;

  static Duration d(BuildContext context, Duration base) => reduceMotion(context) ? Duration.zero : base;
}

/// Deslizar una fila para acciones rápidas (cobrar, WhatsApp, duplicar) con vibración al cruzar el umbral.
/// No borra la fila: al soltar ejecuta la acción y vuelve a su lugar.
class SwipeActions extends StatefulWidget {
  const SwipeActions({super.key, required this.child, this.left, this.right});
  final Widget child;

  /// Acción al deslizar hacia la DERECHA (aparece a la izquierda).
  final SwipeAction? left;

  /// Acción al deslizar hacia la IZQUIERDA (aparece a la derecha).
  final SwipeAction? right;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class SwipeAction {
  const SwipeAction({required this.icon, required this.label, required this.color, required this.onTrigger});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTrigger;
}

class _SwipeActionsState extends State<SwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this, duration: Motion.medium);
  double _dx = 0;
  double _from = 0;
  bool _armed = false;
  static const _threshold = 84.0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    if (_back.isAnimating) {
      _back.stop();
      _dx = 0;
    }
    var next = _dx + d.delta.dx;
    if (widget.left == null && next > 0) next = 0;
    if (widget.right == null && next < 0) next = 0;
    next = next.clamp(-140.0, 140.0);
    final armed = next.abs() >= _threshold;
    if (armed != _armed) {
      if (armed) Haptics.select();
      _armed = armed;
    }
    setState(() => _dx = next);
  }

  void _end(DragEndDetails _) {
    final action = _dx > 0 ? widget.left : widget.right;
    if (_armed && action != null) {
      Haptics.soft();
      action.onTrigger();
    }
    _armed = false;
    _from = _dx;
    _back.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _dx = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _back,
      builder: (context, child) {
        final x = _back.isAnimating ? _from * (1 - Motion.standard.transform(_back.value)) : _dx;
        final a = x > 0 ? widget.left : widget.right;
        final p = (x.abs() / _threshold).clamp(0.0, 1.0);
        return GestureDetector(
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          child: Stack(children: [
            if (a != null && x != 0)
              Positioned.fill(
                child: Container(
                  alignment: x > 0 ? Alignment.centerLeft : Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(color: a.color.withValues(alpha: 0.12 + 0.18 * p), borderRadius: BorderRadius.circular(24)),
                  child: Transform.scale(
                    scale: 0.8 + 0.25 * p,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(a.icon, color: a.color),
                      Text(a.label, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: a.color)),
                    ]),
                  ),
                ),
              ),
            Transform.translate(offset: Offset(x, 0), child: child),
          ]),
        );
      },
      child: widget.child,
    );
  }
}

/// Hace "vibrar" su contenido cuando [trigger] cambia (errores que se explican con movimiento, no con pantallas rojas).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && !reduceMotion(context)) {
      Haptics.warning();
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => Transform.translate(offset: Offset(math.sin(_c.value * math.pi * 6) * 8 * (1 - _c.value), 0), child: child),
      );
}

/// Onda de voz en vivo mientras se dicta ([level] 0..1 actualizado por el grabador).
class VoiceWave extends StatefulWidget {
  const VoiceWave({super.key, required this.level, this.active = true, this.color, this.height = 46, this.bars = 28});
  final double level;
  final bool active;
  final Color? color;
  final double height;
  final int bars;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    if (reduceMotion(context)) {
      return SizedBox(height: widget.height, child: Center(child: Container(height: 4 + widget.level * (widget.height - 4), width: 6, color: color)));
    }
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _WavePainter(_c.value, widget.active ? widget.level.clamp(0.0, 1.0) : 0, color, widget.bars), size: Size.infinite),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.level, this.color, this.bars);
  final double t;
  final double level;
  final Color color;
  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / (bars * 1.6);
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    for (var i = 0; i < bars; i++) {
      final phase = (i / bars) * math.pi * 2;
      final amp = 0.15 + 0.85 * level * (0.55 + 0.45 * math.sin(t * math.pi * 2 * 1.6 + phase * 1.7).abs());
      final h = math.max(3.0, size.height * amp);
      final x = (i + 0.5) * size.width / bars;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), p..color = color.withValues(alpha: 0.45 + 0.55 * amp));
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.level != level || old.color != color;
}

/// Cambio de estado visible (pendiente → cobrada): el contenido nuevo entra deslizando y con fundido.
class StatusMorph extends StatelessWidget {
  const StatusMorph({super.key, required this.status, required this.child});
  final String status;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.d(context, Motion.medium),
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c)),
        child: KeyedSubtree(key: ValueKey(status), child: child),
      );
}

/// Detecta teléfonos lentos midiendo los primeros cuadros: si van por encima de ~20 ms, reduce efectos solo.
class PerfGuard {
  PerfGuard._();
  static final ValueNotifier<bool> slowDevice = ValueNotifier(false);
  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    final samples = <int>[];
    late TimingsCallback cb;
    cb = (List<FrameTiming> timings) {
      for (final t in timings) {
        samples.add(t.totalSpan.inMicroseconds);
      }
      if (samples.length >= 180) {
        samples.sort();
        final p75 = samples[(samples.length * 0.75).floor()];
        if (p75 > 20000) slowDevice.value = true;
        WidgetsBinding.instance.removeTimingsCallback(cb);
      }
    };
    WidgetsBinding.instance.addTimingsCallback(cb);
  }
}

/// Preferencia de movimiento de la app: null = automático (sistema + teléfono lento), true = reducidas, false = completas.
/// main.dart la aplica a toda la app vía MediaQuery.disableAnimations, así cada widget solo pregunta reduceMotion(context).
class MotionPrefs {
  MotionPrefs._();
  static final ValueNotifier<bool?> userReduced = ValueNotifier(null);
  static Listenable get listenable => Listenable.merge([userReduced, PerfGuard.slowDevice]);
  static bool effective(bool system) {
    final u = userReduced.value;
    if (system || u == true) return true;
    if (u == false) return false;
    return PerfGuard.slowDevice.value;
  }
}
