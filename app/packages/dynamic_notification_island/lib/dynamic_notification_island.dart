import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

part 'src/island_surface.dart';

@immutable
class DynamicIslandNotice {
  const DynamicIslandNotice({
    required this.id,
    required this.title,
    this.message = '',
    this.accent = const Color(0xff87e5cb),
  });

  final String id;
  final String title;
  final String message;
  final Color accent;
}

/// An in-app island anchored to its compact toolbar control.
///
/// Changing [announcement] to a new non-null value presents [notice]. Removing
/// the notice immediately removes its content, including during a transition.
class DynamicNotificationIsland extends StatefulWidget {
  const DynamicNotificationIsland({
    super.key,
    required this.notice,
    required this.onOpen,
    this.announcement,
    this.compactLabel = 'Actividad',
    this.duration = const Duration(milliseconds: 3600),
  });

  final DynamicIslandNotice? notice;
  final Object? announcement;
  final VoidCallback onOpen;
  final String compactLabel;
  final Duration? duration;

  @override
  State<DynamicNotificationIsland> createState() =>
      _DynamicNotificationIslandState();
}

class _DynamicNotificationIslandState extends State<DynamicNotificationIsland>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
    reverseDuration: const Duration(milliseconds: 360),
  )..addStatusListener(_statusChanged);
  Timer? _timer;
  String? _visibleId;
  double _drag = 0;
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
        if (_motion.status == AnimationStatus.reverse) {
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

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _visibleId = null;
    _hidePortal();
  }

  void _hidePortal() {
    if (!_portal.isShowing) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visibleId == null && _portal.isShowing) _portal.hide();
      });
    } else {
      _portal.hide();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    final lifetime = widget.duration;
    if (_accessible || lifetime == null || !_portal.isShowing) return;
    const revealDelay = Duration(milliseconds: 560);
    _timer = Timer(lifetime + (_reduced ? Duration.zero : revealDelay), _close);
  }

  void _show() {
    if (widget.notice == null) {
      widget.onOpen();
      return;
    }
    _drag = 0;
    _visibleId = widget.notice!.id;
    _portal.show();
    if (_reduced) {
      _motion.value = 1;
    } else {
      _motion.forward();
    }
    _scheduleDismiss();
  }

  void _dropImmediately() {
    _timer?.cancel();
    _drag = 0;
    _visibleId = null;
    _motion.value = 0;
    _hidePortal();
  }

  void _close() {
    _timer?.cancel();
    if (!_portal.isShowing) return;
    if (_reduced) {
      _dropImmediately();
    } else {
      _motion.reverse();
    }
  }

  void _open() {
    _dropImmediately();
    widget.onOpen();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: CompositedTransformTarget(
        link: _link,
        child: SizedBox(
          key: _anchor,
          width: 80,
          height: 48,
          child: Semantics(
            button: true,
            label: widget.compactLabel,
            child: Tooltip(
              message: widget.compactLabel,
              excludeFromSemantics: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('dynamic-island'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _portal.isShowing ? _close() : _show(),
                  child: Center(
                    child: Container(
                      height: 26,
                      width: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xff11141c),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xff48515e)),
                      ),
                      child: Center(
                        child: CustomPaint(
                          painter: _ActivityMark(notice?.accent),
                          size: const Size(32, 13),
                        ),
                      ),
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
    // toolbar movement, while an offset keeps the card within the safe edges.
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
        final usable = math.max(
          0.0,
          bounds.maxWidth - safe.left - safe.right - 24,
        );
        final width = math.min(396.0, usable);
        if (width < 100) return const SizedBox.shrink();
        final left = (center.dx - width / 2)
            .clamp(
              safe.left + 12,
              math.max(
                safe.left + 12,
                bounds.maxWidth - safe.right - 12 - width,
              ),
            )
            .toDouble();
        final shift = left + width / 2 - center.dx;
        final content = _NoticeCard(
          notice: notice,
          onOpen: _open,
          onClose: _close,
        );
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: width,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.center,
                followerAnchor: Alignment.topCenter,
                offset: Offset(shift, 0),
                child: AnimatedBuilder(
                  animation: _motion,
                  child: content,
                  builder: (context, child) {
                    final t = _motion.value;
                    final reveal = const Interval(
                      560 / 780,
                      1,
                      curve: Curves.easeOutCubic,
                    ).transform(t);
                    return Transform.translate(
                      offset: Offset(0, _reduced ? 0 : _drag),
                      child: CustomPaint(
                        painter: _DropletPainter(t, width / 2 - shift),
                        child: Padding(
                          padding: const EdgeInsets.only(top: _cardTop),
                          child: IgnorePointer(
                            ignoring: reveal < .5,
                            child: ExcludeSemantics(
                              excluding: reveal < .5,
                              child: Opacity(
                                opacity: reveal,
                                child: GestureDetector(
                                  onVerticalDragStart: (_) => _timer?.cancel(),
                                  onVerticalDragUpdate: (event) => setState(() {
                                    _drag = (_drag + event.delta.dy).clamp(
                                      -120.0,
                                      24.0,
                                    );
                                  }),
                                  onVerticalDragCancel: () {
                                    setState(() => _drag = 0);
                                    _scheduleDismiss();
                                  },
                                  onVerticalDragEnd: (event) {
                                    if (_drag < -18 ||
                                        (event.primaryVelocity ?? 0) < -420) {
                                      _close();
                                    } else {
                                      setState(() => _drag = 0);
                                      _scheduleDismiss();
                                    }
                                  },
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
            ),
          ],
        );
      },
    );
  }
}
