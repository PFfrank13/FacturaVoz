// Comparación de planes (Prompt Maestro §7): Básico · Pro · Empresa con Pro como protagonista.
// Las funciones salen de planMatrix (copia de private.plan_matrix) y los precios de planPrices
// (docs/facturavoz-planes.json, probados en plan_prices_test). Lo que se cobra de verdad lo decide Solvex Hub:
// aquí no se inventan precios, insignias de popularidad ni funciones.
import 'package:flutter/material.dart';

import '../rubros.dart';
import 'license_gate.dart' show featureName;

class PlanCompare extends StatelessWidget {
  const PlanCompare({super.key, required this.rubro, required this.currentPlan, this.onChoose});

  final String? rubro;
  final String currentPlan;

  /// Solo se pasa si el usuario puede gestionar la suscripción (propietario).
  final void Function(String plan)? onChoose;

  static const recommended = 'PRO';

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final code in planCodes)
        _PlanCard(
          code: code,
          rubro: rubro,
          current: code == currentPlan,
          highlighted: code == recommended,
          onChoose: onChoose == null || code == currentPlan ? null : () => onChoose!(code),
        ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 720) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, w) in cards.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(flex: planCodes[i] == recommended ? 6 : 5, child: w),
            ],
          ]),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, w) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          w,
        ],
      ]);
    });
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.code, required this.rubro, required this.current, required this.highlighted, this.onChoose});

  final String code;
  final String? rubro;
  final bool current;
  final bool highlighted;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final tools = planNewTools(rubro, code);
    final prev = planCodes.indexOf(code) > 0 ? planName(planCodes[planCodes.indexOf(code) - 1]) : null;
    final price = planPriceText(code);
    return Container(
      key: ValueKey('plan-card-$code'),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlighted ? cs.primary : cs.outlineVariant, width: highlighted ? 2 : 1),
      ),
      padding: EdgeInsets.fromLTRB(16, highlighted ? 14 : 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(planName(code), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          if (highlighted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(99)),
              child: Text('RECOMENDADO', style: TextStyle(color: cs.onPrimary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ),
        ]),
        if (price.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(price, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: highlighted ? cs.primary : null)),
          Text('Precio referencial con IGV. El cobro lo confirma Solvex.', style: t.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Text(prev == null ? 'Incluye' : 'Todo lo de $prev, más', style: t.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final k in tools)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(featureName(k), style: t.textTheme.bodyMedium)),
            ]),
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: current
              ? const OutlinedButton(onPressed: null, child: Text('Tu plan actual'))
              : onChoose == null
                  ? const SizedBox.shrink()
                  : highlighted
                      ? FilledButton(onPressed: onChoose, child: Text('Elegir ${planName(code)}'))
                      : OutlinedButton(onPressed: onChoose, child: Text('Elegir ${planName(code)}')),
        ),
      ]),
    );
  }
}
