import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// Editorial palette: neutral foundations with restrained functional color.
/// These tones identify actions, never replace their text labels.
abstract final class RetailAccent {
  static const ink = Color(0xFF18243A);
  static const teal = Color(0xFF087D79);
  static const blue = Color(0xFF285DA8);
  static const violet = Color(0xFF6552A3);
  static const amber = Color(0xFFC36F24);
  static const mint = Color(0xFF12866D);
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
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final ink = theme.colorScheme.onSurface;
    final surface = theme.colorScheme.surface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final cardRadius = BorderRadius.circular(30);
    final glass = highContrast ? 1.0 : dark ? .76 : .86;
    final primary = dark ? const Color(0xFF80D9C9) : RetailAccent.teal;

    return Semantics(
      container: true,
      label: 'Resumen operativo de la bodega',
      child: Container(
        key: const ValueKey('bodega-enterprise-overview'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: cardRadius,
          border: Border.all(color: dark
              ? const Color(0xFF515563) : Colors.white, width: 1.1),
          boxShadow: FvTokens.shadow(theme.brightness),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: dark
              ? const [Color(0xFF223041), Color(0xFF18272C), Color(0xFF151920)]
              : const [Color(0xFFE5EDFF), Color(0xFFE4F6F3), Color(0xFFF8F6FF)],
            stops: const [0, .55, 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _AccentIcon(icon: Icons.storefront_rounded,
                tint: RetailAccent.blue, size: 47),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TU TIENDA HOY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted, fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
                  const SizedBox(height: 3),
                  Text(name.isEmpty ? 'Tu negocio' : name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: ink, fontWeight: FontWeight.w800,
                      letterSpacing: -.6)),
                ],
              )),
              Tooltip(
                message: loaded ? 'Datos del servidor verificados'
                    : 'Esperando datos del servidor',
                child: _AccentIcon(
                  icon: loaded ? Icons.verified_rounded : Icons.schedule_rounded,
                  tint: loaded ? RetailAccent.mint : RetailAccent.muted,
                  size: 38),
              ),
            ]),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: Colors.white.withValues(alpha: dark ? .13 : .85)),
                color: surface.withValues(alpha: glass),
              ),
              padding: const EdgeInsets.fromLTRB(17, 17, 17, 15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(showMonth ? 'Ventas de este mes' : 'Tu actividad',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 7),
                if (showMonth)
                  loaded
                    ? Text('$currencySymbol ${salesAmount.toStringAsFixed(2)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: ink, fontWeight: FontWeight.w800,
                          fontSize: 36, letterSpacing: -1.7,
                          fontFeatures: const [FontFeature.tabularFigures()]))
                    : Text('—', style: theme.textTheme.headlineMedium)
                else
                  Text('Operaciones del negocio',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (loaded)
                    _MiniFact(icon: Icons.receipt_long_rounded,
                      label: salesCount == 1 ? '1 venta emitida'
                          : '$salesCount ventas emitidas',
                      tint: RetailAccent.blue),
                  if (todayAmount != null)
                    _MiniFact(icon: Icons.calendar_today_rounded,
                      label: 'Hoy $currencySymbol ${todayAmount!.toStringAsFixed(2)}',
                      tint: RetailAccent.teal)
                  else if (todayCount != null && !showMonth)
                    _MiniFact(icon: Icons.today_rounded,
                      label: 'Hoy $todayCount ventas',
                      tint: RetailAccent.teal),
                  if (loaded && drafts > 0)
                    _MiniFact(icon: Icons.edit_note_rounded,
                      label: '$drafts ${drafts == 1 ? 'borrador' : 'borradores'}',
                      tint: RetailAccent.violet),
                ]),
              ]),
            ),
            if (showMonth && loaded && chart != null) ...[
              const SizedBox(height: 20),
              Row(children: [
                Icon(Icons.show_chart_rounded, size: 18, color: primary),
                const SizedBox(width: 7),
                Expanded(child: Text('Tendencia · últimos 14 días',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 10),
              SizedBox(height: 56, child: chart),
            ],
            if (showMonth) ...[
              const SizedBox(height: 16),
              Material(
                color: surface.withValues(alpha: glass),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  key: const ValueKey('bodega-goal-action'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onGoal();
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Icon(Icons.flag_outlined, size: 20, color: primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(goalPercent == null
                            ? 'Establecer meta del mes' : 'Meta mensual',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: ink, fontWeight: FontWeight.w700))),
                        if (goalPercent != null)
                          Text('${(goalPercent! * 100).round()}%',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: ink, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 5),
                        Icon(Icons.chevron_right_rounded, size: 20, color: muted),
                      ]),
                      if (goalPercent != null) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: goalPercent!.clamp(0.0, 1.0),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(8),
                          color: primary,
                          backgroundColor: primary.withValues(alpha: .13),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.icon, required this.label, required this.tint});
  final IconData icon;
  final String label;
  final Color tint;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.colorScheme.surface.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: t.colorScheme.onSurface))),
        ]),
      ),
    );
  }
}

