part of '../dynamic_notification_island.dart';

const _cardTop = 38.0;
const _islandInk = Color(0xff121722);
const _cardInk = Color(0xff1b2635);

class _ActivityMark extends CustomPainter {
  const _ActivityMark(this.accent);
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = accent ?? const Color(0xffaab6c8);
    final path = Path()
      ..moveTo(1, mid + 2)
      ..cubicTo(6, mid + 2, 7, mid - 4, 11, mid - 4)
      ..cubicTo(15, mid - 4, 15, mid + 3, 19, mid + 3)
      ..quadraticBezierTo(21, mid + 3, 24, mid);
    canvas.drawPath(path, pen);
    if (accent != null) {
      pen.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.width - 2, mid), 2.1, pen);
    }
  }

  @override
  bool shouldRepaint(_ActivityMark oldDelegate) => accent != oldDelegate.accent;
}

/// Derived from rit3zh/expo-dynamic-notifications buildNotificationGeometry
/// and neckProfile. Translates their droplet stretch and neck break to Canvas.
class _DropletPainter extends CustomPainter {
  const _DropletPainter(this.progress, this.anchorX);
  final double progress;
  final double anchorX;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.height <= _cardTop) return;
    final drop = const Interval(
      0,
      .62,
      curve: Curves.easeOutCubic,
    ).transform(progress);
    final expand = const Interval(
      340 / 780,
      1,
      curve: Curves.easeOutCubic,
    ).transform(progress);
    final tint = const Interval(110 / 780, .85).transform(progress);
    final grow = 1 - math.pow(1 - (drop / .7).clamp(0.0, 1.0), 1.25);
    final phase = (drop / .82).clamp(0.0, 1.0);
    const peak = 1.6 / (1.6 + 1.4);
    final norm = math.pow(peak, 1.6) * math.pow(1 - peak, 1.4);
    final neck = math.pow(phase, 1.6) * math.pow(1 - phase, 1.4) / norm;
    final stretch = 1 + .38 * neck;
    final diameter = 46.0 * grow;
    final w = lerpDouble(diameter / stretch, size.width, expand)!;
    final h = lerpDouble(diameter * stretch, size.height - _cardTop, expand)!;
    final cx = lerpDouble(anchorX, size.width / 2, drop)!;
    final cy = lerpDouble(4.2, _cardTop + (size.height - _cardTop) / 2, drop)!;
    final pen = Paint()..color = Color.lerp(_islandInk, _cardInk, tint)!;
    if (neck > 0 && w > 0) {
      final half = math.min(w, 46.0) * neck / 2;
      canvas.drawPath(
        Path()
          ..moveTo(anchorX - half, 0)
          ..quadraticBezierTo(cx - half * .45, cy * .52, cx - half, cy)
          ..lineTo(cx + half, cy)
          ..quadraticBezierTo(cx + half * .45, cy * .52, anchorX + half, 0)
          ..close(),
        pen,
      );
    }
    final radius = math.min(
      lerpDouble(diameter / 2, 23, expand)!,
      math.min(w, h) / 2,
    );
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      Radius.circular(radius),
    );
    if (expand > 0) {
      canvas.drawShadow(
        Path()..addRRect(rect),
        const Color(0xff0b162a).withValues(alpha: .36 * expand),
        7,
        false,
      );
    }
    canvas.drawRRect(rect, pen);
    if (expand > .65) {
      pen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .21 * expand);
      canvas.drawRRect(rect.deflate(.5), pen);
    }
  }

  @override
  bool hitTest(Offset position) => false;
  @override
  bool shouldRepaint(_DropletPainter oldDelegate) =>
      progress != oldDelegate.progress || anchorX != oldDelegate.anchorX;
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.notice,
    required this.onOpen,
    required this.onClose,
  });
  final DynamicIslandNotice notice;
  final VoidCallback onOpen, onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An upstream accent may be dark. Preserve its hue in the symbol and keep
    // the text on a stable accessible foreground in both app themes.
    final accent = Color.lerp(notice.accent, Colors.white, .45)!;
    return Semantics(
      key: const ValueKey('dynamic-island-notice'),
      container: true,
      liveRegion: true,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 74),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(23),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 0, 13),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .13),
                            border: Border.all(
                              color: accent.withValues(alpha: .32),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.notifications_outlined,
                              color: accent,
                              size: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                notice.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (notice.message.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  notice.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xffdce6f3),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: Color(0xffcfdaea),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
