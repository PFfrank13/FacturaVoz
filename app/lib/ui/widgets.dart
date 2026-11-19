import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'theme.dart';
import 'design_tokens.dart';

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

/// Identidad visual de FacturaVoz. Ícono propio en PNG, con forma reconocible también a 44 px.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .29),
        child: Image.asset('assets/branding/facturavoz_icon.png',
            width: size, height: size, fit: BoxFit.contain,
            filterQuality: FilterQuality.high),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 300 || textScale >= 1.6;
        final labelWidget = Text(label,
          softWrap: true,
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant));
        final valueWidget = Money(value,
          size: strong ? 20 : 14.5,
          weight: strong ? FontWeight.w700 : FontWeight.w500);
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: valueWidget),
            ],
          );
        }
        return Row(children: [
          Expanded(child: labelWidget),
          const SizedBox(width: 12),
          Flexible(child: Align(alignment: Alignment.centerRight, child: valueWidget)),
        ]);
      }),
    );
  }
}

/// Estado vacío: dice qué hacer, no solo que no hay nada. La marca flota suavemente.
class EmptyState extends StatefulWidget {
  const EmptyState({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (reduceMotion)
          const BrandMark(size: 60)
        else
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -8 * Curves.easeInOut.transform(_c.value)),
              child: child,
            ),
            child: const BrandMark(size: 60),
          ),
        const SizedBox(height: 20),
        Reveal(index: 1, dy: 12, child: Text(widget.title, textAlign: TextAlign.center, style: t.textTheme.titleLarge)),
        const SizedBox(height: 8),
        Reveal(index: 2, dy: 12, child: Text(widget.body, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
      ]),
    );
  }
}


/// Entrada escalonada: aparece desde abajo con fundido. `index` define el retraso en cascada.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 8});
  final Widget child;
  final int index;
  final double dy;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  // Entrada corta: el contenido nunca debe quedar invisible esperando una animación (máx. ~50 ms de espera + 180 ms).
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  Timer? _t;

  @override
  void initState() {
    super.initState();
    final ms = 12 * widget.index.clamp(0, 4);
    if (ms == 0) {
      _c.forward();
    } else {
      _t = Timer(Duration(milliseconds: ms), () {
        if (mounted) _c.forward();
      });
    }
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

/// Cifra que se muestra al instante y se desliza suavemente cuando cambia (venta nueva en tiempo real).
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.builder});
  final double value;
  final Widget Function(BuildContext, double) builder;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return builder(context, value);
    // Al aparecer muestra el valor YA (sin contar desde cero); si luego cambia, la cifra se desliza al nuevo valor.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: value, end: value),
      duration: const Duration(milliseconds: 450),
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
          duration: Duration(milliseconds: _down ? 110 : 380),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      );
}

/// Tarjeta blanda con sombra difusa (reemplaza al borde duro).
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = Radii.lg, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: FvSurfaces.card(
        Theme.of(context), radius: radius, color: color),
      // Material transparente ENCIMA del color: los ListTile/InkWell de adentro dibujan su efecto de toque aquí
      // (si no, el color de la tarjeta lo tapa y Flutter muestra "EXCEPTION CAUGHT BY FLUTTER FRAMEWORK" en depuración).
      child: Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Botón de la acción principal (nombre heredado: ya no lleva degradado, §11). Relleno sólido del primario,
/// altura mínima 56 (crece con letra grande) y el texto se ajusta en vez de desbordar.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed, this.busy = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ds = DsColors.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null && !busy,
      label: label,
      child: Pressable(
        onTap: busy ? null : onPressed,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: onPressed == null ? 0.55 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ds.primary, borderRadius: BorderRadius.circular(Radii.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              busy
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: ds.onPrimary))
                  : Icon(icon, color: ds.onPrimary, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Inter', color: ds.onPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}



/// Marcador de posición con brillo que recorre la tarjeta mientras carga.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base = t.colorScheme.surfaceContainerHighest;
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(8)));
    return Shimmer(
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: base, shape: BoxShape.circle)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 14), const SizedBox(height: 8), bar(90, 11)])),
          bar(64, 16),
        ]),
      ),
    );
  }
}

