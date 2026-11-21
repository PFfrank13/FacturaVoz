import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';

/// Aparece una sola vez cuando un bloque entra realmente al viewport.
/// Se usa en secciones grandes, no por fila en listas virtualizadas.
class FvScrollReveal extends StatefulWidget {
  const FvScrollReveal({super.key, required this.child, this.offset = 14});

  final Widget child;
  final double offset;

  @override
  State<FvScrollReveal> createState() => _FvScrollRevealState();
}

class _FvScrollRevealState extends State<FvScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );
  late final _progress = _controller.drive(CurveTween(curve: Motion.enter));
  ScrollPosition? _scrollPosition;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(_scrollPosition, next)) {
      _scrollPosition?.removeListener(_checkVisibility);
      _scrollPosition = next;
      if (!_shown) _scrollPosition?.addListener(_checkVisibility);
    }
    if (reduceMotion(context)) {
      _shown = true;
      _scrollPosition?.removeListener(_checkVisibility);
      _controller.value = 1;
    } else if (!_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  void _checkVisibility() {
    if (!mounted || _shown) return;
    final target = context.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) return;

    final RenderBox? viewportBox =
        RenderAbstractViewport.maybeOf(target) as RenderBox?;
    if (viewportBox != null && viewportBox.attached && viewportBox.hasSize) {
      final top = target.localToGlobal(Offset.zero).dy;
      final bottom = top + target.size.height;
      final visibleTop = viewportBox.localToGlobal(Offset.zero).dy;
      final visibleBottom = visibleTop + viewportBox.size.height;
      if (bottom <= visibleTop + 12 || top >= visibleBottom - 12) return;
    }
    _shown = true;
    _scrollPosition?.removeListener(_checkVisibility);
    if (reduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_checkVisibility);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - _progress.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
