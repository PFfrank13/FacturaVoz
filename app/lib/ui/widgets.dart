import 'package:flutter/material.dart';

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

/// Marca: micrófono dorado dentro de un sello índigo.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.indigo, Brand.indigoDeep]),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Icon(Icons.mic_rounded, color: Brand.gold, size: size * 0.52),
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
            onTap: widget.busy ? null : widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.recording ? Brand.bad : Brand.gold,
                boxShadow: [
                  BoxShadow(
                    color: (widget.recording ? Brand.bad : Brand.gold).withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: widget.busy
                  ? const Padding(
                      padding: EdgeInsets.all(26),
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2A1D00)),
                    )
                  : Icon(widget.recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: s * 0.46, color: widget.recording ? Colors.white : const Color(0xFF2A1D00)),
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
