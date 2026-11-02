// Caja y cierre del día (Fase 8 · módulo 3): apertura, ingresos y salidas de efectivo, lo vendido por medio de pago,
// cuánto efectivo DEBERÍA haber y el arqueo. Al cerrar se guarda y se envía el reporte al dueño por correo.
import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/v2_api.dart';
import '../services/v2_repo.dart';
import '../services/live.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show shortDateTime;

class CashDayScreen extends StatefulWidget {
  const CashDayScreen({super.key});

  @override
  State<CashDayScreen> createState() => _CashDayScreenState();
}

class _CashDayScreenState extends State<CashDayScreen> with LiveReload<CashDayScreen> {
  String _day = todayIso();
  DaySummary? _sum;
  List<CashMove> _moves = const [];
  Map<String, dynamic>? _closing;
  String? _error;
  bool _busy = false;

  String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';

  @override
  List<String> get liveTables => const ['cash_movements', 'payments', 'invoices'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _sum = LiveCache.get<DaySummary>('cash.$_day.sum');
    _moves = LiveCache.get<List<CashMove>>('cash.$_day.moves') ?? const [];
    _closing = LiveCache.get<Map<String, dynamic>>('cash.$_day.closing');
    _load();
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await V2Repo.daySummary(_day);
      final m = await V2Repo.cashMoves(_day);
      final c = await V2Repo.dayClosing(_day);
      LiveCache.put('cash.$_day.sum', s);
      LiveCache.put('cash.$_day.moves', m);
      LiveCache.put('cash.$_day.closing', c);
      if (mounted) {
        setState(() {
          _sum = s;
          _moves = m;
          _closing = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.parse(_day), firstDate: DateTime.now().subtract(const Duration(days: 366)), lastDate: DateTime.now());
    if (d == null) return;
    setState(() {
      _day = todayIso(d);
      _sum = null;
    });
    _load();
  }

  Future<void> _move(String kind) async {
    final amount = TextEditingController(), note = TextEditingController();
    final title = switch (kind) { 'apertura' => 'Apertura de caja', 'ingreso' => 'Entra efectivo', _ => 'Sale efectivo' };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Monto', prefixText: '${currencySymbols[_cur] ?? _cur} '),
          ),
          TextField(controller: note, decoration: InputDecoration(labelText: kind == 'apertura' ? 'Nota (opcional)' : 'Motivo (ej.: pago a proveedor, sencillo)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final a = parseDecimal(amount.text) ?? 0;
    final n = note.text;
    disposeAfterClose([amount, note]);
    if (ok != true || a <= 0) return;
    setState(() => _busy = true);
    try {
      await V2Repo.addCashMove(kind: kind, amount: a, note: n);
      if (mounted) showSuccess(context, 'Movimiento guardado');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _close() async {
    final s = _sum;
    if (s == null) return;
    final counted = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar la caja'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Debería haber ${money(s.expectedCash, _cur)} en efectivo. Cuenta los billetes y monedas:'),
          const SizedBox(height: 10),
          TextField(
            controller: counted,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Efectivo contado', prefixText: '${currencySymbols[_cur] ?? _cur} '),
          ),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar y enviar reporte')),
        ],
      ),
    );
    final c = parseDecimal(counted.text);
    final n = note.text;
    disposeAfterClose([counted, note]);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await V2Api.closeDay(day: _day, counted: c, note: n);
      if (!mounted) return;
      final diff = c == null ? 0.0 : c - r.summary.expectedCash;
      Haptics.success();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(diff.abs() < 0.5 ? Icons.verified_rounded : Icons.error_outline_rounded, color: diff.abs() < 0.5 ? Brand.ok : Brand.warn, size: 40),
          title: Text(diff.abs() < 0.5 ? '¡Caja cuadrada!' : (diff > 0 ? 'Sobra ${money(diff, _cur)}' : 'Falta ${money(-diff, _cur)}')),
          content: Text(r.emailed ? 'El reporte del día se envió por correo al dueño.' : 'Cierre guardado. (El correo no se envió: revisa la configuración de Resend en el servidor.)'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _sum;
    final isToday = _day == todayIso();
    return Scaffold(
      appBar: AppBar(title: const Text('Caja del día'), actions: [
        TextButton.icon(onPressed: _pickDay, icon: const Icon(Icons.calendar_today_rounded, size: 18), label: Text(isToday ? 'Hoy' : displayDate(_day))),
      ]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : s == null
              ? const SkeletonList(count: 4)
              : AbsorbPointer(
                  absorbing: _busy,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                      Reveal(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(26)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Vendido ${isToday ? 'hoy' : 'ese día'}', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85))),
                            CountUp(value: s.salesTotal, builder: (_, v) => Text(money(v, _cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800))),
                            Text(
                              '${s.salesCount} ${s.salesCount == 1 ? 'venta' : 'ventas'}${s.draftsCount > 0 ? ' · ${s.draftsCount} sin emitir' : ''}',
                              style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Reveal(
                        index: 1,
                        child: SoftCard(
                          child: Column(children: [
                            _line(context, 'Apertura', s.opening),
                            _line(context, 'Ventas en efectivo', s.cashSales),
                            _line(context, 'Otros ingresos de efectivo', s.cashIn),
                            _line(context, 'Salidas de efectivo', -s.cashOut),
                            const Divider(),
                            _line(context, 'Debería haber en caja', s.expectedCash, bold: true),
                            if (_closing != null) ...[
                              _line(context, 'Contado al cerrar', ((_closing!['counted_cash'] as num?) ?? 0).toDouble()),
                              _line(context, 'Diferencia', ((_closing!['difference'] as num?) ?? 0).toDouble(), bold: true, signed: true),
                            ],
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (s.byMethod.isNotEmpty)
                        Reveal(
                          index: 2,
                          child: SoftCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Cobrado por medio de pago', style: t.textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final e in s.byMethod.entries) _line(context, paymentMethods[e.key] ?? e.key, e.value),
                              if (s.fiadoCharged > 0 || s.fiadoPaid > 0) ...[
                                const Divider(),
                                _line(context, 'Fiado entregado', s.fiadoCharged),
                                _line(context, 'Abonos de fiado', s.fiadoPaid),
                              ],
                              if (s.expenses != null && Access.instance.can('finance')) _line(context, 'Gastos registrados', s.expenses!),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (isToday && _closing == null)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(onPressed: () => _move('apertura'), icon: const Icon(Icons.lock_open_rounded), label: const Text('Apertura')),
                          OutlinedButton.icon(onPressed: () => _move('ingreso'), icon: const Icon(Icons.south_west_rounded), label: const Text('Entra efectivo')),
                          OutlinedButton.icon(onPressed: () => _move('egreso'), icon: const Icon(Icons.north_east_rounded), label: const Text('Sale efectivo')),
                        ]),
                      if (_moves.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const SectionTitle('Movimientos de caja'),
                        for (final m in _moves)
                          ListTile(
                            dense: true,
                            leading: Icon(m.kind == 'egreso' ? Icons.north_east_rounded : Icons.south_west_rounded, color: m.kind == 'egreso' ? Brand.bad : Brand.ok),
                            title: Text(m.note.isEmpty ? (m.kind == 'apertura' ? 'Apertura' : (m.kind == 'egreso' ? 'Salida' : 'Ingreso')) : m.note),
                            subtitle: m.createdAt == null ? null : Text(shortDateTime(m.createdAt!)),
                            trailing: Money(money(m.amount, _cur)),
                          ),
                      ],
                      const SizedBox(height: 18),
                      if (_closing == null)
                        GradientButton(label: 'Cerrar la caja y enviar reporte', icon: Icons.lock_clock_rounded, busy: _busy, onPressed: _busy ? null : _close)
                      else
                        SoftCard(
                          color: Brand.ok.withValues(alpha: 0.10),
                          child: Row(children: [
                            const Icon(Icons.verified_rounded, color: Brand.ok),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Caja cerrada${_closing!['note'] != null && '${_closing!['note']}'.isNotEmpty ? ' · ${_closing!['note']}' : ''}.')),
                            TextButton(onPressed: _close, child: const Text('Volver a cerrar')),
                          ]),
                        ),
                    ]),
                  ),
                ),
    );
  }

  Widget _line(BuildContext context, String label, double v, {bool bold = false, bool signed = false}) {
    final t = Theme.of(context);
    final color = signed ? (v.abs() < 0.5 ? Brand.ok : (v > 0 ? Brand.warn : Brand.bad)) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: bold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)),
        Money('${signed && v > 0 ? '+' : ''}${money(v, _cur)}', weight: bold ? FontWeight.w800 : FontWeight.w600, color: color),
      ]),
    );
  }
}
