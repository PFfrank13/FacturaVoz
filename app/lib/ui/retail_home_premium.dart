import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';
import 'glass_widgets.dart';
import 'motion.dart';
import 'retail_icon.dart';

/// Editorial palette: neutral foundations with restrained functional color.
/// These tones identify actions, never replace their text labels.
abstract final class RetailAccent {
  static const ink = Color(0xFF18243A);
  static const teal = FvLuxe.jade;
  static const blue = Color(0xFF537AF1);
  static const coral = Color(0xFFF97A83);
  static const amber = Color(0xFFEBB32E);
  static const mint = Color(0xFF37BDAB);
  static const muted = Color(0xFF5B6475);
}

/// Genuine data dashboard, never a fabricated revenue graphic.
/// Keeps the exact existing home key used by navigation and regression tests.
class RetailPremiumOverview extends StatelessWidget {
  const RetailPremiumOverview({
    super.key,
    required this.name, required this.currencySymbol,
    required this.salesAmount, required this.loaded,
    required this.showMonth, required this.salesCount,
    required this.drafts, required this.todayAmount,
    required this.todayCount, required this.chart,
    required this.onGoal, this.goalPercent,
  });

  final String name, currencySymbol;
  final double salesAmount;
  final int salesCount, drafts;
  final double? todayAmount;
  final int? todayCount;
  final bool loaded, showMonth;
  final Widget? chart;
  final double? goalPercent;
  final VoidCallback onGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contrast = MediaQuery.highContrastOf(context);
    final radius = BorderRadius.circular(27);
    final facts = <Widget>[
      if (showMonth && loaded) _MiniFact(icon: Icons.receipt_long_outlined,
        label: salesCount == 1 ? '1 venta emitida' : '$salesCount ventas emitidas'),
      if (todayAmount != null) _MiniFact(icon: Icons.today_outlined,
        label: 'Hoy $currencySymbol ${todayAmount!.toStringAsFixed(2)}')
      else if (todayCount != null && !showMonth)
        _MiniFact(icon: Icons.today_outlined, label: 'Hoy $todayCount ${todayCount == 1 ? 'venta' : 'ventas'}'),
      if (showMonth && loaded && drafts > 0) _MiniFact(icon: Icons.edit_note_outlined,
        label: '$drafts ${drafts == 1 ? 'borrador' : 'borradores'}'),
    ];
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const RetailIcon(Icons.storefront_outlined,
            ink: Color(0xFFDDFBF6), accent: Color(0xFF389D9F), size: 23),
          const SizedBox(width: 9),
          Expanded(child: Text(showMonth ? 'Ventas de este mes' : 'Tu actividad',
            style: theme.textTheme.labelLarge?.copyWith(color: const Color(0xFFD7F8F2)))),
        ]),
        const SizedBox(height: 14),
        if (showMonth)
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(loaded ? '$currencySymbol ${salesAmount.toStringAsFixed(2)}' : '—',
              style: theme.textTheme.displayMedium?.copyWith(
                color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600,
                fontSize: 51, height: 1.02, letterSpacing: -2.8,
                fontFeatures: const [FontFeature.tabularFigures()]))),
        if (!showMonth)
          Text('Operaciones del negocio', style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white, fontFamily: FvLuxe.editorialFont, fontWeight: FontWeight.w400)),
      ],
    );
    final lead = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, bounds) {
        final reserve = !contrast && bounds.maxWidth >= 260 &&
            MediaQuery.textScalerOf(context).scale(16) <= 20 ? 64.0 : 0.0;
        return Padding(padding: EdgeInsets.only(right: reserve), child: summary);
      }),
      if (facts.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 14, runSpacing: 7, children: facts),
      ],
    ]);
    final trend = showMonth && loaded && chart != null ? _RetailTrend(chart: chart!) : null;
    return Semantics(
      container: true, label: 'Resumen operativo de ${name.isEmpty ? 'la bodega' : name}',
      child: DecoratedBox(
        key: const ValueKey('bodega-enterprise-overview'),
        decoration: BoxDecoration(borderRadius: radius, boxShadow: [
          BoxShadow(color: const Color(0xFF0A232C).withValues(alpha:
            theme.brightness == Brightness.dark ? .28 : .18),
            blurRadius: 19, offset: const Offset(0, 8)),
        ]),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF145668), Color(0xFF173453), Color(0xFF121E38)],
              stops: [0, .57, 1])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Stack(children: [
                if (!contrast && MediaQuery.textScalerOf(context).scale(16) <= 20)
                  const PositionedDirectional(top: 0, end: 0, width: 90, height: 76,
                    child: IgnorePointer(child: ClipRect(child: CustomPaint(painter: _VoiceRings())))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 19, 20, 17),
                  child: LayoutBuilder(builder: (context, bounds) {
                    final wide = bounds.maxWidth >= 650 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24;
                    if (wide && trend != null) {
                      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(child: lead), const SizedBox(width: 34),
                        Expanded(child: trend),
                      ]);
                    }
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      lead, if (trend != null) ...[const SizedBox(height: 19), trend],
                    ]);
                  }),
                ),
              ]),
              if (showMonth) _RetailGoal(percent: goalPercent, onTap: onGoal),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three cropped, flat bands echo the voice motif. They are painted once.
