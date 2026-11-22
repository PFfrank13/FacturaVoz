// Comparación de planes (Prompt Maestro §7): Básico · Pro · Empresa con Pro como protagonista.
// Las funciones salen de planMatrix (copia de private.plan_matrix) y los precios de planPrices
// (docs/facturavoz-planes.json, probados en plan_prices_test). Lo que se cobra de verdad lo decide Solvex Hub:
// aquí no se inventan precios ni funciones. Pro lleva «Más recomendado» (una recomendación, no
// una afirmación de ventas: no se dice «Más vendido» sin datos).
import 'package:flutter/material.dart';

import '../rubros.dart';
import '../ui/liquid_glass.dart';
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
        // Sin IntrinsicHeight (costoso): las tarjetas se alinean arriba.
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, w) in cards.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(flex: planCodes[i] == recommended ? 6 : 5, child: w),
          ],
        ]);
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

/// Funciones nuevas por plan sin rubro elegido (lista general de docs/facturavoz-planes.json).
List<String> _generalNewTools(String code) {
  bool on(String c, String k) => planFeatures[c]?[k] == true;
  final i = planCodes.indexOf(code);
  return [
    for (final k in allFeatureKeys)
      if (on(code, k) && (i == 0 || !on(planCodes[i - 1], k))) k,
  ];
}

String _pitch(String code) => switch (code) {
      'BASICO' => 'Lo esencial completo para operar tu negocio.',
      'PRO' => 'Más productividad: módulo estrella de tu rubro y Copiloto.',
      _ => 'Mayor escala: más usuarios y locales, control del dueño e integraciones.',
    };

/// Each plan carries its own light: ice for Básico, aurora for Pro, gold for Empresa.
(Color, Color) planLight(String code) => switch (code) {
      'BASICO' => (const Color(0xFF7CC8FF), const Color(0xFF3B6FD6)),
      'PRO' => (const Color(0xFF9B87FF), const Color(0xFF2FD8A8)),
      _ => (const Color(0xFFFFD27A), const Color(0xFFE08A2B)),
    };

Widget _chip(BuildContext context, IconData icon, String text) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: dark ? const Color(0x1FFFFFFF) : const Color(0xB3FFFFFF),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: dark ? const Color(0x26FFFFFF) : Colors.white),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface))),
    ]),
  );
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
    final dark = t.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final tools = rubro != null && planMatrix(rubro, code) != null ? planNewTools(rubro, code) : _generalNewTools(code);
    final lim = planLimits[code];
    final trial = planTrialDays[code] ?? 0;
    final star = rubro == null ? null : proStar[rubro];
    final prev = planCodes.indexOf(code) > 0 ? planName(planCodes[planCodes.indexOf(code) - 1]) : null;
    final price = planPrices[code];
    final (light, deep) = planLight(code);
    final accent = dark ? light : Color.lerp(deep, Colors.black, .15)!;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [light, deep]),
            boxShadow: [BoxShadow(color: light.withValues(alpha: .7), blurRadius: 10)],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(planName(code), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: highlighted ? 24 : 21))),
        if (highlighted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: contrast ? null : LinearGradient(colors: [light, deep]),
              color: contrast ? cs.primary : null,
              borderRadius: BorderRadius.circular(99),
              boxShadow: contrast ? null : [BoxShadow(color: light.withValues(alpha: .5), blurRadius: 14)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_rounded, size: 13, color: contrast ? cs.onPrimary : const Color(0xFF0B1424)),
              const SizedBox(width: 4),
              Text('MÁS RECOMENDADO', style: TextStyle(color: contrast ? cs.onPrimary : const Color(0xFF0B1424),
                fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: .6)),
            ]),
          ),
      ]),
      if (price != null) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('S/ ${price == price.roundToDouble() ? price.toStringAsFixed(0) : price.toStringAsFixed(2)}',
              style: TextStyle(fontFamily: 'Inter', fontSize: highlighted ? 44 : 36, height: 1,
                fontWeight: FontWeight.w800, letterSpacing: -1.8,
                color: highlighted && !contrast ? accent : cs.onSurface)),
          )),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('al mes', style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Precio referencial con IGV. El cobro lo confirma Solvex.', style: t.textTheme.bodySmall),
      ],
      const SizedBox(height: 10),
      Text(_pitch(code), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      if (code == 'PRO' && star != null) ...[
        const SizedBox(height: 4),
        Text('Módulo estrella de tu rubro: ${featureName(star)}', style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: accent)),
      ],
      if (lim != null) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(context, Icons.group_rounded, lim.users < 0 ? 'Usuarios sin límite' : lim.users == 1 ? '1 usuario' : '${lim.users} usuarios'),
          _chip(context, Icons.store_rounded, lim.branches < 0 ? 'Sucursales sin límite' : lim.branches == 1 ? '1 local' : '${lim.branches} locales'),
          if (trial > 0) _chip(context, Icons.card_giftcard_rounded, '$trial días de prueba'),
        ]),
      ],
      const SizedBox(height: 14),
      Text(prev == null ? 'Incluye' : 'Todo lo de $prev, más', style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final k in tools)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 18, height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: .18)),
              child: Icon(Icons.check_rounded, size: 13, color: accent),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(featureName(k), style: t.textTheme.bodyMedium)),
          ]),
        ),
      if (current || onChoose != null) ...[
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50, minWidth: double.infinity),
          child: current
              ? const OutlinedButton(onPressed: null, child: Text('Tu plan actual'))
              : highlighted
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: contrast ? null : [BoxShadow(color: light.withValues(alpha: .45), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: FilledButton(
                        style: contrast ? null : FilledButton.styleFrom(
                          backgroundColor: dark ? const Color(0xFF3EE6B0) : const Color(0xFF0E8C74),
                          foregroundColor: dark ? const Color(0xFF04201A) : Colors.white,
                          minimumSize: const Size(64, 52),
                        ),
                        onPressed: onChoose,
                        child: Text('Elegir ${planName(code)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    )
                  : OutlinedButton(onPressed: onChoose, child: Text('Elegir ${planName(code)}')),
        ),
      ],
    ]);
    final card = FvLiquidGlass(
      radius: 28,
      blur: 0,
      tint: light,
      strength: highlighted ? (dark ? 1.9 : 1.6) : (dark ? 1.5 : 1.4),
      padding: EdgeInsets.fromLTRB(18, highlighted ? 20 : 18, 18, 18),
      child: content,
    );
    if (!highlighted || contrast) return KeyedSubtree(key: ValueKey('plan-card-$code'), child: card);
    // Pro: a lit gradient rim and a soft spring entrance set it above the others.
    return TweenAnimationBuilder<double>(
      key: ValueKey('plan-card-$code'),
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(
        scale: .96 + .04 * v,
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [light, Colors.white.withValues(alpha: .7), deep],
          ),
          boxShadow: [
            BoxShadow(color: light.withValues(alpha: dark ? .35 : .28), blurRadius: 34, spreadRadius: -6, offset: const Offset(0, 14)),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(1.6), child: card),
      ),
    );
  }
}
