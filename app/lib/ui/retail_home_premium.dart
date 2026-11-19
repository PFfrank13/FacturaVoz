import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../growth.dart' show goalProgress;
import '../models.dart' show money, todayIso;
import 'design_tokens.dart';

/// Coloured dashboard, truthful KPI figures and no invented chart samples.
class RetailPremiumHero extends StatelessWidget {
  const RetailPremiumHero({
    super.key,
    required this.name, required this.currency, required this.total,
    required this.count, required this.loaded, required this.showMonth,
    required this.series, required this.goal, required this.onGoal,
    this.todayTotal, this.drafts = 0,
  });
  final String name, currency;
  final double total;
  final int count, drafts;
  final bool loaded, showMonth;
  final List<double> series;
  final double? goal, todayTotal;
  final VoidCallback onGoal;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final progress = goal != null && goal! > 0 && loaded
        ? goalProgress(goal: goal!, sales: total, today: todayIso())
        : null;
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Buenos días' :
        h < 19 ? 'Buenas tardes' : 'Buenas noches';
    return Semantics(
      container: true, label: 'Resumen operativo de la bodega',
      child: Column(
        key: const ValueKey('bodega-enterprise-overview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 16),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF28493F)
                      : const Color(0xFFE5F2EB),
                  borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.storefront_rounded, size: 25,
                    color: Color(0xFF36806B)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting, style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Text(name.isEmpty ? 'Tu tienda' : name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -.5)),
                ],
              )),
              Tooltip(
                message: loaded ? 'Resumen actualizado' : 'Cargando resumen',
                child: Container(
                  height: 36, width: 36,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF214438)
                        : const Color(0xFFE9F5EF),
                    shape: BoxShape.circle),
                  child: Icon(loaded ? Icons.verified_rounded
                      : Icons.sync_rounded, size: 19,
                      color: const Color(0xFF34836C)),
                ),
              ),
            ]),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(27),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1B2B35), Color(0xFF24514D), Color(0xFF29705D)
                ]),
              boxShadow: const [BoxShadow(
                color: Color(0x242C5B4D), blurRadius: 28,
                offset: Offset(0, 12))],
            ),
            child: Stack(children: [
              Positioned(
                right: -58, top: -80,
                child: IgnorePointer(child: Container(
                  height: 210, width: 210,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      Color(0x5958C49F), Color(0x0058C49F)
                    ]),
                  ),
                )),
              ),
              Positioned(
                left: -45, bottom: -110,
                child: IgnorePointer(child: Container(
                  height: 195, width: 195,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      Color(0x325A8BC9), Color(0x005A8BC9)
                    ]),
                  ),
                )),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(19, 18, 19, 15),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(child: Text('TU NEGOCIO · ESTE MES',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFFE0F4EC),
                          fontSize: 10.5, fontWeight: FontWeight.w700,
                          letterSpacing: .8))),
                      if (loaded)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(99)),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 9, vertical: 6),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.circle, size: 7,
                                  color: Color(0xFFB9EAD9)),
                              SizedBox(width: 5),
                              Text('Actualizado', style: TextStyle(
                                color: Colors.white, fontSize: 10.5,
                                fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    Text(showMonth ? 'Ventas del mes' : 'Tu actividad',
                      style: const TextStyle(
                        color: Color(0xFFD2E8E2), fontSize: 13)),
                    const SizedBox(height: 5),
                    if (showMonth && loaded)
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(money(total, currency),
                            key: const ValueKey('retail-home-real-month-total'),
                            style: const TextStyle(
                              color: Colors.white, fontSize: 38,
                              height: 1.17, fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              fontFeatures: [FontFeature.tabularFigures()]))),
                      )
                    else if (showMonth)
                      const Text('Cargando…', style: TextStyle(
                        color: Colors.white, fontSize: 26))
                    else
                      const Text('Tu jornada, de un vistazo',
                        style: TextStyle(color: Colors.white,
                          fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      if (loaded) _HeroChip(
                        icon: Icons.receipt_long_rounded,
                        label: count == 1 ? '1 venta emitida'
                            : '$count ventas emitidas'),
                      if (todayTotal != null)
                        _HeroChip(icon: Icons.today_rounded,
                          label: 'Hoy ${money(todayTotal!, currency)}'),
                      if (loaded && drafts > 0) _HeroChip(
                        icon: Icons.edit_note_rounded,
                        label: '$drafts borradores'),
                    ]),
                    const SizedBox(height: 15),
                    if (showMonth && loaded &&
                        series.length > 1 && series.any((v) => v > 0)) ...[
                      const Text('TENDENCIA · ÚLTIMOS 14 DÍAS',
                        style: TextStyle(color: Color(0xFFC8E2D9),
                          letterSpacing: .7, fontSize: 10)),
                      const SizedBox(height: 6),
                      SizedBox(height: 46, width: double.infinity,
                        child: CustomPaint(
                          painter: _RetailTrendPainter(values: series))),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          'La tendencia aparece con tus ventas reales.',
                          style: TextStyle(color: Color(0xFFBED9D0),
                            fontSize: 11.5))),
                    if (showMonth) ...[
                      const SizedBox(height: 12),
                      Divider(color: Colors.white.withValues(alpha: .19),
                          height: 1),
                      if (progress != null) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          const Expanded(child: Text('Meta mensual',
                            style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w600, fontSize: 12))),
                          Text('${(progress.percent * 100).round()}%',
                            style: const TextStyle(
                              color: Color(0xFFF4DDB6),
                              fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress.percent.clamp(0.0, 1.0),
                          borderRadius: BorderRadius.circular(9),
                          minHeight: 5,
                          backgroundColor: Colors.white.withValues(alpha: .16),
                          color: const Color(0xFFA9E7CD)),
                      ],
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onGoal();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.fromLTRB(0, 9, 4, 0),
                          foregroundColor: const Color(0xFFF6E0B8)),
                        icon: const Icon(Icons.flag_outlined, size: 17),
                        label: Text(progress == null ?
                            'Establecer meta del mes' : 'Editar meta',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFFC5EFDB), size: 13),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 10.5,
          fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _RetailTrendPainter extends CustomPainter {
  const _RetailTrendPainter({required this.values});
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    if (maxValue <= 0) return;
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = 4 + (size.height - 8) * (1 - values[i] / maxValue);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0x5055D4AC), Color(0x0055D4AC)],
      ).createShader(Offset.zero & size));
    canvas.drawPath(line, Paint()
      ..color = const Color(0xFFB4F5D7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }
  @override
  bool shouldRepaint(covariant _RetailTrendPainter old) =>
    old.values.length != values.length ||
    old.values.toString() != values.toString();
}

