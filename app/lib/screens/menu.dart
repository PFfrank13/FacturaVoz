// Menú (E): la ÚNICA puerta a todas las funciones, ordenada por las áreas de TU rubro, con buscador de texto y voz.
//  - Lo que tu rol no permite: no aparece.
//  - Lo que tu plan no incluye: aparece con candado y "Disponible en el plan X" (toca para mejorar tu plan).
//  - Lo que no es de tu rubro: en "Otras funciones" (nada se borra).
import 'package:flutter/material.dart';

import '../access.dart';
import '../logic/search_score.dart';
import '../rubros.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'license_gate.dart' show PlanScreen;

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

/// Plan mínimo que trae la función (para el texto del candado).
String upgradeLabel(FeatureEntry f) {
  final code = f.feature == null ? null : minPlanFor(f.feature!, planFeatures);
  return code == null ? 'No incluido en tu plan' : 'Disponible en el plan ${planName(code)}';
}

class _MenuScreenState extends State<MenuScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final spec = rubroFor(Access.instance.rubro);
    final all = featureCatalog().where((f) => f.roleOk).toList();
    final byId = {for (final f in all) f.id: f};
    final areas = spec?.areas ?? [for (final g in groupOrder) RubroArea(g, [for (final f in all) if (f.group == g) f.id])];
    final shown = <String>{for (final a in areas) ...a.features};
    final others = all.where((f) => !shown.contains(f.id)).toList();
    final q = _q.trim();
    final hits = q.isEmpty
        ? const <FeatureEntry>[]
        : (all.map((f) => (f, matchScore(q, f.title, extra: [f.subtitle, ...f.keywords]))).where((x) => x.$2 > 0).toList()..sort((a, b) => b.$2.compareTo(a.$2)))
            .map((x) => x.$1)
            .take(12)
            .toList();

    Widget tile(FeatureEntry f) {
      final locked = !f.planOk;
      final c = groupColors[f.group] ?? Brand.indigo;
      return ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.withValues(alpha: locked ? 0.06 : 0.12), borderRadius: BorderRadius.circular(13)),
          child: Icon(locked ? Icons.lock_rounded : f.icon, color: locked ? t.colorScheme.outline : c, size: 21),
        ),
        title: Text(f.title, style: locked ? TextStyle(color: t.colorScheme.onSurfaceVariant) : null),
        subtitle: Text(locked ? upgradeLabel(f) : f.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: f.id == spec?.signature ? const Icon(Icons.star_rounded, color: Brand.warn) : const Icon(Icons.chevron_right_rounded),
        onTap: locked ? () => pushPremium(context, const PlanScreen()) : () => openFeature(context, f),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(spec == null ? 'Menú' : 'Menú · ${spec.name}')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Busca una función, cliente o comprobante',
            suffixIcon: IconButton(tooltip: 'Buscar hablando', icon: const Icon(Icons.mic_rounded), onPressed: () => openUniversalSearch(context, voice: true)),
          ),
          onChanged: (v) => setState(() => _q = v),
          onSubmitted: (v) {
            if (hits.isEmpty && v.trim().isNotEmpty) openUniversalSearch(context);
          },
        ),
        const SizedBox(height: 12),
        if (q.isNotEmpty) ...[
          if (hits.isEmpty)
            ListTile(leading: const Icon(Icons.manage_search_rounded), title: const Text('Buscar también en clientes y comprobantes'), onTap: () => openUniversalSearch(context))
          else
            SoftCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [for (final f in hits) tile(f)])),
        ] else ...[
          for (final (i, a) in areas.indexed)
            if (a.features.any(byId.containsKey)) ...[
              SectionTitle(a.title),
              Reveal(
                index: i,
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [for (final id in a.features) if (byId[id] case final f?) tile(f)]),
                ),
              ),
              const SizedBox(height: 10),
            ],
          if (others.isNotEmpty)
            SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ExpansionTile(
                shape: const Border(),
                leading: const Icon(Icons.apps_rounded),
                title: const Text('Otras funciones'),
                subtitle: Text('${others.length} que no son de tu rubro (siguen disponibles)'),
                children: [for (final f in others) tile(f)],
              ),
            ),
        ],
      ]),
    );
  }
}
