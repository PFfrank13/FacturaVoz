// Dueño a distancia y antifraude (Fase 8 · módulo 5): alertas en tiempo real (anulaciones, descuentos grandes,
// caja que no cuadra, cobros borrados, nuevos integrantes), bitácora encadenada que no se puede alterar sin que se note,
// y PIN del dueño para autorizar operaciones sensibles en el local.
import 'package:flutter/material.dart';

import '../errors.dart';
import '../models_v2.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show shortDateTime;

/// Antes de una operación sensible (anular, borrar un cobro): si la empresa tiene PIN y este usuario no lo validó
/// en los últimos minutos, se lo pide. Devuelve true si puede continuar. La base de datos lo vuelve a comprobar.
Future<bool> ensureOwnerPin(BuildContext context, {String reason = 'Esta operación necesita el PIN del dueño.'}) async {
  final st = await V2Repo.pinStatus();
  if (st['enabled'] != true || st['ok'] == true) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(context: context, builder: (_) => _PinDialog(reason: reason));
  return ok == true;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.reason});
  final String reason;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _c = TextEditingController();
  bool _busy = false;
  String _msg = '';
  int _shake = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final ok = await V2Repo.verifyPin(_c.text.trim());
      if (!mounted) return;
      if (ok) {
        Haptics.success();
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _msg = 'PIN incorrecto. Tras 5 intentos se bloquea 15 minutos.';
        _shake++;
      });
    } catch (e) {
      if (mounted) setState(() => _msg = friendly(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.pin_rounded, size: 36),
        title: const Text('PIN del dueño'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.reason, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Shake(
            trigger: _shake,
            child: TextField(
              controller: _c,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              onSubmitted: (_) => _check(),
            ),
          ),
          if (_msg.isNotEmpty) Text(_msg, style: const TextStyle(color: Brand.bad), textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: _busy ? null : _check, child: const Text('Autorizar')),
        ],
      );
}

// ═════════════════════════ Alertas ═════════════════════════
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final Stream<List<OwnerAlert>> _stream = V2Repo.watchAlerts();

  @override
  void initState() {
    super.initState();
    V2Repo.markAlertsRead().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas del dueño'), actions: [
        IconButton(tooltip: 'Bitácora', onPressed: () => pushPremium(context, const AuditScreen()), icon: const Icon(Icons.history_rounded)),
        IconButton(tooltip: 'PIN del dueño', onPressed: () => pushPremium(context, const OwnerPinScreen()), icon: const Icon(Icons.pin_rounded)),
      ]),
      body: StreamBuilder<List<OwnerAlert>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(V2Repo.missingHint(snap.error!), textAlign: TextAlign.center)));
          final list = snap.data;
          if (list == null) return const SkeletonList();
          if (list.isEmpty) {
            return const EmptyState(title: 'Todo tranquilo', body: 'Aquí verás al instante anulaciones, descuentos grandes, cobros borrados y cajas que no cuadran.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = list[i];
              final c = switch (a.severity) { 'bad' => Brand.bad, 'warn' => Brand.warn, _ => Brand.indigo };
              return Reveal(
                key: ValueKey(a.id),
                index: i < 8 ? i : 8,
                child: SoftCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.title, style: t.textTheme.titleSmall),
                        if (a.body.isNotEmpty) Text(a.body, style: t.textTheme.bodySmall),
                        if (a.createdAt != null) Text(shortDateTime(a.createdAt!), style: t.textTheme.labelSmall),
                      ]),
                    ),
                    if (a.readAt == null) const PulseDot(color: Brand.bad),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ═════════════════════════ Bitácora ═════════════════════════
const _actionNames = <String, String>{
  'factura.estado': 'Cambió el estado de un comprobante',
  'cobro.registrado': 'Registró un cobro',
  'comprobante.anulado': 'Anuló un comprobante',
  'venta.descuento_alto': 'Dio un descuento grande',
  'caja.cierre': 'Cerró la caja',
  'equipo.insert': 'Entró un integrante nuevo',
  'equipo.update': 'Cambió permisos de un integrante',
  'equipo.delete': 'Quitó a un integrante',
  'pin.cambiado': 'Cambió el PIN del dueño',
  'pin.desactivado': 'Quitó el PIN del dueño',
  'pin.fallido': 'PIN incorrecto',
};

