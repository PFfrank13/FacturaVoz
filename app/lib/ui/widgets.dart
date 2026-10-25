import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Importe con cifras tabulares para que las columnas se alineen.
class Money extends StatelessWidget {
  const Money(this.text, {super.key, this.size = 15, this.weight = FontWeight.w600, this.color, this.align});
  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: weight,
          letterSpacing: size > 24 ? -size * 0.03 : 0,
          fontFeatures: _tabular,
          color: color ?? Theme.of(context).colorScheme.onSurface,
        ),
      );
}

enum PillTone { neutral, ok, warn, bad, info }

/// Estado como punto de color + texto: se lee sin depender solo del color.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = PillTone.neutral});
  final String label;
  final PillTone tone;

  static PillTone toneForFiscal(String? status) {
    switch (status) {
      case 'accepted':
        return PillTone.ok;
      case 'rejected':
        return PillTone.bad;
      case 'error':
      case 'pending':
        return PillTone.warn;
      default:
        return PillTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color c;
    switch (tone) {
      case PillTone.ok:
        c = dark ? const Color(0xFF4FD1A1) : Brand.ok;
      case PillTone.warn:
        c = dark ? const Color(0xFFFFB454) : Brand.warn;
      case PillTone.bad:
        c = dark ? const Color(0xFFFF8A7A) : Brand.bad;
      case PillTone.info:
        c = dark ? Brand.indigoSoft : Brand.indigo;
      case PillTone.neutral:
        c = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

/// Marca: micrófono blanco sobre degradado lavanda.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: Brand.heroGradient,
          borderRadius: BorderRadius.circular(size * 0.34),
          boxShadow: Brand.softShadow(false, a: 0.25),
        ),
        child: Icon(Icons.mic_rounded, color: Colors.white, size: size * 0.52),
      );
}

/// Botón de dictado: el momento central de la app. Los anillos solo se animan mientras graba.
class DictateButton extends StatefulWidget {
  const DictateButton({super.key, required this.onPressed, this.recording = false, this.busy = false, this.size = 84});
  final VoidCallback? onPressed;
  final bool recording;
  final bool busy;
  final double size;

  @override
  State<DictateButton> createState() => _DictateButtonState();
}

class _DictateButtonState extends State<DictateButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didUpdateWidget(covariant DictateButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.recording && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.recording) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      label: widget.recording ? 'Detener grabación' : 'Dictar factura',
      child: SizedBox(
        width: s * 1.9,
        height: s * 1.9,
        child: Stack(alignment: Alignment.center, children: [
          if (widget.recording && !reduce)
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(size: Size(s * 1.9, s * 1.9), painter: _RingPainter(_c.value, s)),
            ),
          GestureDetector(
            onTap: widget.busy
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    widget.onPressed?.call();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.recording ? Brand.bad : null,
                gradient: widget.recording ? null : Brand.coralGradient,
                boxShadow: [
                  BoxShadow(
                    color: (widget.recording ? Brand.bad : Brand.goldDeep).withValues(alpha: 0.38),
                    blurRadius: 30,
                    spreadRadius: 1,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: widget.busy
                  ? const Padding(
                      padding: EdgeInsets.all(26),
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                    )
                  : Icon(widget.recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: s * 0.46, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.base);
  final double t;
  final double base;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final r = base / 2 + (size.width / 2 - base / 2) * p;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Brand.bad.withValues(alpha: 0.5 * (1 - p));
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t;
}

/// Papel de comprobante con borde inferior dentado: el detalle memorable de la app.
class TicketPaper extends StatelessWidget {
  const TicketPaper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipPath(
      clipper: const _ZigzagClipper(),
      child: Container(
        color: dark ? Brand.darkCard : Colors.white,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 34),
        child: child,
      ),
    );
  }
}

class _ZigzagClipper extends CustomClipper<Path> {
  const _ZigzagClipper();
  static const _tooth = 12.0;

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, 0)..lineTo(size.width, 0)..lineTo(size.width, size.height - _tooth);
    final n = (size.width / (_tooth * 1.6)).floor().clamp(4, 80);
    final w = size.width / n;
    for (var i = n; i > 0; i--) {
      path.lineTo(w * (i - 0.5), size.height);
      path.lineTo(w * (i - 1), size.height - _tooth);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

/// Fila de datos: etiqueta tenue a la izquierda, valor a la derecha.
class DataRow2 extends StatelessWidget {
  const DataRow2(this.label, this.value, {super.key, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        Money(value, size: strong ? 20 : 14.5, weight: strong ? FontWeight.w700 : FontWeight.w500),
      ]),
    );
  }
}

/// Estado vacío: dice qué hacer, no solo que no hay nada.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
      child: Column(children: [
        const BrandMark(size: 60),
        const SizedBox(height: 20),
        Text(title, textAlign: TextAlign.center, style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}


/// Entrada escalonada: aparece desde abajo con fundido. `index` define el retraso en cascada.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 18});
  final Widget child;
  final int index;
  final double dy;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  Timer? _t;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 60 * widget.index.clamp(0, 12));
    _t = Timer(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: a,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, (1 - a.value) * widget.dy), child: child),
      ),
    );
  }
}

/// Cifra que "cuenta" hasta su valor (se anima al cambiar).
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.builder});
  final double value;
  final Widget Function(BuildContext, double) builder;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (c, v, _) => builder(c, v),
    );
  }
}

/// Retroalimentación táctil: se encoge ligeramente al pulsar.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.scale = 0.97});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Tarjeta blanda con sombra difusa (reemplaza al borde duro).
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 24, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Brand.softShadow(dark, a: 0.07),
      ),
      child: child,
    );
  }
}
