part of '../dynamic_notification_island.dart';

// Pure black merges with camera cut-outs and the hardware Dynamic Island.
const _ink = Color(0xff000000);
const _bodyRadius = 30.0;
// Distance between the pill and the card it pours into. With the pill in the
// status strip this places the card right under the system clock and icons,
// which the OS always draws on top and must stay readable.
const _gap = 10.0;

Color _bright(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  return hsl
      .withLightness(math.max(hsl.lightness, .64))
      .withSaturation(math.min(1, hsl.saturation + .08))
      .toColor();
}

/// The resting pill: a leading glyph and a trailing activity trace flanking an
/// empty center, where the camera sits on real hardware.
class _CompactIsland extends StatelessWidget {
  const _CompactIsland({
    required this.size,
    required this.notice,
    required this.pulse,
    required this.elevated,
  });

  final Size size;
  final DynamicIslandNotice? notice;
  final Animation<double> pulse;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final accent = notice == null ? null : _bright(notice!.accent);
    final glyph = size.height * .6;
    final inset = (size.height - glyph) / 2;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: _ink,
        shape: StadiumBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: elevated ? .10 : .06),
            width: .6,
          ),
        ),
        shadows: [
          if (elevated)
            const BoxShadow(
              color: Color(0x38000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Row(
          children: [
            _Glyph(
              size: glyph,
              accent: accent,
              icon: notice?.icon,
              pulse: pulse,
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => CustomPaint(
                size: Size(glyph * .9, glyph * .7),
                painter: _ActivityTrace(accent, pulse.value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.size,
    required this.accent,
    required this.icon,
    required this.pulse,
  });
  final double size;
  final Color? accent;
  final IconData? icon;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final idle = accent == null;
    final colors = idle
        ? const [Color(0xff9ff3df), Color(0xff6fb7ff)]
        : [accent!, Color.lerp(accent, const Color(0xff1d2b4a), .38)!];
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        // One soft breath when a notice arrives; still otherwise.
        final p = pulse.isAnimating ? math.sin(pulse.value * math.pi) : 0.0;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: .28 + .4 * p),
                blurRadius: 6 + 8 * p,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Icon(
        idle ? Icons.receipt_long_rounded : icon,
        size: size * .6,
        color: const Color(0xff07121c),
      ),
    );
  }
}

/// A small waveform; it swells once with [phase] when a notice arrives.
class _ActivityTrace extends CustomPainter {
  const _ActivityTrace(this.accent, this.phase);
  final Color? accent;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = [.42, .86, .58, 1.0];
    final gap = size.width / (bars.length * 2 - 1);
    final pen = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = gap
      ..color = accent ?? const Color(0xff5d6b7e);
    final mid = size.height / 2;
    for (var i = 0; i < bars.length; i++) {
      final wave = phase == 0 || phase == 1
          ? 0.0
          : math.sin((phase * 3 + i / bars.length) * math.pi * 2) *
                math.sin(phase * math.pi) *
                .35;
      final h = (bars[i] + wave).clamp(.25, 1.2) * size.height / 2;
      final x = gap / 2 + i * gap * 2;
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), pen);
    }
  }

  @override
  bool shouldRepaint(_ActivityTrace old) =>
      accent != old.accent || phase != old.phase;
}

/// The expanded island: the pill stays where it rests, and a card pours out
/// below it through a short liquid neck, then settles with a spring. The card
/// child is laid out once at full width and revealed through its growing clip,
/// so text never reflows while the shape moves.
class _IslandMorph extends SingleChildRenderObjectWidget {
  const _IslandMorph({
    required this.t,
    required this.compact,
    required this.expandedWidth,
    required this.shift,
    required this.accent,
    super.child,
  });

  final double t;
  final Size compact;
  final double expandedWidth;
  final double shift;
  final Color accent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIslandMorph(t, compact, expandedWidth, shift, accent);

  @override
  void updateRenderObject(BuildContext context, _RenderIslandMorph r) {
    r
      ..t = t
      ..compact = compact
      ..expandedWidth = expandedWidth
      ..shift = shift
      ..accent = accent;
  }
}

class _RenderIslandMorph extends RenderProxyBox {
  _RenderIslandMorph(
    this._t,
    this._compact,
    this._width,
    this._shift,
    this._accent,
  );

  double _t;
  set t(double v) {
    if (v == _t) return;
    _t = v;
    markNeedsLayout();
  }

  Size _compact;
  set compact(Size v) {
    if (v == _compact) return;
    _compact = v;
    markNeedsLayout();
  }

  double _width;
  set expandedWidth(double v) {
    if (v == _width) return;
    _width = v;
    markNeedsLayout();
  }

  double _shift;
  set shift(double v) {
    if (v == _shift) return;
    _shift = v;
    markNeedsLayout();
  }

