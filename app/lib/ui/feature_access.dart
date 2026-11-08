import 'package:flutter/material.dart';

import '../access.dart';
import '../screens/license_gate.dart' show PlanScreen;
import 'motion.dart';

Future<void> showUpgradeDialog(BuildContext context) async {
  final viewPlans = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Actualiza tu plan'),
      content: const Text('Esta función no está incluida en tu plan actual.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ver planes')),
      ],
    ),
  );
  if (viewPlans == true && context.mounted) {
    await pushPremium(context, const PlanScreen());
  }
}

/// Rechecks an open route on license/role changes. The protected child is
/// unmounted on revocation, so it cannot keep displaying the previous grant.
class FeatureAccessGate extends StatelessWidget {
  const FeatureAccessGate({super.key, required this.roleAllowed,
    required this.planAllowed, required this.builder, this.requiresLicense = true});
  final bool Function() roleAllowed;
  final bool Function() planAllowed;
  final WidgetBuilder builder;
  final bool requiresLicense;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Access.instance,
    builder: (context, _) {
      final verified = !requiresLicense || Access.instance.licenseReady;
      final role = roleAllowed();
      if (verified && role && planAllowed()) return Builder(builder: builder);
      return Scaffold(
        appBar: AppBar(title: const Text('Acceso a la herramienta')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline_rounded, size: 36),
            const SizedBox(height: 16),
            Text(!verified ? 'Tu licencia necesita validación. Revisa Mi plan.'
                : !role ? 'Tu rol no tiene permiso para esta herramienta.'
                : 'Esta función no está incluida en tu plan actual.', textAlign: TextAlign.center),
            if (verified && role || !verified) TextButton(
              onPressed: () => pushPremium(context, const PlanScreen()),
              child: const Text('Ver planes'),
            ),
          ]),
        )),
      );
    },
  );
}
