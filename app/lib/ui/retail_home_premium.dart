import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// Editorial palette: neutral foundations with restrained functional color.
/// These tones identify actions, never replace their text labels.
abstract final class RetailAccent {
  static const ink = Color(0xFF18243A);
  static const teal = FvLuxe.jade;
  static const blue = FvLuxe.blue;
  static const violet = Color(0xFF6552A3);
  static const amber = Color(0xFFC36F24);
  static const mint = FvLuxe.jade;
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
    final scheme = theme.colorScheme;
    final strong = MediaQuery.highContrastOf(context);
    const paper = Color(0xFFFBFCF6);
    const soft = Color(0xFFCBE4DB);
    final amount = '$currencySymbol ${salesAmount.toStringAsFixed(2)}';
    return Semantics(
      container: true,
      label: 'Resumen operativo de la bodega',
      child: Container(
        key: const ValueKey('bodega-enterprise-overview'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FvTokens.cardRadius),
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ColoredBox(color: FvLuxe.forest, child: CustomPaint(
            painter: FvEngraving(FvLuxe.mintInk.withValues(alpha: strong ? 0 : .16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.storefront_outlined, color: soft, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name.isEmpty ? 'Tu negocio' : name,
                    style: theme.textTheme.labelLarge?.copyWith(color: paper))),
                  Tooltip(message: loaded ? 'Datos cargados' : 'Esperando datos',
                    child: Icon(loaded ? Icons.check_circle_outline_rounded : Icons.schedule_rounded,
                      color: soft, size: 18)),
                ]),
                const SizedBox(height: 23),
                Text(showMonth ? 'Ventas de este mes' : 'Tu actividad',
                  style: theme.textTheme.labelMedium?.copyWith(color: soft)),
                const SizedBox(height: 3),
                if (showMonth)
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(loaded ? amount : '—', style: theme.textTheme.displaySmall?.copyWith(
                      color: paper, fontSize: 42, letterSpacing: -1.6,
                      fontFeatures: const [FontFeature.tabularFigures()]))),
                if (!showMonth)
                  Text('Operaciones del negocio', style: theme.textTheme.titleLarge?.copyWith(color: paper)),
                const SizedBox(height: 12),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  if (loaded) _MiniFact(icon: Icons.receipt_long_outlined,
                    label: salesCount == 1 ? '1 venta emitida' : '$salesCount ventas emitidas'),
                  if (todayAmount != null) _MiniFact(icon: Icons.today_outlined,
                    label: 'Hoy $currencySymbol ${todayAmount!.toStringAsFixed(2)}')
                  else if (todayCount != null && !showMonth)
                    _MiniFact(icon: Icons.today_outlined, label: 'Hoy $todayCount ventas'),
                  if (loaded && drafts > 0) _MiniFact(icon: Icons.edit_note_outlined,
                    label: '$drafts ${drafts == 1 ? 'borrador' : 'borradores'}'),
                ]),
              ]),
            ),
          )),
          if (showMonth && loaded && chart != null)
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Tendencia · últimos 14 días', style: theme.textTheme.labelMedium),
                const SizedBox(height: 10),
                SizedBox(height: 45, child: chart),
              ])),
          if (showMonth) ...[
            const Divider(),
            Material(color: Colors.transparent, child: InkWell(
              key: const ValueKey('bodega-goal-action'),
              onTap: () { HapticFeedback.selectionClick(); onGoal(); },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.flag_outlined, color: scheme.primary, size: 19),
                    const SizedBox(width: 10),
                    Expanded(child: Text(goalPercent == null ? 'Establecer meta del mes' : 'Meta mensual',
                      style: theme.textTheme.labelLarge)),
                    if (goalPercent != null) Text('${(goalPercent! * 100).round()}%'),
                    const Icon(Icons.chevron_right_rounded, size: 19),
                  ]),
                  if (goalPercent != null) Padding(padding: const EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(value: goalPercent!.clamp(0, 1))),
                ])),
            )),
          ],
        ]),
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 15, color: FvLuxe.mintInk),
    const SizedBox(width: 5),
    Flexible(child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white))),
  ]);
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
      ('stock', 'Inventario', Icons.inventory_2_outlined, RetailAccent.blue),
      ('comprobantes', 'Comprobantes', Icons.receipt_long_outlined, RetailAccent.blue),
      ('cash', 'Caja', Icons.point_of_sale_outlined, RetailAccent.amber),
      ('fiados', 'Fiados', Icons.account_balance_wallet_outlined, RetailAccent.teal),
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
    final still = MediaQuery.disableAnimationsOf(context);
    final body = Container(
      constraints: const BoxConstraints(minHeight: 158),
      padding: const EdgeInsets.all(15),
      decoration: FvSurfaces.card(t),
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
          child: AnimatedSwitcher(
            duration: still ? Duration.zero : const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .22),
                  end: Offset.zero).animate(animation),
                child: child)),
            child: Text(value, key: ValueKey(value), maxLines: 1,
            style: t.textTheme.headlineSmall?.copyWith(
              color: tone ?? ink, fontFamily: 'Inter', fontSize: 25,
              fontWeight: FontWeight.w800, letterSpacing: -.6,
              fontFeatures: const [FontFeature.tabularFigures()])))),
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
      onTap: onTap,
      child: Material(
        color: Colors.transparent, borderRadius: BorderRadius.circular(23),
        child: InkWell(
          borderRadius: BorderRadius.circular(23), onTap: onTap,
          child: body),
      ),
    );
  }
}


/// iOS-style bottom glass navigation for compact retail screens.
/// The same MainShell still owns all navigation and permissions.
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
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final ink = t.colorScheme.onSurface;
    final selectedTint = dark ? FvTokens.emeraldDark : FvLuxe.jade;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
        child: Container(
          key: const ValueKey('bodega-premium-bottom-dock'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: FvTokens.shadow(t.brightness),
          ),
          child: FvGlassSurface(
            radius: 32, blur: 20,
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: SizedBox(
              height: 44 + MediaQuery.textScalerOf(context).scale(14),
              child: Row(children: [
                for (final item in items)
                  Expanded(
                    child: _DockDestination(
                      id: item.$1,
                      label: item.$2,
                      icon: item.$3,
                      current: current,
                      tint: selectedTint,
                      ink: ink,
                      onTap: () => onNavigate(item.$1),
                    ),
                  ),
                Expanded(child: _DockDestination(
                  id: 'more',
                  label: 'Más',
                  icon: Icons.more_horiz_rounded,
                  current: current,
                  tint: selectedTint,
                  ink: ink,
                  onTap: onMore,
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.id, required this.label, required this.icon,
    required this.current, required this.tint, required this.ink,
    required this.onTap,
  });
  final String id, label, current;
  final Color tint, ink;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = id == current;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        key: ValueKey('bodega-dock-$id'),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(21),
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: selected ? LinearGradient(
              colors: [tint.withValues(alpha: .21), tint.withValues(alpha: .11)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedScale(
              scale: selected ? 1.09 : 1,
              duration: still ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(icon, size: 22,
                color: selected ? tint : ink.withValues(alpha: .78))),
            const SizedBox(height: 3),
            Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: selected ? tint : ink.withValues(alpha: .78),
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