class RetailHomeShortcut {
  const RetailHomeShortcut(this.id, this.label, this.icon, this.accent);
  final String id, label;
  final IconData icon;
  final Color accent;
}

/// A single shell navigator handles navigation. These are merely shortcuts.
class RetailHomeShortcuts extends StatelessWidget {
  const RetailHomeShortcuts({
    super.key, required this.items, required this.onSelect,
  });
  final List<RetailHomeShortcut> items;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Accesos rápidos',
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: -.3))),
          Text('Desliza', style: t.textTheme.labelSmall),
          const SizedBox(width: 3),
          Icon(Icons.arrow_forward_ios_rounded, size: 11,
            color: t.colorScheme.onSurfaceVariant),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 114, child: ListView.separated(
          key: const ValueKey('retail-home-shortcuts'),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final item = items[i];
            final dark = t.brightness == Brightness.dark;
            return SizedBox(width: 110,
              child: Material(
                color: t.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  key: ValueKey('retail-home-open-${item.id}'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(item.id);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: t.colorScheme.outlineVariant.withValues(
                          alpha: dark ? .6 : .65), width: .7),
                      boxShadow: FvTokens.shadow(t.brightness)),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 43, height: 43,
                          decoration: BoxDecoration(
                            color: item.accent.withValues(
                              alpha: dark ? .22 : .13),
                            borderRadius: BorderRadius.circular(14)),
                          child: Icon(item.icon, size: 24,
                            color: item.accent),
                        ),
                        const Spacer(),
                        Text(item.label, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: t.colorScheme.onSurface,
                            fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        )),
      ]),
    );
  }
}