class _VoiceRings extends CustomPainter {
  const _VoiceRings();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 4, -15);
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 11;
    for (final (radius, pigment) in const [
      (27.0, Color(0xFFAEF0D5)),
      (46.0, Color(0xFF61D3C4)),
      (65.0, Color(0xFF518AAD)),
    ]) {
      canvas.drawCircle(center, radius, stroke..color = pigment);
    }
  }

  @override
  bool shouldRepaint(_VoiceRings oldDelegate) => false;
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: const Color(0xFF7FE7CD)),
    const SizedBox(width: 5),
    Flexible(child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: const Color(0xFFEBF7F8), fontSize: 12, fontWeight: FontWeight.w500))),
  ]);
}

class _RetailTrend extends StatelessWidget {
  const _RetailTrend({required this.chart});
  final Widget chart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Tendencia · últimos 14 días', style: theme.textTheme.labelSmall?.copyWith(
        color: const Color(0xFFD2E5DE), fontWeight: FontWeight.w500)),
      const SizedBox(height: 9),
      SizedBox(height: 41, child: Stack(fit: StackFit.expand, children: [
        const Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Divider(height: 1, color: Color(0x304C7578)),
          Divider(height: 1, color: Color(0x304C7578)),
          Divider(height: 1, color: Color(0x506E8E8F)),
        ]),
        chart,
      ])),
    ]);
  }
}

class _RetailGoal extends StatelessWidget {
  const _RetailGoal({required this.percent, required this.onTap});
  final double? percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: const Color(0xFF142E45),
      child: InkWell(
        key: const ValueKey('bodega-goal-action'),
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          constraints: const BoxConstraints(minHeight: 49),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF426165), width: .7))),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.outlined_flag_rounded, color: Color(0xFFABF3CA), size: 19),
              const SizedBox(width: 10),
              Expanded(child: Text(percent == null ? 'Establecer meta del mes' : 'Meta mensual',
                style: t.textTheme.labelLarge?.copyWith(color: const Color(0xFFECF8F6)))),
              if (percent != null) Text('${(percent! * 100).round()}%',
                style: t.textTheme.labelMedium?.copyWith(color: Colors.white)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFCDE2D8), size: 19),
            ]),
            if (percent != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: percent!.clamp(0, 1), minHeight: 3,
                borderRadius: BorderRadius.circular(3),
                color: const Color(0xFFABF3CA), backgroundColor: const Color(0xFF486469)),
            ],
          ]),
        ),
      ),
    );
  }
}


