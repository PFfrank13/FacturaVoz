// Mi turno de caja (v3.8c): cada cajero abre su turno con su fondo y lo cierra contando su cajón a ciegas.
// Lo esperado lo calcula la base (shift_close) y solo lo ve el dueño o finanzas.
// Investigación: docs/INVESTIGACION_RETAIL.md, filas 5 y 7 (robo interno y colusión).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/widgets.dart';

class MyShiftCard extends StatefulWidget {
  const MyShiftCard({super.key, required this.currency});
  final String currency;

  @override
  State<MyShiftCard> createState() => _MyShiftCardState();
}

class _MyShiftCardState extends State<MyShiftCard> {
  final _amount = TextEditingController();
  Map<String, dynamic>? _open;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final org = Repo.activeOrgId;
    final user = _db.auth.currentUser?.id;
    if (org == null || user == null) return;
    try {
      final row = await _db.from('cash_shifts').select('opened_at, opening_float').eq('org_id', org).eq('user_id', user).isFilter('closed_at', null).maybeSingle();
      if (mounted) setState(() { _open = row; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false); // migración v3.8c pendiente: la tarjeta no se muestra
    }
  }

  Future<void> _submit() async {
    final org = Repo.activeOrgId;
    final v = parseDecimal(_amount.text);
    if (org == null || v == null || v < 0) return setState(() => _message = _open == null ? 'Escribe el fondo inicial.' : 'Escribe el efectivo que contaste.');
    setState(() { _busy = true; _message = null; });
    try {
      if (_open == null) {
        await _db.rpc('shift_open', params: {'p_org': org, 'p_float': double.parse(v.toStringAsFixed(2))});
        _message = 'Turno abierto. Ciérralo al terminar contando tu cajón.';
      } else {
        final r = await _db.rpc('shift_close', params: {'p_org': org, 'p_counted': double.parse(v.toStringAsFixed(2))});
        final diff = (r is Map && r['difference'] != null) ? (r['difference'] as num).toDouble() : null;
        _message = diff == null
            ? 'Turno cerrado. El dueño revisará el cuadre.'
            : diff.abs() <= 0.01 ? 'Turno cerrado: cuadró exacto.' : 'Turno cerrado: ${diff > 0 ? 'sobraron' : 'faltaron'} ${money(diff.abs(), widget.currency)}.';
      }
      _amount.clear();
      await _load();
    } catch (e) {
      _message = friendly(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final t = Theme.of(context);
    final open = _open;
    final since = open == null ? null : DateTime.tryParse(open['opened_at'] as String)?.toLocal();
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(open == null ? Icons.point_of_sale_rounded : Icons.timer_rounded, color: t.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(open == null ? 'Mi turno' : 'Mi turno está abierto', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(open == null
            ? 'Si trabajan varios cajeros, cada uno abre su turno con su fondo y lo cierra contando su cajón.'
            : 'Desde las ${since == null ? '—' : '${since.hour.toString().padLeft(2, '0')}:${since.minute.toString().padLeft(2, '0')}'} con ${money((open['opening_float'] as num).toDouble(), widget.currency)} de fondo. Al terminar, cuenta tu cajón: es un cierre ciego.',
          style: t.textTheme.bodySmall),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: open == null ? 'Fondo inicial' : 'Efectivo contado', isDense: true),
          )),
          const SizedBox(width: 10),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(open == null ? 'Abrir turno' : 'Cerrar turno')),
        ]),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, style: t.textTheme.bodySmall)),
      ]),
    );
  }
}
