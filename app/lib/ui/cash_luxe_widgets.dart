import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Presentation-only journey for the real cash day.
class FvCashJourney extends StatelessWidget {
  const FvCashJourney({
    super.key,
    required this.opened,
    required this.movements,
    required this.closed,
  });

  final bool opened;
  final int movements;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final stages = <_CashStage>[
      _CashStage(Icons.lock_open_rounded, 'Apertura',
          opened ? 'Realizada' : 'Pendiente', opened),
      _CashStage(Icons.swap_horiz_rounded, 'Movimientos',
          movements == 0 ? 'Sin registros' : '$movements registrados',
          movements > 0),
      _CashStage(Icons.fact_check_outlined, 'Arqueo',
          closed ? 'Completado' : 'Al cerrar', closed),
      _CashStage(Icons.verified_outlined, 'Cierre',
          closed ? 'Finalizado' : 'Pendiente', closed),
    ];
    return LayoutBuilder(builder: (context, limits) {
      final columns = limits.maxWidth >= 710 ? 4 : 2;
      const space = 9.0;
      final cardWidth = (limits.maxWidth - space * (columns - 1)) / columns;
      return Semantics(
        container: true,
        label: 'Etapas del control de caja',
        child: Wrap(spacing: space, runSpacing: space, children: [
          for (final (i, stage) in stages.indexed)
            SizedBox(
              width: cardWidth,
              child: _CashStageCard(index: i + 1, stage: stage),
            ),
        ]),
      );
    });
  }
}

class _CashStage {
  const _CashStage(this.icon, this.title, this.detail, this.complete);
  final IconData icon;
  final String title, detail;
  final bool complete;
}

class _CashStageCard extends StatelessWidget {
  const _CashStageCard({required this.index, required this.stage});
  final int index;
  final _CashStage stage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final tone = stage.complete
        ? (dark ? FvTokens.emeraldDark : FvLuxe.jade)
        : t.colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'Paso $index: ${stage.title}, ${stage.detail}',
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero : FvTokens.transition,
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.fromLTRB(12, 13, 11, 12),
        decoration: BoxDecoration(
          gradient: stage.complete ? FvLuxe.editorial(t.brightness) : null,
          color: stage.complete ? null : t.colorScheme.surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: stage.complete
                ? tone.withValues(alpha: .37)
                : t.colorScheme.outlineVariant,
            width: stage.complete ? 1.2 : .8,
          ),
          boxShadow: FvTokens.shadow(t.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(stage.complete ? Icons.check_circle_rounded : stage.icon,
              size: 23, color: tone),
            const SizedBox(height: 9),
            Text(stage.title, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(stage.detail, maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(color: tone)),
          ],
        ),
      ),
    );
  }
}

/// Intentionally contains NO expected cash amount before a blind closing.
class FvCashBlindPanel extends StatelessWidget {
  const FvCashBlindPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Arqueo ciego: saldo esperado oculto hasta cerrar caja',
      child: DecoratedBox(
        decoration: FvSurfaces.card(t),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: t.brightness == Brightness.dark
                    ? FvLuxe.blue.withValues(alpha: .23)
                    : FvLuxe.blueSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.visibility_off_rounded,
                color: t.brightness == Brightness.dark
                    ? t.colorScheme.onSurface : FvLuxe.blue),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Arqueo ciego', style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('El saldo esperado permanece oculto hasta cerrar caja y confirmar el conteo.',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant, height: 1.35)),
                ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Read-only movement row; never registers or changes cash.
class FvCashMovementTile extends StatelessWidget {
  const FvCashMovementTile({
    super.key,
    required this.kind,
    required this.label,
    required this.amount,
    this.time,
  });

  final String kind;
  final String label;
  final String amount;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final outgoing = kind == 'egreso';
    final opening = kind == 'apertura';
    final tone = outgoing ? t.colorScheme.error
        : opening ? (t.brightness == Brightness.dark
            ? FvTokens.emeraldDark : FvLuxe.blue)
        : t.colorScheme.primary;
    final icon = outgoing ? Icons.north_east_rounded
        : opening ? Icons.lock_open_rounded : Icons.south_west_rounded;
    return Semantics(
      container: true,
      label: '$label, $amount${time == null ? '' : ', $time'}',
      child: DecoratedBox(
        decoration: FvSurfaces.card(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
          child: Row(children: [
            Container(
              width: 45, height: 45,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: tone, size: 22),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700)),
                if (time != null && time!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 3),
                    child: Text(time!, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSurfaceVariant))),
              ],
            )),
            const SizedBox(width: 10),
            Flexible(child: Text(amount,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: t.colorScheme.onSurface))),
          ]),
        ),
      ),
    );
  }
}