/// Aligns the bottom edges of adjacent tiles while allowing large text to wrap.
class RetailHomeStatGrid extends StatelessWidget {
  const RetailHomeStatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    const gap = 12.0;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final columns = ((bounds.maxWidth + gap) / (137 * scale + gap)).floor().clamp(1, 4);
    return Column(children: [
      for (int start = 0; start < children.length; start += columns) ...[
        if (start != 0) const SizedBox(height: gap),
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (int i = 0; i < columns; i++) ...[
            if (i != 0) const SizedBox(width: gap),
            Expanded(child: start + i < children.length ? children[start + i] : const SizedBox.shrink()),
          ],
        ])),
      ],
    ]);
  });
}

/// A metric surface keeps the value, status and touch target together.
class RetailHomeStat extends StatelessWidget {
  const RetailHomeStat({
    super.key, required this.label, required this.value,
    required this.icon, required this.tint,
    this.detail, this.onTap, this.tone,
  });
  final String label, value;
  final String? detail;
  final Color tint;
  final Color? tone;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final paper = dark ? const Color(0xFF162333) : Colors.white;
    final pigment = dark ? Color.lerp(tint, Colors.white, .65)!
        : Color.lerp(tint, const Color(0xFF101E38), .72)!;
    final ink = dark ? const Color(0xFFF1F5F2) : const Color(0xFF142E36);
    final muted = dark ? const Color(0xFFC2D1D1) : const Color(0xFF42565C);
    final surface = Color.lerp(paper, tint, dark ? .14 : .17)!;
    final border = Color.lerp(surface, pigment, highContrast ? .83 : .16)!;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(21), side: BorderSide(color: border, width: .8),
    );
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      button: onTap != null, excludeSemantics: true, onTap: onTap,
      child: FvTactileScale(
        enabled: onTap != null,
        child: Material(
          color: surface, shape: shape, clipBehavior: Clip.antiAlias,
          child: InkWell(
              customBorder: shape, onTap: onTap,
              hoverColor: tint.withValues(alpha: .10),
              splashColor: tint.withValues(alpha: .14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 151),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 37, height: 37,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11),
                          color: dark ? Color.lerp(tint, Colors.white, .48) : pigment),
                        alignment: Alignment.center,
                        child: RetailIcon(icon, size: 24,
                          ink: dark ? const Color(0xFF14233A) : Colors.white,
                          accent: dark ? tint : Color.lerp(tint, Colors.white, .28)!),
                      ),
                      const Spacer(),
                      if (onTap != null) Icon(Icons.north_east_rounded, size: 15, color: pigment),
                    ]),
                    const SizedBox(height: 14),
                    Text(label, style: t.textTheme.labelMedium?.copyWith(
                      color: pigment, fontWeight: FontWeight.w600, height: 1.2)),
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: still ? Duration.zero : const Duration(milliseconds: 190),
                        switchInCurve: Curves.easeOutCubic,
                        child: Text(value, key: ValueKey(value), maxLines: 1,
                          style: t.textTheme.headlineSmall?.copyWith(
                            color: tone ?? ink, fontSize: 27, fontFamily: 'Inter',
                            height: 1.15, fontWeight: FontWeight.w600, letterSpacing: -1.1,
                            fontFeatures: const [FontFeature.tabularFigures()])))),
                    if (detail != null) ...[
                      const SizedBox(height: 5),
                      Text(detail!, style: t.textTheme.bodySmall?.copyWith(
                        color: muted, height: 1.28, fontSize: 12)),
                    ],
                  ]),
                ),
              ),
          ),
        ),
      ),
    );
  }
}


