// Papelera de 30 días + "Deshacer" (Fase 8 · módulo 6). Lo borrado se guarda en la base de datos (disparadores)
// y se puede recuperar. Después de 30 días se limpia solo.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models_v2.dart';
import '../services/live.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Muestra "Deshacer" unos segundos después de borrar algo. [rowId] es el id de la fila borrada.
void showUndo(BuildContext context, {required String rowId, required String label, VoidCallback? onRestored}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(label),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () async {
          try {
            final id = await V2Repo.lastTrashFor(rowId);
            if (id == null) throw AppException('Ya no está en la papelera.');
            await V2Repo.restore(id);
            AppState.instance.bump();
            onRestored?.call();
            messenger.showSnackBar(const SnackBar(content: Text('Recuperado ✓')));
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('No se pudo recuperar. ${friendly(e)}')));
          }
        },
      ),
    ));
}

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> with LiveReload<TrashScreen> {
  List<TrashItem>? _items;
  String? _error;
  final Set<String> _busy = {};

  @override
  List<String> get liveTables => const ['trash'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _items = LiveCache.get<List<TrashItem>>('trash.all');
    startLive();
    _load();
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await V2Repo.trash();
      LiveCache.put('trash.all', r);
      if (mounted) {
        setState(() {
          _items = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _restore(TrashItem i) async {
    setState(() => _busy.add(i.id));
    try {
      await V2Repo.restore(i.id);
      AppState.instance.bump();
      if (!mounted) return;
      Haptics.success();
      showSuccess(context, 'Recuperado: ${i.label}', icon: Icons.restore_rounded);
      setState(() => _items?.remove(i));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo recuperar. ${friendly(e)}')));
    }
    if (mounted) setState(() => _busy.remove(i.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Papelera')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _items == null
              ? const SkeletonList()
              : _items!.isEmpty
                  ? const EmptyState(title: 'La papelera está vacía', body: 'Lo que borres se guarda aquí 30 días por si te arrepientes.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: _items!.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == 0) return Text('Se borra para siempre a los 30 días.', style: t.textTheme.bodySmall);
                          final it = _items![i - 1];
                          final days = it.deletedAt == null ? null : 30 - DateTime.now().difference(it.deletedAt!).inDays;
                          return Reveal(
                            key: ValueKey(it.id),
                            index: i < 10 ? i : 10,
                            child: SoftCard(
                              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                              child: Row(children: [
                                Icon(Icons.delete_outline_rounded, color: t.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(it.label.isEmpty ? (trashTables[it.table] ?? it.table) : it.label, style: t.textTheme.titleSmall),
                                    Text('${trashTables[it.table] ?? it.table}${days != null ? ' · quedan ${days < 0 ? 0 : days} días' : ''}', style: t.textTheme.bodySmall),
                                  ]),
                                ),
                                _busy.contains(it.id)
                                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                    : TextButton.icon(onPressed: () => _restore(it), icon: const Icon(Icons.restore_rounded), label: const Text('Recuperar')),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Color neutro reutilizado por otras pantallas de control.
const trashColor = Brand.warn;