class _AccentIcon extends StatelessWidget {
  const _AccentIcon({required this.icon, required this.tint, this.size = 45});
  final IconData icon;
  final Color tint;
  final double size;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .31),
        color: dark ? tint.withValues(alpha: .24) : tint.withValues(alpha: .12),
        border: Border.all(color: Colors.white.withValues(alpha: dark ? .12 : .75)),
      ),
      child: Icon(icon, size: size * .51, color: dark
          ? Color.lerp(tint, Colors.white, .35)! : tint),
    );
  }
}

/// Quick actions have one source of navigation truth: the containing MainShell.
class RetailHomeQuickActions extends StatelessWidget {
  const RetailHomeQuickActions({
    super.key, required this.onNavigate,
    required this.allowed,
  });
  final ValueChanged<String> onNavigate;
  final Set<String> allowed;

  @override
  Widget build(BuildContext context) {
    const items = <(String, String, IconData, Color)>[
      ('sell', 'Ventas', Icons.shopping_cart_outlined, RetailAccent.teal),
      ('stock', 'Inventario', Icons.inventory_2_outlined, RetailAccent.violet),
      ('comprobantes', 'Comprobantes', Icons.receipt_long_outlined, RetailAccent.blue),
      ('cash', 'Caja', Icons.point_of_sale_outlined, RetailAccent.amber),
      ('fiados', 'Fiados', Icons.account_balance_wallet_outlined, RetailAccent.violet),
    ];
    final visible = items.where((item) => allowed.contains(item.$1)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 104,
      child: ListView(
        key: const ValueKey('retail-home-shortcuts'),
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (id, label, icon, tint) in visible)
            Padding(
              padding: const EdgeInsets.only(right: 13),
              child: SizedBox(
                width: 88,
                child: Semantics(
                  button: true, label: 'Abrir $label',
                  child: InkWell(
                    key: ValueKey('retail-home-quick-$id'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onNavigate(id);
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Column(children: [
                      _AccentIcon(icon: icon, tint: tint, size: 58),
                      const SizedBox(height: 8),
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Colored dashboard tile used solely for the retail operational overview.
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
    final ink = t.colorScheme.onSurface;
    final effective = dark ? Color.lerp(tint, Colors.white, .25)! : tint;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 158),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: dark
              ? [t.colorScheme.surface, tint.withValues(alpha: .21)]
              : [Colors.white, tint.withValues(alpha: .11)],
        ),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: .10) : Colors.white,
          width: 1),
        boxShadow: FvTokens.shadow(t.brightness),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _AccentIcon(icon: icon, tint: tint, size: 43),
          const Spacer(),
          if (onTap != null) Icon(Icons.arrow_outward_rounded,
            color: effective.withValues(alpha: .7), size: 17),
        ]),
        const SizedBox(height: 11),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: t.textTheme.labelSmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
            fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1,
            style: t.textTheme.headlineSmall?.copyWith(
              color: tone ?? ink, fontSize: 25,
              fontWeight: FontWeight.w800, letterSpacing: -.6,
              fontFeatures: const [FontFeature.tabularFigures()]))),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(fontSize: 11)),
        ],
      ]),
    );
    return Semantics(
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent, borderRadius: BorderRadius.circular(23),
        child: InkWell(
          borderRadius: BorderRadius.circular(23), onTap: onTap,
          child: body),
      ),
    );
  }
}