/// Floating navigation for the compact retail shell.
class RetailPremiumBottomDock extends StatelessWidget {
  const RetailPremiumBottomDock({
    super.key,
    required this.current,
    required this.items,
    required this.onNavigate,
    required this.onMore,
  });
  final String current;
  final List<(String, String, IconData)> items;
  final ValueChanged<String> onNavigate;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final destinations = [...items, ('more', 'Más', Icons.more_horiz_rounded)];
    final active = items.any((item) => item.$1 == current) ? current : 'more';
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: 11, height: 1.15, letterSpacing: -.12, fontWeight: FontWeight.w700,
    );
    final widths = <double>[];
    for (final item in destinations) {
      final painter = TextPainter(
        text: TextSpan(text: item.$2, style: labelStyle),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      widths.add(math.max(48.0, painter.width.ceilToDouble() + 8));
      painter.dispose();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 8),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: FvFloatingGlassDock(
              key: const ValueKey('bodega-premium-bottom-dock'),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final total = widths.reduce((a, b) => a + b);
                  final capacity = total <= width ? destinations.length :
                      math.max(1, (width / widths.reduce(math.max)).floor());
                  final rows = (destinations.length / capacity).ceil();
                  final columns = (destinations.length / rows).ceil();
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < destinations.length; i += columns)
                      _DockLane(
                        destinations: destinations.skip(i).take(columns).toList(),
                        widths: widths.skip(i).take(columns).toList(),
                        width: width,
                        height: math.max(54, 32 + scaler.scale(11) * 1.15),
                        active: active,
                        labelStyle: labelStyle,
                        onTap: (id) => id == 'more' ? onMore() : onNavigate(id),
                      ),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockLane extends StatelessWidget {
  const _DockLane({
    required this.destinations,
    required this.widths,
    required this.width,
    required this.height,
    required this.active,
    required this.labelStyle,
    required this.onTap,
  });

  final List<(String, String, IconData)> destinations;
  final List<double> widths;
  final double width, height;
  final String active;
  final TextStyle labelStyle;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final selected = destinations.indexWhere((item) => item.$1 == active);
    final extra = (width - widths.reduce((a, b) => a + b)) / widths.length;
    final edges = [0.0];
    for (final preferred in widths.take(widths.length - 1)) {
      edges.add(edges.last + preferred + extra);
    }
    edges.add(width);
    return SizedBox(
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        if (selected >= 0)
          AnimatedPositionedDirectional(
            key: const ValueKey('retail-dock-selection'),
            duration: Motion.d(context, const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            top: 1,
            bottom: 1,
            start: edges[selected] + 1,
            width: edges[selected + 1] - edges[selected] - 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: contrast ? theme.colorScheme.primaryContainer : null,
                gradient: contrast ? null : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0, .55, 1],
                  colors: dark
                      ? const [Color(0xFF275868), Color(0xFF1B485E), Color(0xFF28475F)]
                      : const [Color(0xFFBAF4E3), Color(0xFF85DECA), Color(0xFFC7E9F4)],
                ),
                border: Border.all(color: contrast ? theme.colorScheme.outline :
                    dark ? const Color(0xA280BCAD) : const Color(0xE8EAFBF1)),
                boxShadow: contrast ? null : const [
                  BoxShadow(color: Color(0x28203D38), blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        Material(
          type: MaterialType.transparency,
          child: Row(children: [
            for (var i = 0; i < destinations.length; i++)
              SizedBox(
                width: edges[i + 1] - edges[i],
                height: height,
                child: _DockDestination(
                  item: destinations[i],
                  selected: i == selected,
                  labelStyle: labelStyle,
                  onTap: () => onTap(destinations[i].$1),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.item,
    required this.selected,
    required this.labelStyle,
    required this.onTap,
  });
  final (String, String, IconData) item;
  final bool selected;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final ink = contrast
        ? (selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface)
        : selected
            ? (dark ? const Color(0xFFE4FFF1) : const Color(0xFF10483B))
            : (dark ? const Color(0xFFE2ECEB) : const Color(0xFF304644));
    void activate() {
      HapticFeedback.selectionClick();
      onTap();
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.$2,
      onTap: activate,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('bodega-dock-${item.$1}'),
        borderRadius: BorderRadius.circular(26),
        onTap: activate,
        child: FvTactileScale(
          pressedScale: .96,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            RetailIcon(item.$3, ink: ink, size: selected ? 24 : 23,
              accent: contrast ? ink.withValues(alpha: .42)
                  : dark ? const Color(0xFF45969B) : const Color(0xFF84C8C1)),
            const SizedBox(height: 3),
            Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: labelStyle.copyWith(color: ink)),
          ]),
        ),
      ),
    );
  }
}
