import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart' show money;

/// A touch or arrow key selects one complete business day.
class RetailSalesTrend extends StatefulWidget {
  const RetailSalesTrend({
    super.key,
    required this.values,
    required this.currency,
    required this.lastDay,
  }) : assert(values.length > 1);

  final List<double> values;
  final String currency;
  final DateTime lastDay;

  @override
  State<RetailSalesTrend> createState() => _RetailSalesTrendState();
}

class _RetailSalesTrendState extends State<RetailSalesTrend> {
  // Store the date so a refresh across midnight retains the inspected day.
  DateTime? _inspectedDay;
  bool _showFocus = false;
  int get _last => widget.values.length - 1;
  DateTime get _end => DateTime.utc(
    widget.lastDay.year,
    widget.lastDay.month,
    widget.lastDay.day,
  );
  DateTime _date(int i) => _end.subtract(Duration(days: _last - i));
  int get _index => _inspectedDay == null
      ? _last
      : (_last - _end.difference(_inspectedDay!).inDays).clamp(0, _last);

  void _select(int index) {
    final date = _date(index.clamp(0, _last));
    if (_inspectedDay != date) setState(() => _inspectedDay = date);
  }

  String _dayLabel(int index) {
    final d = _date(index);
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _reading(int i) =>
      '${_dayLabel(i)} · ${money(widget.values[i], widget.currency)}';

  @override
  Widget build(BuildContext context) {
    final index = _index;
    final theme = Theme.of(context);
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: const Color(0xFFC6DFE6),
    );
    return Semantics(
      container: true,
      slider: true,
      label: 'Ventas diarias, últimos ${widget.values.length} días',
      value: _reading(index),
      decreasedValue: index > 0 ? _reading(index - 1) : null,
      increasedValue: index < _last ? _reading(index + 1) : null,
      onDecrease: index > 0 ? () => _select(index - 1) : null,
      onIncrease: index < _last ? () => _select(index + 1) : null,
      child: ExcludeSemantics(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _select(index - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _select(index + 1),
            const SingleActivator(LogicalKeyboardKey.home): () => _select(0),
            const SingleActivator(LogicalKeyboardKey.end): () => _select(_last),
          },
          child: FocusableActionDetector(
            onShowFocusHighlight: (value) => setState(() => _showFocus = value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    Text(
                      'Ventas por día',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _inspectedDay == null
                          ? 'Últimos ${widget.values.length} días'
                          : _reading(index),
                      key: const ValueKey('retail-trend-reading'),
                      style: axisStyle,
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, bounds) {
                    void inspect(double x) => _select(
                      (x / bounds.maxWidth * widget.values.length).floor(),
                    );
                    return GestureDetector(
                      key: const ValueKey('retail-trend-plot'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (e) => inspect(e.localPosition.dx),
                      onHorizontalDragStart: (e) => inspect(e.localPosition.dx),
                      onHorizontalDragUpdate: (e) =>
                          inspect(e.localPosition.dx),
                      child: SizedBox(
                        height: 62,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _DailyBars(
                              widget.values,
                              index,
                              _showFocus,
                              MediaQuery.highContrastOf(context),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_dayLabel(0), style: axisStyle),
                    Text(_dayLabel(_last), style: axisStyle),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyBars extends CustomPainter {
  const _DailyBars(this.values, this.selected, this.focused, this.contrast);
  final List<double> values;
  final int selected;
  final bool focused, contrast;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 7.0;
    final bottom = size.height - inset;
    final high = math.max(0.0, values.reduce(math.max));
    final low = math.min(0.0, values.reduce(math.min));
    final range = high == low ? 1.0 : high - low;
    double y(double v) => bottom - (v - low) / range * (bottom - inset);
    final zero = y(0);
    final step = size.width / values.length;
    final width = math.min(18.0, step * .57);
    final ink = Paint();
    final base = const Color(0xFF9EEBD6);
    final fill = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB5F3DD), Color(0xFF4BAAB2)],
    ).createShader(Offset.zero & size);
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      ink..color = contrast ? Colors.white70 : const Color(0xFF59808B),
    );
    for (var i = 0; i < values.length; i++) {
      final x = (i + .5) * step;
      final active = i == selected;
      if (active) {
        final track = Rect.fromLTRB(
          x - width * .74,
          1,
          x + width * .74,
          size.height - 1,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(track, const Radius.circular(8)),
          ink..color = const Color(0x3474D3D2),
        );
      }
      final tip = y(values[i]);
      final bar = Rect.fromLTRB(
        x - width / 2,
        math.min(tip, zero) - 1.5,
        x + width / 2,
        math.max(tip, zero) + 1.5,
      );
      ink.color = active ? Colors.white : base;
      ink.shader = active || contrast ? null : fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(4)),
        ink,
      );
      ink.shader = null;
    }
    if (focused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(7),
        ),
        ink
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_DailyBars old) =>
      selected != old.selected ||
      focused != old.focused ||
      contrast != old.contrast ||
      !listEquals(values, old.values);
}
