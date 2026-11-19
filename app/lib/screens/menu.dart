// Menú comercial limpio: únicamente herramientas realmente autorizadas.
// La comparación comercial se consulta voluntariamente desde Mi plan.
import 'package:flutter/material.dart';

import '../access.dart';
import '../logic/search_score.dart';
import '../rubros.dart' show RubroArea;
import '../ux/commerce_navigation.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ux/rubro_experience.dart';
import 'catalog.dart';
import 'license_gate.dart' show PlanScreen;

// Conservado por compatibilidad con Ajustes y pruebas antiguas.
// No se utiliza para anunciar funciones bloqueadas en el Menú Básico.
String upgradeLabel(FeatureEntry f) => 'No incluida en tu plan actual';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}


class _MenuScreenState extends State<MenuScreen> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    Access.instance.addListener(_accessChanged);
  }

  void _accessChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    Access.instance.removeListener(_accessChanged);
    super.dispose();
  }

  void _open(FeatureEntry f) => openBasicCommerceFeature(context, f);

  Widget _tile(FeatureEntry f) {
    final c = featureColor(f.id);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
        child: Icon(f.icon, color: c, size: 21),
      ),
      title: Text(f.title),
      subtitle: Text(f.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () => _open(f),
    );
  }

  Widget _section(String key, String title, List<FeatureEntry> features, {bool initiallyExpanded = false}) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: PageStorageKey<String>('menu-$key'),
          initiallyExpanded: initiallyExpanded,
          maintainState: false,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          title: Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text('${features.length} ${features.length == 1 ? 'herramienta' : 'herramientas'} · toca para ver opciones',
              style: t.textTheme.bodySmall),
          children: [for (final f in features) _tile(f)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final guide = experienceFor('bodega');
    final all = featureCatalog().where((f) =>
        commerceEntryVisible(id: f.id, hubPlan: Access.instance.license.plan, roleOk: f.roleOk, planOk: f.planOk)).toList();
    final byId = {for (final f in all) f.id: f};
    final areas = [
      for (final g in groupOrder) RubroArea(g, [for (final f in all) if (f.group == g) f.id]),
    ];
    final q = _q.trim();
    final hits = q.isEmpty
        ? const <FeatureEntry>[]
        : (all.map((f) => (f, matchScore(q, f.title, extra: [f.subtitle, ...f.keywords])))
              .where((x) => x.$2 > 0).toList()
            ..sort((a, b) => b.$2.compareTo(a.$2)))
            .map((x) => x.$1).take(20).toList();
    final priorities = <FeatureEntry>[];
    for (final id in const ['pos', 'productos', 'caja']) {
      final f = byId[id];
      if (f != null && !priorities.any((x) => x.id == id)) priorities.add(f);
      if (priorities.length == 3) break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Herramientas de tu negocio')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          ListTile(
            leading: const Icon(Icons.workspace_premium_rounded),
            title: Text(commerceExperience(commerceViewPlan(Access.instance.license.plan))),
            subtitle: Text(basicLocalPreview
                ? 'Vista local B1 · el Hub y los datos reales no cambian'
                : 'Mi plan · capacidades verificadas por Solvex Hub'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => pushPremium(context, const PlanScreen()),
          ),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: '¿Qué necesitas hacer?',
              suffixIcon: !Access.instance.has('voz') ? null : IconButton(
                tooltip: 'Buscar por voz',
                icon: const Icon(Icons.mic_rounded),
                onPressed: () => openUniversalSearch(context, voice: true),
              ),
            ),
            onChanged: (v) => setState(() => _q = v),
            onSubmitted: (v) {
              if (hits.isEmpty && v.trim().isNotEmpty) openUniversalSearch(context);
            },
          ),
          const SizedBox(height: 16),
          if (q.isNotEmpty) ...[
            Text(hits.isEmpty ? 'Sin resultados en tus herramientas' : 'Resultados (${hits.length})', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (hits.isEmpty)
              SoftCard(child: ListTile(
                leading: const Icon(Icons.manage_search_rounded),
                title: const Text('Buscar clientes o comprobantes'),
                subtitle: const Text('Prueba con un nombre, número o palabra clave.'),
                onTap: () => openUniversalSearch(context),
              ))
            else
              SoftCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [for (final f in hits) _tile(f)])),
          ] else ...[
            Text(guide.menuSubtitle, style: t.textTheme.bodyMedium),
            if (priorities.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Acciones de todos los días', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final f in priorities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: CircleAvatar(
                        backgroundColor: featureColor(f.id).withValues(alpha: 0.13),
                        child: Icon(f.icon, color: featureColor(f.id)),
                      ),
                      title: Text(shortActionLabel(f.id, f.title), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      subtitle: Text(f.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => _open(f),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            SoftCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                key: PageStorageKey<String>('how-to-commerce'),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.help_outline_rounded, color: Brand.indigo),
                title: const Text('¿Primera vez? Empieza aquí'),
                subtitle: const Text('Tres pasos para organizar tu día'),
                children: [
                  for (final (i, step) in guide.steps.indexed)
                    ListTile(
                      leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                      title: Text(step),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Todas tus herramientas', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(basicLocalPreview
                ? 'Accesos propuestos para Básico. Las operaciones sin licencia real quedan protegidas.'
                : 'Solo ves las herramientas disponibles para tu negocio.',
                style: t.textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final (i, area) in areas.indexed)
              if (area.features.any(byId.containsKey))
                _section(
                  'commerce-$i',
                  commerceMenuGroup(area.title),
                  [for (final id in area.features) if (byId[id] case final f?) f],
                  initiallyExpanded: i == 0,
                ),
          ],
        ],
      ),
    );
  }
}
