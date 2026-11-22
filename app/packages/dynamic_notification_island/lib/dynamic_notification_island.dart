import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/material.dart';

part 'src/island_surface.dart';

@immutable
class DynamicIslandNotice {
  const DynamicIslandNotice({
    required this.id,
    required this.title,
    this.message = '',
    this.accent = const Color(0xff87e5cb),
    this.icon = Icons.notifications_active_rounded,
    this.category,
    this.actionLabel = 'Ver',
  });

  final String id;
  final String title;
  final String message;
  final Color accent;
  final IconData icon;

  /// Short context shown beside the camera when expanded, e.g. «Caja».
  final String? category;
  final String actionLabel;
}

/// Where the compact island lives. [statusBar] sits in the system status strip,
/// centered over the camera cut-out; [toolbar] sits inside an app bar row.
enum IslandPlacement { statusBar, toolbar }

/// Geometry for an island centered in the system status strip.
///
/// On iPhones with a Dynamic Island (top inset ≥ 51) the pill wraps the
/// hardware island; on notches and Android punch-holes it is centered in the
/// strip. Returns null when there is no status strip (web, desktop, landscape).
({double top, Size size})? statusBarIslandGeometry(MediaQueryData media) {
  final strip = media.padding.top;
  if (strip < 20 || media.size.width < 300) return null;
  // Around the 126 pt hardware island, 32 pt on each side holds the glyph and
  // the trace clear of the camera while leaving the clock and icons visible.
  final width = strip >= 51 ? 190.0 : (media.size.width * .42).clamp(150.0, 190.0);
  final height = strip >= 51 ? 37.0 : (strip - 6).clamp(26.0, 34.0);
  final top = strip >= 51 ? 11.0 : math.max(3.0, (strip - height) / 2);
  return (top: top, size: Size(width, height));
}

/// An in-app island that morphs from a compact pill into an expanded card.
///
/// Changing [announcement] to a new non-null value presents [notice]. Removing
/// the notice immediately removes its content, including during a transition.
/// This is a Flutter surface: it is not the native iOS Live Activity API.
class DynamicNotificationIsland extends StatefulWidget {
  const DynamicNotificationIsland({
    super.key,
    required this.notice,
    required this.onOpen,
    this.announcement,
    this.compactLabel = 'Actividad',
    this.duration = const Duration(milliseconds: 3600),
    this.compactSize = const Size(126, 34),
    this.placement = IslandPlacement.toolbar,
  });

  final DynamicIslandNotice? notice;
  final Object? announcement;
  final VoidCallback onOpen;
  final String compactLabel;
  final Duration? duration;
  final Size compactSize;
  final IslandPlacement placement;

  @override
  State<DynamicNotificationIsland> createState() =>
      _DynamicNotificationIslandState();
}

// Springs tuned against iOS: a soft overshoot on open, a critically damped
// retreat on close. Both settle in roughly 450 ms and stay interruptible.
final _openSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 250,
  ratio: .72,
);
final _closeSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 420,
  ratio: 1,
);
final _tolerance = Tolerance(distance: .001, velocity: .01);