  Color _accent;
  set accent(Color v) {
    if (v == _accent) return;
    _accent = v;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipRRectLayer>();
  late Rect _pill;
  late RRect _body;
  Offset _childOffset = Offset.zero;
  double _grow = 0;

  @override
  void performLayout() {
    final c = child!;
    c.layout(BoxConstraints.tightFor(width: _width), parentUsesSize: true);
    final t = _t;
    // 0 → 0.3: the body slides out from behind the pill, stretching the neck.
    // 0.15 → 1: it widens and fills. The width keeps the spring's overshoot.
    final drop = Curves.easeOutCubic.transform((t / .3).clamp(0.0, 1.0));
    final open = (t - .15) / .85;
    _grow = open.clamp(0.0, 1.0);
    final bodyW = lerpDouble(_compact.width * .62, _width, open)!;
    final bodyH = lerpDouble(_compact.height * .8, c.size.height, _grow)!;
    final bodyTop = lerpDouble(_compact.height * .1, _compact.height + _gap, drop)!;
    final span = _width + _shift.abs() * 2;
    final w = math.max(_compact.width, math.max(span, bodyW + _shift.abs() * 2));
    size = constraints.constrain(Size(w, math.max(_compact.height, bodyTop + bodyH)));
    final mid = size.width / 2;
    _pill = Rect.fromCenter(
      center: Offset(mid, _compact.height / 2),
      width: _compact.width,
      height: _compact.height,
    );
    final bodyCenter = mid + _shift * _grow;
    _body = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyCenter - bodyW / 2, bodyTop, bodyW, bodyH),
      Radius.circular(
        math.min(lerpDouble(_compact.height * .45, _bodyRadius, _grow)!, bodyH / 2),
      ),
    );
    _childOffset = Offset(bodyCenter - _width / 2, bodyTop);
  }

  // A metaball bridge: narrow under the pill, flaring into the card's top edge.
  Path _neck() {
    final top = _pill.bottom - 2;
    final bottom = _body.top + 1;
    if (bottom <= top + .5) return Path();
    final cx = (_pill.center.dx + _body.center.dx) / 2;
    final waist = math.min(_compact.width * .2, 24.0);
    final flare = math.min(waist + 16, _body.width / 2 - _body.tlRadiusX * .3);
    final h = bottom - top;
    return Path()
      ..moveTo(cx - waist, top)
      ..cubicTo(cx - waist, top + h * .55, cx - flare + 4, bottom, cx - flare, bottom + 2)
      ..lineTo(cx + flare, bottom + 2)
      ..cubicTo(cx + flare - 4, bottom, cx + waist, top + h * .55, cx + waist, top)
      ..close();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final pill = RRect.fromRectAndRadius(_pill, Radius.circular(_pill.height / 2));
    final g = _grow;
    final ink = Paint()..color = _ink;
    if (g > 0) {
      canvas.drawShadow(
        Path()..addRRect(_body),
        Colors.black.withValues(alpha: .55 * g),
        20 * g,
        false,
      );
    }
    canvas.drawRRect(_body, ink);
    canvas.drawPath(_neck(), ink);
    canvas.drawRRect(pill, ink);
    if (g > .05) {
      // Contextual light: the notice color glows from the leading corner, and
      // a faint sheen along the top edge suggests a polished surface.
      final glow = _bright(_accent);
      final r = _body.outerRect;
      canvas.save();
      canvas.clipRRect(_body);
      canvas.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-1, -1.2),
            radius: 1.3,
            colors: [glow.withValues(alpha: .30 * g), glow.withValues(alpha: 0)],
          ).createShader(r),
      );
      final sheen = Rect.fromLTWH(r.left, r.top, r.width, 28);
      canvas.drawRect(
        sheen,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: .08 * g),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(sheen),
      );
      canvas.restore();
      canvas.drawRRect(
        _body.deflate(.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = Colors.white.withValues(alpha: .12 * g),
      );
    }
    canvas.restore();
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      _body.outerRect,
      _body,
      (context, offset) => context.paintChild(child!, offset + _childOffset),
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_body.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: _childOffset,
      position: position,
      hitTest: (result, local) => child!.hitTest(result, position: local),
    );
  }

  @override
  bool hitTestSelf(Offset position) =>
      _body.contains(position) || _pill.contains(position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_childOffset.dx, _childOffset.dy, 0, 1);
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

/// The card's content.
class _ExpandedIsland extends StatelessWidget {
  const _ExpandedIsland({
    required this.notice,
    required this.onOpen,
    required this.onClose,
  });

  final DynamicIslandNotice notice;
  final VoidCallback onOpen, onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _bright(notice.accent);
    return Semantics(
      key: const ValueKey('dynamic-island-notice'),
      container: true,
      liveRegion: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(_bodyRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent,
                            Color.lerp(accent, const Color(0xff13233d), .45)!,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: .42),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        notice.icon,
                        size: 22,
                        color: const Color(0xff07121c),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (notice.category != null)
                            Text(
                              notice.category!.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            notice.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              height: 1.18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      icon: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: .13),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 52, right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          notice.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xffc3cdda),
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: const StadiumBorder(),
                          color: accent,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          child: Text(
                            notice.actionLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: const Color(0xff07121c),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
