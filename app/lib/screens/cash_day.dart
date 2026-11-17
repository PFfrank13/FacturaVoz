// Caja y cierre del día (Fase 8 · módulo 3): apertura, ingresos y salidas de efectivo, lo vendido por medio de pago,
// cuánto efectivo DEBERÍA haber y el arqueo. Al cerrar se guarda y se envía el reporte al dueño por correo.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/data_scope.dart';

import '../access.dart';
import '../app_state.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/v2_api.dart';
import '../services/v2_repo.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/ds.dart';
import '../ui/widgets.dart';
import '../ui/retail_visual.dart';
import 'client_profile.dart' show shortDateTime;

class CashDayScreen extends StatefulWidget {
  const CashDayScreen({super.key, this.embedded = false});

  final bool embedded;

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
  String? _activeOrg;
  int _loadGeneration = 0;

  ScopeTicket _operationTicket() => ScopeTicket(
      dataScope.value, Repo.activeOrgId,
      Supabase.instance.client.auth.currentUser?.id);

  bool _canCommit(ScopeTicket ticket, String day) => mounted &&
      day == _day && ticket.permitsMutation(dataScope.value, Repo.activeOrgId,
          Supabase.instance.client.auth.currentUser?.id);

  void _onCompanyChange() {
    final org = Repo.activeOrgId;
    if (!mounted || org == _activeOrg) return;
    _activeOrg = org;
    _loadGeneration++;
    setState(() {
      _day = todayIso();
      _sum = null;
      _moves = const [];
      _closing = null;
      _error = null;
    });
    _load();
  }

  String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';

