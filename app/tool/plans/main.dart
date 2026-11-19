import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:facturavoz/ui/theme.dart';
import 'proposal.dart';

void main() {
  // A release/profile build of this target fails closed before rendering.
  if (!kDebugMode) throw UnsupportedError('Laboratorio solo debug/test');
  runApp(const PlansLab());
}

class PlansLab extends StatelessWidget {
  const PlansLab({super.key});
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return MaterialApp(theme: buildTheme(Brightness.dark), home: const LabScreen());
  }
}

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  TrialPlan plan = TrialPlan.basico;
  TrialRole role = TrialRole.propietario;
  bool menu = false, reached = false;

  Future<void> compare() => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('Comparación propuesta'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Solo desarrollo. Sin precios ni cambios en Hub.'),
      for (final p in TrialPlan.values) ListTile(title: Text(proposals[p]!.label),
        subtitle: Text('${proposals[p]!.experience}\n${proposals[p]!.users} usuarios · ${proposals[p]!.branches} sucursales\n${proposedFeatures.where((f) => f.minimum.index <= p.index).length} capacidades propuestas; incluye pendientes')),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
  ));

  Future<void> open(ProposedFeature f, TrialDecision decision) async {
    if (decision == TrialDecision.upgrade) {
      final next = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Actualiza tu plan'),
        content: Text('${f.name}: propuesta desde ${proposals[f.minimum]!.label}. No cambia tu licencia real.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ver planes'))],
      ));
      if (next == true && mounted) await compare();
      return;
    }
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(decision == TrialDecision.roleDenied ? 'Permiso de trabajador requerido'
        : decision == TrialDecision.limitReached ? 'Límite de prueba alcanzado' : f.name),
      content: SingleChildScrollView(child: Text(
        '${f.status}\n\nDestino existente: ${f.destination}\nArchivo: ${f.file}\nClave: ${f.key}\nPermiso: ${f.permission}\nIntegración: ${f.integration}\n\n'
        'INSPECCIÓN DE CONTRATO, NO PANTALLA OPERATIVA. Este laboratorio no abre servicios, no autentica ni registra operaciones. Los destinos reales se prueban desde la app normal con permisos reales.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = proposals[plan]!;
    final entries = menu ? proposedFeatures : trialHome(plan, role);
    return Scaffold(
      appBar: AppBar(title: const Text('Planes · laboratorio local')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('SIMULACIÓN · SIN NUBE NI OPERACIONES REALES', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        DropdownButtonFormField<TrialPlan>(initialValue: plan, decoration: const InputDecoration(labelText: 'Plan propuesto'),
          items: [for (final v in TrialPlan.values) DropdownMenuItem(value: v, child: Text(proposals[v]!.label))],
          onChanged: (v) => setState(() => plan = v!)),
        const SizedBox(height: 12),
        DropdownButtonFormField<TrialRole>(initialValue: role, decoration: const InputDecoration(labelText: 'Rol de prueba'),
          items: [for (final v in TrialRole.values) DropdownMenuItem(value: v, child: Text(v.name))],
          onChanged: (v) => setState(() => role = v!)),
        SwitchListTile(title: const Text('Límites alcanzados'), value: reached, onChanged: (v) => setState(() => reached = v)),
        Text('${p.experience} · ${p.users} usuarios · ${p.branches} sucursales'),
        TextButton(onPressed: compare, child: const Text('Comparar planes')),
        SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Inicio propuesto')),
          ButtonSegment(value: true, label: Text('Menú'))], selected: {menu}, onSelectionChanged: (v) => setState(() => menu = v.first)),
        const SizedBox(height: 12),
        const Text('Las fichas documentan destinos; no simulan funciones inexistentes.'),
        for (final f in entries) Builder(builder: (context) {
          final decision = trialDecision(f, plan, role, users: reached ? p.users : 0, branches: reached ? p.branches : 0);
          final subtitle = switch (decision) {
            TrialDecision.upgrade => 'Candado · desde ${proposals[f.minimum]!.label}',
            TrialDecision.roleDenied => 'Restringida por rol · sin oferta comercial',
            TrialDecision.limitReached => 'Límite alcanzado · ${f.limit}',
            _ => f.status,
          };
          return ListTile(key: ValueKey(f.id),
            leading: Icon(decision == TrialDecision.upgrade ? Icons.lock_outline : decision == TrialDecision.allowed ? Icons.description_outlined : Icons.info_outline),
            title: Text(f.name), subtitle: Text(subtitle), onTap: () => open(f, decision));
        }),
      ]),
    );
  }
}
