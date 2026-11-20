import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// UI de una deuda existente. No registra cargos, abonos ni recordatorios.
class FvCreditBalanceCard extends StatelessWidget {
  const FvCreditBalanceCard({
    super.key,
    required this.name,
    required this.amount,
    required this.hasBalance,
    this.dueLabel,
    this.lastMovement,
    this.overdue = false,
    this.overLimit = false,
  });

  final String name;
  final String amount;
  final bool hasBalance;
  final String? dueLabel;
  final String? lastMovement;
  final bool overdue;
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final tone = !hasBalance
        ? (dark ? FvTokens.emeraldDark : FvLuxe.jade)
        : overdue || overLimit
            ? t.colorScheme.error
            : (dark ? const Color(0xFFFFC58B) : FvLuxe.gold);
    final state = !hasBalance ? 'Al día'
        : overdue ? 'Vencido'
        : overLimit ? 'Sobre el límite' : 'Pendiente';

    return Semantics(
      container: true,
      label: '$name, $state, saldo $amount',
      child: DecoratedBox(
        decoration: FvSurfaces.card(t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: dark
                          ? FvLuxe.blue.withValues(alpha: .25)
                          : FvLuxe.blueSoft,
                      borderRadius: BorderRadius.circular(17)),
                    child: Icon(Icons.person_outline_rounded,
                      size: 25, color: dark
                          ? t.colorScheme.onSurface : FvLuxe.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.25)),
                      const SizedBox(height: 6),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(!hasBalance ? Icons.check_circle_rounded
                            : overdue ? Icons.error_outline_rounded
                            : Icons.schedule_rounded,
                          size: 15, color: tone),
                        const SizedBox(width: 5),
                        Flexible(child: Text(state,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelMedium?.copyWith(
                            color: tone, fontWeight: FontWeight.w800))),
                      ]),
                    ],
                  )),
                ],
              ),
              if (lastMovement != null && lastMovement!.isNotEmpty) ...[
                const SizedBox(height: 11),
                Text('Último movimiento · $lastMovement',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant)),
              ],
              if (hasBalance && dueLabel != null && dueLabel!.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(dueLabel!, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: overdue ? t.colorScheme.error
                        : t.colorScheme.onSurfaceVariant,
                    fontWeight: overdue ? FontWeight.w700
                        : FontWeight.w500)),
              ],
              if (hasBalance && overLimit) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 16,
                    color: t.colorScheme.error),
                  const SizedBox(width: 5),
                  Expanded(child: Text('Se superó el límite de crédito',
                    style: t.textTheme.labelSmall?.copyWith(
                      color: t.colorScheme.error,
                      fontWeight: FontWeight.w700))),
                ]),
              ],
              const SizedBox(height: 13),
              Divider(height: 1, color: t.colorScheme.outlineVariant),
              const SizedBox(height: 11),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: Text(hasBalance
                      ? 'SALDO PENDIENTE' : 'SALDO PAGADO',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800, letterSpacing: 1.0))),
                const SizedBox(width: 8),
                Flexible(child: Text(amount, maxLines: 1,
                  overflow: TextOverflow.ellipsis, textAlign: TextAlign.end,
                  style: t.textTheme.titleLarge?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.65,
                    fontFeatures: const [FontFeature.tabularFigures()]))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