/// Varias tarjetas de carga seguidas (para pantallas de lista).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < count; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonCard()),
      ]);
}


/// Libera los controladores de un diálogo u hoja inferior DESPUÉS de que termine su animación de cierre.
/// (Liberarlos justo al volver del `await` deja un TextField vivo usando un controlador ya liberado y
/// Flutter lanza `'_dependents.isEmpty': is not true`.)
void disposeAfterClose(Iterable<ChangeNotifier> items) {
  final list = items.toList();
  Future<void>.delayed(const Duration(milliseconds: 700), () {
    for (final c in list) {
      c.dispose();
    }
  });
}


/// Lluvia de confeti para celebrar un logro (factura aceptada, importación lista). No bloquea toques.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.count = 70});
  final int count;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  late final List<_Piece> _pieces = _makePieces(widget.count);

  static List<_Piece> _makePieces(int n) {
    final r = math.Random(7);
    const colors = [Brand.indigo, Brand.lilac, Brand.gold, Brand.goldDeep, Brand.ok, Color(0xFFFFD166)];
    return List.generate(
      n,
      (i) => _Piece(
        angle: -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.1,
        speed: 0.45 + r.nextDouble() * 0.75,
        spin: (r.nextDouble() - 0.5) * 14,
        size: 5 + r.nextDouble() * 6,
        color: colors[i % colors.length],
        round: r.nextBool(),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(animation: _c, builder: (context, _) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value))),
      ),
    );
  }
}

class _Piece {
  const _Piece({required this.angle, required this.speed, required this.spin, required this.size, required this.color, required this.round});
  final double angle;
  final double speed;
  final double spin;
  final double size;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.35);
    final reach = size.shortestSide < 1 ? 300.0 : size.longestSide * 0.7;
    final paint = Paint();
    for (final p in pieces) {
      final e = Curves.easeOutCubic.transform(t);
      final pos = origin + Offset(math.cos(p.angle) * p.speed * reach * e, math.sin(p.angle) * p.speed * reach * e + 380 * t * t);
      final fade = (1 - ((t - 0.6) / 0.4)).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), const Radius.circular(1.5)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}


/// Fotografías editoriales integradas por rubro; no pertenecen a ningún catálogo de empresa.
/// Las fotos reales que suba cada comerciante tienen prioridad sobre estos recursos.
String sectorPhotoFor(String? rubro) => switch (rubro) {
  'bodega' => 'bodega', 'restaurante' => 'restaurante',
  'servicios_tecnicos' => 'servicios_tecnicos', 'taller' => 'taller',
  'consultorio' => 'consultorio', 'salon' => 'salon',
  'educacion' => 'educacion', 'construccion' => 'construccion',
  'mayorista' => 'mayorista', _ => 'bodega',
};

Color sectorAccent(String? rubro) => switch (rubro) {
  'bodega' => const Color(0xFF12B88A),
  'restaurante' => const Color(0xFFFF894D),
  'servicios_tecnicos' => const Color(0xFF00B6D9),
  'taller' => const Color(0xFF328EFC),
  'consultorio' => const Color(0xFF34B7BC),
  'salon' => const Color(0xFFEB5AA5),
  'educacion' => const Color(0xFF8367EF),
  'construccion' => const Color(0xFFFFA64E),
  'mayorista' => const Color(0xFF7455EE),
  _ => const Color(0xFF6B51E6),
};

IconData sectorIcon(String? rubro) => switch (rubro) {
  'bodega' => Icons.storefront_rounded,
  'restaurante' => Icons.restaurant_rounded,
  'servicios_tecnicos' => Icons.build_circle_rounded,
  'taller' => Icons.car_repair_rounded,
  'consultorio' => Icons.health_and_safety_rounded,
  'salon' => Icons.content_cut_rounded,
  'educacion' => Icons.school_rounded,
  'construccion' => Icons.construction_rounded,
  'mayorista' => Icons.local_shipping_rounded,
  _ => Icons.storefront_rounded,
};