class _DynamicNotificationIslandState extends State<DynamicNotificationIsland>
    with TickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  late final _motion = AnimationController.unbounded(vsync: this);
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  Timer? _timer;
  String? _visibleId;
  double _target = 0;
  double _dragDy = 0;
  bool _reduced = false;
  bool _accessible = false;
  bool _announcedInitial = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessibility = MediaQuery.accessibleNavigationOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_portal.isShowing) {
      if (reduced && !_reduced && _motion.isAnimating) {
        if (_target == 0) {
          _dropImmediately();
        } else {
          _motion.value = 1;
        }
      }
      if (_accessible != accessibility) {
        _accessible = accessibility;
        _scheduleDismiss();
      }
    }
    _accessible = accessibility;
    _reduced = reduced;
    if (!_announcedInitial) {
      _announcedInitial = true;
      if (widget.announcement != null && widget.notice != null) {
        _showAfterBuild();
      }
    }
  }

  @override
  void didUpdateWidget(covariant DynamicNotificationIsland oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notice == null || widget.notice?.id != oldWidget.notice?.id) {
      _dropImmediately();
    }
    if (widget.notice != null &&
        widget.announcement != null &&
        widget.announcement != oldWidget.announcement) {
      _showAfterBuild();
    } else if (widget.duration != oldWidget.duration && _portal.isShowing) {
      _scheduleDismiss();
    }
  }

  void _showAfterBuild() {
    final expectedId = widget.notice?.id;
    final announcement = widget.announcement;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.notice?.id == expectedId &&
          widget.announcement == announcement &&
          (ModalRoute.isCurrentOf(context) ?? true)) {
        _show();
      }
    });
  }

  void _springTo(double target, {double velocity = 0}) {
    _target = target;
    if (_reduced) {
      _motion.value = target;
      if (target == 0) _settledClosed();
      return;
    }
    final simulation = SpringSimulation(
      target > 0 ? _openSpring : _closeSpring,
      _motion.value,
      target,
      velocity,
      tolerance: _tolerance,
    );
    _motion.animateWith(simulation).whenCompleteOrCancel(() {
      if (mounted && _target == 0 && !_motion.isAnimating) _settledClosed();
    });
  }

  void _settledClosed() {
    _visibleId = null;
    _dragDy = 0;
    _hidePortal();
  }

  void _hidePortal() {
    if (!_portal.isShowing) return;
    void hide() {
      if (mounted && _visibleId == null && _portal.isShowing) {
        setState(_portal.hide);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => hide());
    } else {
      hide();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    final lifetime = widget.duration;
    if (_accessible || lifetime == null || !_portal.isShowing) return;
    const revealDelay = Duration(milliseconds: 420);
    _timer = Timer(lifetime + (_reduced ? Duration.zero : revealDelay), _close);
  }

  void _show() {
    if (widget.notice == null) {
      widget.onOpen();
      return;
    }
    _dragDy = 0;
    _visibleId = widget.notice!.id;
    if (!_portal.isShowing) setState(_portal.show);
    if (!_reduced) {
      HapticFeedback.lightImpact();
      _pulse.forward(from: 0);
    }
    _springTo(1);
    _scheduleDismiss();
  }

  void _dropImmediately() {
    _timer?.cancel();
    _motion.stop();
    _target = 0;
    _dragDy = 0;
    _visibleId = null;
    _motion.value = 0;
    _hidePortal();
  }

  void _close({double velocity = 0}) {
    _timer?.cancel();
    if (!_portal.isShowing) return;
    if (_reduced) {
      _dropImmediately();
    } else {
      HapticFeedback.selectionClick();
      _springTo(0, velocity: velocity);
    }
  }

  void _open() {
    _dropImmediately();
    widget.onOpen();
  }

  // A swipe up compresses the island back toward the pill, following the
  // finger, and the release velocity carries straight into the spring.
  void _dragUpdate(DragUpdateDetails event) {
    _timer?.cancel();
    _motion.stop();
    final dy = event.delta.dy;
    if (dy < 0 || _motion.value < 1) {
      _motion.value = (_motion.value + dy / 190).clamp(.35, 1.0);
      _dragDy = 0;
    } else {
      // Rubber band downward, iOS-style: resistance grows with distance.
      _dragDy = (_dragDy + dy * (1 - _dragDy / 40)).clamp(0.0, 24.0);
    }
    setState(() {});
  }

  void _dragEnd(DragEndDetails event) {
    final velocity = (event.primaryVelocity ?? 0) / 190;
    setState(() => _dragDy = 0);
    if (_motion.value < .86 || velocity < -2.2) {
      _close(velocity: math.min(velocity, 0));
    } else {
      _springTo(1, velocity: velocity.clamp(-4.0, 4.0));
      _scheduleDismiss();
    }
  }

  void _dragCancel() {
    setState(() => _dragDy = 0);
    _springTo(1);
    _scheduleDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final size = widget.compactSize;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: CompositedTransformTarget(
        link: _link,
        child: SizedBox.fromSize(
          key: _anchor,
          size: size,
          child: Semantics(
            button: true,
            label: widget.compactLabel,
            child: Tooltip(
              message: widget.compactLabel,
              excludeFromSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('dynamic-island'),
                  customBorder: const StadiumBorder(),
                  splashColor: Colors.white.withValues(alpha: .08),
                  highlightColor: Colors.white.withValues(alpha: .05),
                  onTap: () => _portal.isShowing ? _close() : _show(),
                  // The expanded surface replaces the pill while it is shown,
                  // so there is always exactly one island on screen.
                  child: Opacity(
                    opacity: _portal.isShowing ? 0 : 1,
                    child: _CompactIsland(
                      size: size,
                      notice: notice,
                      pulse: _pulse,
                      elevated: widget.placement == IslandPlacement.toolbar,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final notice = widget.notice;
    if (notice == null || _visibleId != notice.id) {
      return const SizedBox.shrink();
    }
    // Leave the rest of the overlay transparent to touch. The follower tracks
    // the pill, while a shift keeps the expanded island within the safe edges.
    return LayoutBuilder(
      builder: (context, bounds) {
        final overlay = Overlay.of(context).context.findRenderObject();
        final anchor = _anchor.currentContext?.findRenderObject();
        if (overlay is! RenderBox ||
            anchor is! RenderBox ||
            !anchor.hasSize ||
            !overlay.attached ||
            !anchor.attached) {
          return const SizedBox.shrink();
        }
        final center = anchor.localToGlobal(
          anchor.size.center(Offset.zero),
          ancestor: overlay,
        );
        final safe = MediaQuery.paddingOf(context);
        const margin = 10.0;
        final usable = math.max(
          0.0,
          bounds.maxWidth - safe.left - safe.right - margin * 2,
        );
        final width = math.min(412.0, usable);
        if (width < 100) return const SizedBox.shrink();
        final left = (center.dx - width / 2)
            .clamp(
              safe.left + margin,
              math.max(
                safe.left + margin,
                bounds.maxWidth - safe.right - margin - width,
              ),
            )
            .toDouble();
        final shift = left + width / 2 - center.dx;
        final content = _ExpandedIsland(
          notice: notice,
          onOpen: _open,
          onClose: _close,
        );
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: AnimatedBuilder(
                animation: _motion,
                child: content,
                builder: (context, child) {
                  final t = _motion.value;
                  // Content waits until the card is nearly full width, so
                  // text is never seen clipped by the narrow, moving shape.
                  final reveal = Curves.easeOutCubic.transform(
                    ((t - .88) / .12).clamp(0.0, 1.0),
                  );
                  return CompositedTransformFollower(
                    link: _link,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.topCenter,
                    followerAnchor: Alignment.topCenter,
                    offset: Offset(0, _dragDy),
                    child: GestureDetector(
                      onVerticalDragStart: (_) => _timer?.cancel(),
                      onVerticalDragUpdate: _dragUpdate,
                      onVerticalDragEnd: _dragEnd,
                      onVerticalDragCancel: _dragCancel,
                      child: _IslandMorph(
                        t: t,
                        compact: widget.compactSize,
                        expandedWidth: width,
                        shift: shift,
                        accent: notice.accent,
                        child: IgnorePointer(
                          ignoring: reveal < .5,
                          child: ExcludeSemantics(
                            excluding: reveal < .5,
                            child: Opacity(
                              opacity: reveal,
                              child: Transform.scale(
                                scale: lerpDouble(.94, 1, reveal),
                                alignment: Alignment.topCenter,
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
