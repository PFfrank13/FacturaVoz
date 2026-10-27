import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
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
  PremiumRoute({required WidgetBuilder builder, bool fullscreenDialog = false})
      : super(
          fullscreenDialog: fullscreenDialog,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            if (MediaQuery.of(context).disableAnimations) return child;
            final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            final s = CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.6).animate(s),
              child: ScaleTransition(
                scale: Tween<double>(begin: 1, end: 0.96).animate(s),
                child: FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(a), child: child),
                ),
              ),
            );
          },
        );
}

Future<T?> pushPremium<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(PremiumRoute<T>(builder: (_) => page));

/// Cambia de contenido con "fade through" (Material motion): sale con fundido, entra creciendo.
class FadeThrough extends StatelessWidget {
  const FadeThrough({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1).animate(a), child: c),
        ),
        child: child,
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

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