String sectorShortName(String? rubro) => switch (rubro) {
  'bodega' => 'Bodega / Minimarket', 'restaurante' => 'Restaurante / Cafetería',
  'servicios_tecnicos' => 'Servicios técnicos', 'taller' => 'Taller automotriz',
  'consultorio' => 'Consultorio / Salud', 'salon' => 'Salón / Barbería',
  'educacion' => 'Educación / Academia', 'construccion' => 'Construcción / Obras',
  'mayorista' => 'Mayorista / Distribución', _ => 'Tu negocio',
};

String sectorTagline(String? rubro) => switch (rubro) {
  'bodega' => 'Vende más, controla tu stock y factura en segundos.',
  'restaurante' => 'Mesas, cocina, carta y cobros conectados.',
  'servicios_tecnicos' => 'Diagnósticos, órdenes de servicio y entregas.',
  'taller' => 'Vehículos, citas, repuestos y órdenes de trabajo.',
  'consultorio' => 'Agenda y atención organizada para tus pacientes.',
  'salon' => 'Citas, servicios, clientes y tu equipo en un lugar.',
  'educacion' => 'Cursos, matrículas, horarios y pagos.',
  'construccion' => 'Obras, materiales, presupuestos y avances.',
  'mayorista' => 'Pedidos, distribución, clientes y precios por volumen.',
  _ => 'Todo tu negocio, en un solo lugar.',
};

/// Cabecera editorial específica: la imagen ambienta y nunca sustituye datos comerciales.
class SectorPhotoBanner extends StatelessWidget {
  const SectorPhotoBanner({super.key, required this.rubro, required this.title, required this.subtitle, this.height = 148});
  final String? rubro;
  final String title, subtitle;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(25),
    child: SizedBox(height: height, child: Stack(fit: StackFit.expand, children: [
      Image.asset('assets/photos/${sectorPhotoFor(rubro)}.webp', fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(gradient: Brand.heroGradient))),
      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [Color(0xD80B1034), Color(0x80202566), Color(0x09203463)],
        stops: [0, .55, 1],
      ))),
      Padding(padding: const EdgeInsets.all(18), child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: sectorAccent(rubro).withValues(alpha: .92), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(sectorIcon(rubro), color: Colors.white, size: 13), const SizedBox(width: 5),
            Flexible(child: Text(sectorShortName(rubro), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)))
          ])),
        const SizedBox(height: 8),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: -.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 270),
          child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFE9E7FF), fontSize: 12, height: 1.28))),
      ])),
    ])),
  );
}

/// Tarjeta fotográfica para seleccionar el rubro durante el alta.
/// Evita iconos arbitrarios y mantiene controles Flutter accesibles.
class SectorPhotoTile extends StatelessWidget {
  const SectorPhotoTile({super.key, required this.rubro, required this.label, required this.selected, this.height = 172});
  final String rubro, label;
  final bool selected;
  final double height;
  @override
  Widget build(BuildContext context) {
    final accent = sectorAccent(rubro);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(19),
        border: Border.all(color: selected ? accent : Theme.of(context).colorScheme.outline, width: selected ? 2.5 : 1),
        boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: .24), blurRadius: 18, offset: const Offset(0, 6))] : null),
      child: ClipRRect(borderRadius: BorderRadius.circular(17), child: SizedBox(height: height,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/photos/${sectorPhotoFor(rubro)}.webp', fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(gradient: Brand.heroGradient))),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x050C1237), Color(0x360C1237), Color(0xEA101537)]))),
          Positioned(left: 11, right: 9, bottom: 12, child: Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(9)),
              child: Icon(sectorIcon(rubro), color: Colors.white, size: 17)),
            const SizedBox(width: 7),
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.2))),
          ])),
          if (selected) Positioned(top: 9, right: 9, child: Container(padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: Icon(Icons.check_circle_rounded, color: accent, size: 23))),
        ])),
      ),
    );
  }
}
