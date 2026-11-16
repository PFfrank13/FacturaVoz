// Recorrido de activación (Prompt Maestro §14). Orden REAL de la app: la licencia va antes que los datos de la
// empresa porque la base no permite escribir sin una licencia válida (license_guard). Cada pantalla dice en qué
// paso está y qué sigue.
import 'package:flutter/material.dart';

import 'theme.dart';

const onboardingSteps = <(String, String)>[
  ('Cuenta', 'Crea tu cuenta o inicia sesión.'),
  ('Plan y licencia', 'Elige tu plan y activa la licencia o la prueba gratis.'),
  ('Empresa', 'Nombre, RUC y datos que salen en tus comprobantes.'),
  ('Rubro', 'Tu tipo de negocio arma tu Inicio, tu menú y tus palabras.'),
  ('Inicio', 'Tu Inicio personalizado, listo para la primera venta.'),
];

/// [current] es 0-based dentro de [onboardingSteps].
class OnboardingSteps extends StatelessWidget {
  const OnboardingSteps({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ds = DsColors.of(context);
    final step = onboardingSteps[current];
    final next = current + 1 < onboardingSteps.length ? onboardingSteps[current + 1].$1 : null;
    return Semantics(
      label: 'Paso ${current + 1} de ${onboardingSteps.length}: ${step.$1}. ${next == null ? '' : 'Sigue: $next.'}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < onboardingSteps.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(height: 4, decoration: BoxDecoration(color: i <= current ? ds.primary : ds.line, borderRadius: BorderRadius.circular(Radii.pill))),
            ),
          ],
        ]),
        const SizedBox(height: Gap.sm),
        Text('Paso ${current + 1} de ${onboardingSteps.length} · ${step.$1}', style: t.textTheme.labelLarge?.copyWith(color: ds.primaryText)),
        const SizedBox(height: 2),
        Text(step.$2, style: t.textTheme.bodySmall),
        if (next != null) ...[
          const SizedBox(height: 2),
          Text('Después: $next', style: t.textTheme.bodySmall),
        ],
      ]),
    );
  }
}
