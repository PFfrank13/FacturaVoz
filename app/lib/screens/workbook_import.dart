// Importar un libro Excel completo (clientes + comprobantes + detalle + catálogo):
// leer → confirmar con conteos y totales → guardar por bloques → comparar esperado vs. guardado → (deshacer).
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../errors.dart';
import '../models.dart' show money;
import '../services/repo.dart';
import '../services/workbook_import.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

enum _Step { reading, confirm, saving, done, failed }

class WorkbookImportScreen extends StatefulWidget {
  const WorkbookImportScreen({super.key, required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;

  @override
  State<WorkbookImportScreen> createState() => _WorkbookImportScreenState();
}

const _roleLabel = {
  'clientes': 'Clientes',
  'comprobantes': 'Facturas, boletas y notas',
  'detalle': 'Detalle (productos de cada comprobante)',
  'catalogo': 'Catálogo de productos',
  'ignorada': 'No se usa (instrucciones o leyenda)',
};

class _WorkbookImportScreenState extends State<WorkbookImportScreen> {
  _Step _step = _Step.reading;
  WbAnalysis? _a;
  String _error = '';
  WbProgress _p = const WbProgress('', 0, 1);
  String? _job;
  Map<String, dynamic>? _result;
  bool _undoing = false;
  bool _undone = false;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _step = _Step.reading;
      _error = '';
    });
    try {
      final a = await WorkbookImporter.analyze(widget.bytes);
      if (!mounted) return;
      setState(() {
        _a = a;
        _step = _Step.confirm;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendly(e);
          _step = _Step.failed;
        });
      }
    }
  }

  Future<void> _save() async {
    final org = Repo.activeOrgId;
    final a = _a;
    if (org == null || a == null) return;
    setState(() => _step = _Step.saving);
    try {
      final (job, result) = await WorkbookImporter.run(org, widget.fileName, a, (p) {
        if (mounted) setState(() => _p = p);
      });
      if (!mounted) return;
      setState(() {
        _job = job;
        _result = result;
        _step = _Step.done;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '${friendly(e)}\nLo que alcanzó a guardarse se puede deshacer desde "Importaciones anteriores".';
          _step = _Step.failed;
        });
      }
    }
  }

  Future<void> _undo() async {
    final job = _job;
    if (job == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Deshacer toda la importación?'),
        content: const Text('Se borran los comprobantes, cobros, clientes y productos que trajo este archivo. '
            'Lo que ya tenías antes no se toca.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, deshacer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _undoing = true);
    try {
      await WorkbookImporter.undo(job);
      if (mounted) setState(() => _undone = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar libro de Excel')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text(widget.fileName, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          ...switch (_step) {
            _Step.reading => [const SkeletonCard(), const SizedBox(height: 12), const Center(child: Text('Leyendo las hojas del archivo…'))],
            _Step.confirm => _confirm(context, _a!),
            _Step.saving => _saving(context),
            _Step.done => _done(context, _a!, _result!),
            _Step.failed => [
                SoftCard(child: Text(_error, style: const TextStyle(color: Brand.bad))),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _analyze, icon: const Icon(Icons.refresh_rounded), label: const Text('Intentar de nuevo')),
              ],
          },
        ]),
      ),
    );
  }

  List<Widget> _confirm(BuildContext context, WbAnalysis a) {
    final t = Theme.of(context);
    final net = a.money('net');
    return [
      SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Esto encontré en tu archivo', style: t.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final s in a.sheets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(s['role'] == 'ignorada' ? Icons.remove_circle_outline : Icons.check_circle_rounded,
                    size: 18, color: s['role'] == 'ignorada' ? t.colorScheme.outline : Brand.ok),
                const SizedBox(width: 8),
                Expanded(child: Text('${s['name']}: ${_roleLabel[s['role']] ?? s['role']}')),
                if ((s['rows'] as num? ?? 0) > 0) Text('${s['rows']} filas', style: t.textTheme.bodySmall),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se va a guardar', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          DataRow2('Clientes', '${a.count('clients')}'),
          DataRow2('Productos', '${a.count('products')}'),
          DataRow2('Facturas', '${a.count('facturas')}'),
          DataRow2('Boletas', '${a.count('boletas')}'),
          if (a.count('notas_venta') > 0) DataRow2('Notas de venta', '${a.count('notas_venta')}'),
          DataRow2('Notas de crédito (restan)', '${a.count('credit_notes')}'),
          DataRow2('Anulados (no cuentan como venta)', '${a.count('voided')}'),
          DataRow2('Líneas de detalle', '${a.count('lines')}'),
          if (a.count('skipped') > 0) DataRow2('No se pueden importar', '${a.count('skipped')}'),
          const Divider(height: 22),
          for (final e in net.entries) ...[
            DataRow2('Ventas (${e.key})', money(a.money('sales')[e.key] ?? 0, e.key)),
            DataRow2('Notas de crédito (${e.key})', '− ${money(a.money('credit_notes')[e.key] ?? 0, e.key)}'),
            DataRow2('Total neto (${e.key})', money(e.value, e.key)),
            DataRow2('Te deben (${e.key})', money(a.money('receivable')[e.key] ?? 0, e.key)),
          ],
          const SizedBox(height: 6),
          Text('Montos con IGV, tal como vienen en tu archivo.', style: t.textTheme.bodySmall),
        ]),
      ),
      if (a.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.info_outline_rounded, color: Brand.warn), const SizedBox(width: 8), Text('Avisos', style: t.textTheme.titleMedium)]),
            for (final w in a.warnings)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${w['message']} (${w['count']})', style: t.textTheme.bodyMedium),
                children: [for (final ex in (w['examples'] as List? ?? [])) Align(alignment: Alignment.centerLeft, child: Text('• $ex', style: t.textTheme.bodySmall))],
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      GradientButton(label: 'Importar ${a.count('documents')} comprobantes', icon: Icons.download_done_rounded, onPressed: a.count('documents') + a.count('clients') == 0 ? null : _save),
      const SizedBox(height: 8),
      Text('Si importas el mismo archivo dos veces, no se duplica nada. Puedes deshacerlo después.', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
    ];
  }

  List<Widget> _saving(BuildContext context) => [
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Guardando ${_p.step.toLowerCase()}…', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _p.fraction, minHeight: 8, borderRadius: BorderRadius.circular(Radii.sm)),
            const SizedBox(height: 8),
            Text('${_p.done} de ${_p.total}'),
            const SizedBox(height: 8),
            const Text('No cierres esta pantalla hasta que termine.'),
          ]),
        ),
      ];

  List<Widget> _done(BuildContext context, WbAnalysis a, Map<String, dynamic> r) {
    final t = Theme.of(context);
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    final rows = <(String, int, int)>[
      ('Clientes', a.count('clients'), n('clients_created') + n('clients_existing')),
      ('Productos', a.count('products'), n('products_created') + n('products_existing')),
      ('Comprobantes', a.count('documents'), n('documents')),
      ('Facturas', a.count('facturas'), n('facturas')),
      ('Boletas', a.count('boletas'), n('boletas')),
      ('Notas de crédito', a.count('credit_notes'), n('credit_notes')),
      ('Líneas', a.count('lines'), n('lines')),
    ];
    final expectedNet = a.money('net');
    final gotNet = {for (final e in Map<String, dynamic>.from(r['net'] as Map? ?? {}).entries) e.key: (e.value as num).toDouble()};
    final dup = a.count('documents') - n('documents');
    return [
      SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_undone ? 'Importación deshecha' : 'Listo: esto quedó guardado', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: const [Expanded(child: Text('')), SizedBox(width: 80, child: Text('En el archivo', textAlign: TextAlign.end)), SizedBox(width: 80, child: Text('Guardado', textAlign: TextAlign.end))]),
          for (final (label, exp, got) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(exp == got ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: exp == got ? Brand.ok : Brand.warn),
                const SizedBox(width: 6),
                Expanded(child: Text(label)),
                SizedBox(width: 80, child: Text('$exp', textAlign: TextAlign.end)),
                SizedBox(width: 80, child: Text('$got', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
          const Divider(height: 20),
          for (final e in expectedNet.entries)
            DataRow2('Total neto ${e.key}', '${money(e.value, e.key)} → ${money(gotNet[e.key] ?? 0, e.key)}'),
          if (dup > 0) ...[
            const SizedBox(height: 8),
            Text('$dup comprobantes ya estaban en FacturaVoz (mismo tipo y número): no se duplicaron.', style: t.textTheme.bodySmall),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      if (!_undone)
        OutlinedButton.icon(
          onPressed: _undoing ? null : _undo,
          icon: _undoing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.undo_rounded),
          label: const Text('Deshacer esta importación'),
        ),
      const SizedBox(height: 8),
      FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Terminar')),
    ];
  }
}

/// Importaciones anteriores (con opción de deshacer). Solo dueño, administrador o finanzas las ven.
class WorkbookHistoryScreen extends StatefulWidget {
  const WorkbookHistoryScreen({super.key});

  @override
  State<WorkbookHistoryScreen> createState() => _WorkbookHistoryScreenState();
}

class _WorkbookHistoryScreenState extends State<WorkbookHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final org = Repo.activeOrgId;
    return org == null ? Future.value(const []) : WorkbookImporter.history(org);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importaciones anteriores')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const SkeletonList();
          if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendly(s.error!))));
          final rows = s.data ?? const [];
          if (rows.isEmpty) return const Center(child: Text('Todavía no importaste libros de Excel.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rows[i];
              final res = Map<String, dynamic>.from(r['result'] as Map? ?? {});
              final undone = r['status'] == 'undone';
              return SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text((r['file_name'] as String?) ?? 'Archivo'),
                  subtitle: Text(undone ? 'Deshecha' : r['status'] == 'done' ? '${res['documents'] ?? 0} comprobantes · ${res['clients_created'] ?? 0} clientes nuevos' : 'Incompleta'),
                  trailing: undone
                      ? null
                      : TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('¿Deshacer esta importación?'),
                                content: const Text('Se borra solo lo que trajo este archivo.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Deshacer')),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            try {
                              await WorkbookImporter.undo(r['id'] as String);
                              if (mounted) setState(() => _f = _load());
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
                            }
                          },
                          child: const Text('Deshacer'),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