  @override
  List<String> get liveTables => const ['cash_movements', 'payments', 'invoices'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _activeOrg = Repo.activeOrgId;
    AppState.instance.addListener(_onCompanyChange);
    _sum = LiveCache.get<DaySummary>('cash.$_day.sum');
    _moves = LiveCache.get<List<CashMove>>('cash.$_day.moves') ?? const [];
    _closing = LiveCache.get<Map<String, dynamic>>('cash.$_day.closing');
    _load();
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onCompanyChange);
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    final org = Repo.activeOrgId;
    final day = _day;
    final generation = ++_loadGeneration;
    try {
      final s = await V2Repo.daySummary(day);
      final m = await V2Repo.cashMoves(day);
      final c = await V2Repo.dayClosing(day);
      if (!mounted || Repo.activeOrgId != org || _day != day || generation != _loadGeneration) return;
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
      if (mounted && Repo.activeOrgId == org && _day == day && generation == _loadGeneration) {
        setState(() => _error = V2Repo.missingHint(e));
      }
    }
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.parse(_day), firstDate: DateTime.now().subtract(const Duration(days: 366)), lastDate: DateTime.now());
    if (d == null) return;
    setState(() {
      _day = todayIso(d);
      _sum = null;
      _moves = const [];
      _closing = null;
      _error = null;
    });
    _load();
  }

  Future<void> _move(String kind) async {
    if (_busy || _closing != null || _day != todayIso()) return;
    final ticket = _operationTicket();
    final day = _day;
    if (!_canCommit(ticket, day)) return;
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
    final a = parseDecimal(amount.text);
    final n = note.text;
    disposeAfterClose([amount, note]);
    if (ok != true || !_canCommit(ticket, day)) return;
    if (a == null || !a.isFinite || a <= 0 ||
        ((a * 100) - (a * 100).round()).abs() > 0.00001) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingresa un importe válido, mayor que cero y con máximo dos decimales.'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      if (!_canCommit(ticket, day)) return;
      await V2Repo.addCashMove(kind: kind, amount: a, note: n);
      if (!_canCommit(ticket, day)) return;
      showSuccess(context, 'Movimiento guardado');
      await _load();
    } catch (e) {
      if (_canCommit(ticket, day)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_sum == null || _closing != null || _busy || _day != todayIso()) return;
    final ticket = _operationTicket();
    final day = _day;
    if (!_canCommit(ticket, day)) return;
    // Blind cash close: do not expose the expected balance while counting.
    // Peruvian bill/coin values are in integer cents.
    const values = [20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50, 20, 10];
    final countFields = {for (final value in values) value: TextEditingController(text: '0')};
    final note = TextEditingController();
    final answer = await showDialog<({int cents, String note})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cierre ciego de caja'),
        content: SizedBox(
          width: 390,
          height: 460,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Cuenta billetes y monedas sin consultar el saldo esperado. '
                  'Anota cuántos tienes de cada denominación.'),
              const SizedBox(height: 12),
              for (final value in values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(money(value / 100, _cur))),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: countFields[value],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Cantidad', isDense: true),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Observación o motivo de diferencia',
                  helperText: 'Obligatorio si el arqueo no cuadra.',
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            var cents = 0;
            for (final denomination in values) {
              final count = int.tryParse(countFields[denomination]!.text.trim());
              if (count == null || count < 0 || count > 10000) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Cada cantidad debe ser un número entero entre 0 y 10 000')),
                );
                return;
              }
              cents += denomination * count;
            }
            Navigator.pop(ctx, (cents: cents, note: note.text.trim()));
          }, child: const Text('Confirmar conteo')),
        ],
      ),
    );
    disposeAfterClose([...countFields.values, note]);
    if (answer == null || !_canCommit(ticket, day)) return;
    setState(() => _busy = true);
    try {
      if (!_canCommit(ticket, day)) return;
      final r = await V2Api.closeDay(
        day: day, counted: answer.cents / 100, note: answer.note,
      );
      if (!_canCommit(ticket, day)) return;
      final diff = answer.cents / 100 - r.summary.expectedCash;
      Haptics.success();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(diff.abs() < 0.01 ? Icons.verified_rounded : Icons.error_outline_rounded,
              color: diff.abs() < 0.01 ? Brand.ok : Brand.warn, size: 40),
          title: Text(diff.abs() < 0.01 ? 'Caja cuadrada' :
              (diff > 0 ? 'Sobra ${money(diff, _cur)}' : 'Falta ${money(-diff, _cur)}')),
          content: Text(r.emailed
              ? 'Cierre guardado. Se envió el reporte del día al dueño.'
              : 'Cierre guardado. No se pudo enviar correo; revisa Resend.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      );
      if (_canCommit(ticket, day)) await _load();
    } catch (e) {
      if (_canCommit(ticket, day)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se cerró caja: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _sum;
    final isToday = _day == todayIso();
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Caja del día'), actions: [
        TextButton.icon(onPressed: _pickDay, icon: const Icon(Icons.calendar_today_rounded, size: 18), label: Text(isToday ? 'Hoy' : displayDate(_day))),
      ]),
      // Acción principal SIEMPRE visible (Prompt §11/§12): abrir caja si aún no hay apertura; si no, cerrar con arqueo.
      bottomNavigationBar: _error == null && s != null && isToday && _closing == null
          ? (_opened
              ? DsActionBar(label: 'Cerrar caja (arqueo)', icon: Icons.lock_clock_rounded, busy: _busy, onPressed: _busy ? null : _close)
              : DsActionBar(label: 'Abrir caja', icon: Icons.lock_open_rounded, busy: _busy, onPressed: _busy ? null : () => _move('apertura')))
          : null,
      body: _error != null
          ? Center(child: DsStateView.error(message: _error!, onRetry: _load))
          : s == null
              ? const SkeletonList(count: 4)
              : AbsorbPointer(
                  absorbing: _busy,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                      Reveal(
                        child: RetailVisual.hero(
                          context: context,
                          eyebrow: isToday ? 'Caja · Hoy' : 'Caja · Histórico',
                          title: 'Control de caja',
                          subtitle: 'Registra movimientos y cierra con un arqueo ciego. El saldo esperado solo se muestra después del cierre.',
                          icon: Icons.account_balance_wallet_rounded,
                          footer: Row(children: [
                            Expanded(child: RetailVisual.microStat('Ventas del día', money(s.salesTotal, _cur))),
                            const SizedBox(width: 10),
                            Expanded(child: RetailVisual.microStat('Operaciones', '${s.salesCount} ventas')),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isToday) _steps(context),
                      const SizedBox(height: 12),
                      Reveal(
                        index: 1,
                        child: SoftCard(
                          child: Column(children: [
                            if (_closing == null)
                              const ListTile(
                                leading: Icon(Icons.visibility_off_outlined),
                                title: Text('Arqueo ciego'),
                                subtitle: Text('El saldo teórico y sus movimientos se muestran después de cerrar caja.'),
                              )
                            else ...[
                              _line(context, 'Apertura', s.opening),
                              _line(context, 'Ventas en efectivo', s.cashSales),
                              _line(context, 'Otros ingresos de efectivo', s.cashIn),
                              _line(context, 'Salidas de efectivo', -s.cashOut),
                              const Divider(),
                              _line(context, 'Debería haber en caja', s.expectedCash, bold: true),
                              _line(context, 'Contado al cerrar', ((_closing!['counted_cash'] as num?) ?? 0).toDouble()),
                              _line(context, 'Diferencia', ((_closing!['difference'] as num?) ?? 0).toDouble(), bold: true, signed: true),
                            ],
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_closing != null && s.byMethod.isNotEmpty)
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
                          OutlinedButton.icon(onPressed: () => _move('ingreso'), icon: const Icon(Icons.south_west_rounded), label: const Text('Entra efectivo')),
                          OutlinedButton.icon(onPressed: () => _move('egreso'), icon: const Icon(Icons.north_east_rounded), label: const Text('Sale efectivo')),
                        ]),
                      if (_closing != null && _moves.isNotEmpty) ...[
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
                      if (_closing != null)
                        SoftCard(
                          color: Brand.ok.withValues(alpha: 0.10),
                          child: Row(children: [
                            const Icon(Icons.verified_rounded, color: Brand.ok),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Caja cerrada${_closing!['note'] != null && '${_closing!['note']}'.isNotEmpty ? ' · ${_closing!['note']}' : ''}.')),
                            const Icon(Icons.lock_rounded),
                          ]),
                        ),
                    ]),
                  ),
                ),
    );
  }

  /// ¿Hay apertura registrada hoy? (monto de apertura o movimiento de apertura)
  bool get _opened => (_sum?.opening ?? 0) > 0 || _moves.any((m) => m.kind == 'apertura');

  /// Apertura → Movimientos → Arqueo → Cierre. Antes del cierre no se muestran montos (arqueo ciego).
  Widget _steps(BuildContext context) {
    final closed = _closing != null;
    final moves = _moves.where((m) => m.kind != 'apertura').length;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      DsStatus(_opened ? 'Apertura hecha' : '1 · Apertura pendiente', tone: _opened ? DsTone.ok : DsTone.pending),
      DsStatus(moves == 0 ? '2 · Sin movimientos' : '2 · $moves movimiento${moves == 1 ? '' : 's'}', tone: DsTone.info),
      DsStatus(closed ? 'Arqueo hecho' : '3 · Arqueo al cerrar', tone: closed ? DsTone.ok : DsTone.info),
      DsStatus(closed ? 'Caja cerrada' : '4 · Cierre', tone: closed ? DsTone.ok : DsTone.info),
    ]);
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
