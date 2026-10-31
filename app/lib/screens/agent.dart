// Tareas del Copiloto (plan Empresa): le encargas algo, el Copiloto lo PREPARA con tus datos reales y tú lo APRUEBAS.
// Nada se hace sin tu aprobación. Lo único que escribe son recordatorios (reversibles); no envía mensajes, no cobra,
// no emite a SUNAT y no borra nada.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../models.dart';
import '../services/pro_api.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _text = TextEditingController();
  List<Map<String, dynamic>>? _tasks;
  String _error = '';
  bool _busy = false;
  String? _working;

  static const _ideas = [
    'Prepara los mensajes de cobro para los que más me deben',
    'Arma la lista de compras de lo que se está acabando',
    'Programa recordatorios de cobro para dentro de 3 días',
    'Hazme el resumen de la semana',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var q = Supabase.instance.client.from('agent_tasks').select('id, title, prompt, status, plan, result, created_at');
      final org = Repo.activeOrgId;
      if (org != null) q = q.eq('org_id', org);
      final rows = await q.order('created_at', ascending: false).limit(30);
      if (mounted) setState(() => _tasks = [for (final r in rows as List) Map<String, dynamic>.from(r as Map)]);
    } catch (_) {
      if (mounted) setState(() => _tasks = const []);
    }
  }

  Future<void> _ask([String? preset]) async {
    final t = (preset ?? _text.text).trim();
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await AgentApi.create(t);
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String id, bool approve) async {
    setState(() => _working = id);
    try {
      final r = await AgentApi.decide(id, approve: approve);
      if (!mounted) return;
      if (approve) {
        final n = ((r['result'] as Map?)?['reminders_created'] as num?)?.toInt() ?? 0;
        showSuccess(context, n > 0 ? 'Listo: $n recordatorios programados' : 'Aprobada');
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tareas del Copiloto')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
          Text('Encárgale algo. Lo prepara con tus datos reales y tú decides si se hace.', style: t.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              hintText: 'Ej.: cobra a los que más me deben',
              prefixIcon: const Icon(Icons.auto_awesome_rounded),
              suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) : IconButton(icon: const Icon(Icons.send_rounded), onPressed: _ask),
            ),
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error, style: t.textTheme.bodySmall?.copyWith(color: Brand.bad))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final i in _ideas) ActionChip(label: Text(i, style: const TextStyle(fontSize: 12.5)), onPressed: _busy ? null : () => _ask(i)),
          ]),
          const SizedBox(height: 18),
          if (_tasks == null)
            const SkeletonCard()
          else if (_tasks!.isEmpty)
            const EmptyState(title: 'Aún no hay tareas', body: 'Prueba con una de las ideas de arriba.')
          else
            for (final task in _tasks!) Padding(padding: const EdgeInsets.only(bottom: 12), child: _TaskCard(task: task, working: _working == task['id'], onDecide: (a) => _decide(task['id'] as String, a))),
        ]),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.working, required this.onDecide});
  final Map<String, dynamic> task;
  final bool working;
  final ValueChanged<bool> onDecide;

  static String _label(String s) => switch (s) {
        'proposed' => 'Por aprobar',
        'approved' => 'Aprobada',
        'done' => 'Hecha',
        'rejected' => 'Rechazada',
        _ => 'Falló',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = (task['status'] ?? '') as String;
    final plan = task['plan'] is Map ? Map<String, dynamic>.from(task['plan'] as Map) : <String, dynamic>{};
    final results = (plan['results'] is List) ? [for (final r in plan['results'] as List) if (r is Map) Map<String, dynamic>.from(r)] : <Map<String, dynamic>>[];
    final tone = switch (status) { 'proposed' => PillTone.warn, 'done' || 'approved' => PillTone.ok, 'rejected' => PillTone.neutral, _ => PillTone.bad };
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text((task['title'] ?? 'Tarea') as String, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          StatusPill(_label(status), tone: tone),
        ]),
        const SizedBox(height: 4),
        Text('"${task['prompt'] ?? ''}"', style: t.textTheme.bodySmall),
        for (final r in results) ...[const Divider(height: 22), _Step(result: r)],
        if (status == 'proposed') ...[
          const SizedBox(height: 14),
          Text('Al aprobar, solo se programan los recordatorios (si los hay). No se envía nada a tus clientes.', style: t.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: working ? null : () => onDecide(false), child: const Text('Rechazar')),
            const Spacer(),
            FilledButton.icon(onPressed: working ? null : () => onDecide(true), icon: working ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded), label: const Text('Aprobar')),
          ]),
        ],
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = result['items'] is List ? [for (final i in result['items'] as List) if (i is Map) Map<String, dynamic>.from(i)] : <Map<String, dynamic>>[];
    String m(Object? v) => money((v as num?)?.toDouble() ?? 0, 'PEN');
    switch (result['action']) {
      case 'cobranza':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mensajes de cobro (${items.length})', style: t.textTheme.labelLarge),
          if (items.isEmpty) Text('Nadie tiene deuda pendiente. 🎉', style: t.textTheme.bodySmall),
          for (final i in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${i['client']} · ${m(i['balance'])}'),
              subtitle: Text('${i['message']}', maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: 'Copiar mensaje',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${i['message']}'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensaje copiado. Pégalo en WhatsApp.')));
                },
              ),
            ),
        ]);
      case 'reposicion':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Lista de compras (${items.length})', style: t.textTheme.labelLarge),
          if (items.isEmpty) Text('Nada está por acabarse.', style: t.textTheme.bodySmall),
          for (final i in items) Text('• ${i['product']}: quedan ${i['stock']}, sugiero pedir ${i['suggested']}'),
        ]);
      case 'recordatorios':
        final ok = items.where((i) => i['client_id'] != null).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Recordatorios de cobro ($ok)', style: t.textTheme.labelLarge),
          for (final i in items) Text('${i['client_id'] == null ? '⚠️ ' : '• '}${i['client']} · ${m(i['balance'])} · ${displayDate('${i['due_on']}')}${i['client_id'] == null ? ' (no lo programo: nombre repetido o sin ficha)' : ''}'),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Resumen de la semana', style: t.textTheme.labelLarge),
          for (final l in (result['lines'] is List ? result['lines'] as List : const [])) Text('• $l'),
        ]);
    }
  }
}