/// "payments.eliminado" → "Borró: Cobro"; "jobs.recuperado" → "Recuperó: Trabajo".
String auditLabel(String action) {
  final known = _actionNames[action];
  if (known != null) return known;
  final p = action.split('.');
  if (p.length == 2 && (p[1] == 'eliminado' || p[1] == 'recuperado')) {
    return '${p[1] == 'eliminado' ? 'Borró' : 'Recuperó'}: ${trashTables[p[0]] ?? p[0]}';
  }
  return action;
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<AuditEntry>? _items;
  String? _error;
  String _verify = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await V2Repo.audit();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _check() async {
    setState(() => _verify = 'Verificando…');
    try {
      final bad = await V2Repo.auditVerify();
      if (!mounted) return;
      setState(() => _verify = bad == null ? 'Bitácora íntegra ✓ (nadie la alteró)' : '¡Atención! La fila $bad fue alterada.');
      if (bad == null) Haptics.success();
    } catch (e) {
      if (mounted) setState(() => _verify = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bitácora')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _items == null
              ? const SkeletonList()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        const Icon(Icons.link_rounded, color: Brand.indigo),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_verify.isEmpty ? 'Cada registro está encadenado al anterior: si alguien lo cambia, se detecta.' : _verify, style: t.textTheme.bodySmall)),
                        TextButton(onPressed: _check, child: const Text('Verificar')),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (_items!.isEmpty) const EmptyState(title: 'Sin movimientos aún', body: 'Aquí quedará quién hizo qué y cuándo.'),
                    for (final e in _items!)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.circle, size: 10),
                        title: Text(auditLabel(e.action)),
                        subtitle: Text([
                          if (e.createdAt != null) shortDateTime(e.createdAt!),
                          if (e.data['label'] != null) '${e.data['label']}',
                          if (e.data['numero'] != null) '${e.data['numero']}',
                          if (e.data['monto'] != null) 'S/ ${e.data['monto']}',
                        ].join(' · ')),
                      ),
                  ]),
                ),
    );
  }
}

// ═════════════════════════ PIN del dueño ═════════════════════════
class OwnerPinScreen extends StatefulWidget {
  const OwnerPinScreen({super.key});

  @override
  State<OwnerPinScreen> createState() => _OwnerPinScreenState();
}

class _OwnerPinScreenState extends State<OwnerPinScreen> {
  bool? _enabled;
  final _a = TextEditingController();
  final _b = TextEditingController();
  String _msg = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    V2Repo.pinStatus().then((s) {
      if (mounted) setState(() => _enabled = s['enabled'] == true);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final pin = _a.text.trim();
    if (!remove) {
      if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
        setState(() => _msg = 'El PIN debe tener de 4 a 8 números.');
        return;
      }
      if (pin != _b.text.trim()) {
        setState(() => _msg = 'Los PIN no coinciden.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await V2Repo.setPin(remove ? null : pin);
      if (!mounted) return;
      showSuccess(context, remove ? 'PIN quitado' : 'PIN guardado', icon: Icons.pin_rounded);
      _a.clear();
      _b.clear();
      setState(() {
        _enabled = !remove;
        _msg = '';
      });
    } catch (e) {
      if (mounted) setState(() => _msg = V2Repo.missingHint(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PIN del dueño')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Con el PIN activo, tu equipo necesita que lo escribas (en el local) para anular comprobantes o borrar cobros. Tú, como dueño, no lo necesitas.',
            style: t.textTheme.bodyMedium),
        const SizedBox(height: 16),
        if (_enabled == null)
          const LinearProgressIndicator()
        else ...[
          TagChip(_enabled! ? 'PIN activo' : 'Sin PIN', color: _enabled! ? Brand.ok : Brand.warn, icon: _enabled! ? Icons.lock_rounded : Icons.lock_open_rounded),
          const SizedBox(height: 16),
          TextField(controller: _a, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: InputDecoration(labelText: _enabled! ? 'Nuevo PIN' : 'PIN (4 a 8 números)')),
          TextField(controller: _b, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'Repite el PIN')),
          if (_msg.isNotEmpty) Text(_msg, style: const TextStyle(color: Brand.bad)),
          const SizedBox(height: 12),
          GradientButton(label: _enabled! ? 'Cambiar PIN' : 'Activar PIN', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
          if (_enabled!) TextButton(onPressed: _busy ? null : () => _save(remove: true), child: const Text('Quitar el PIN')),
        ],
      ]),
    );
  }
}
