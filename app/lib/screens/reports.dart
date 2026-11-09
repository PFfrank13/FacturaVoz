import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../access.dart';
import '../errors.dart';
import '../models.dart';
import '../reports.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Reportes de ventas por mes + exportación CSV para el contador.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with LiveReload<ReportsScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  List<InvoiceRecord>? _rows;
  String? _error;
  String? _currency;
  bool _exporting = false;
  int _token = 0; // descarta respuestas de meses ya abandonados
  String? _activeOrg;

  void _onCompanyChange() {
    final org = Repo.activeOrgId;
    if (!mounted || org == _activeOrg) return;
    _activeOrg = org;
    _token++;
    setState(() {
      _rows = null;
      _error = null;
      _currency = null;
    });
    _load();
  }

  @override
  List<String> get liveTables => const ['invoices'];

  @override
  Future<void> reloadLive() => _load(quiet: true);

  @override
  void initState() {
    super.initState();
    _activeOrg = Repo.activeOrgId;
    AppState.instance.addListener(_onCompanyChange);
    startLive();
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onCompanyChange);
    stopLive();
    super.dispose();
  }

  bool get _isCurrentMonth => _year == DateTime.now().year && _month == DateTime.now().month;

  Future<void> _load({bool quiet = false}) async {
    final token = ++_token;
    final org = Repo.activeOrgId;
    final key = 'reports.$_year-$_month';
    if (!quiet) {
      setState(() {
        _rows = LiveCache.get<List<InvoiceRecord>>(key); // lo último de ese mes, al instante
        _error = null;
      });
    }
    try {
      final r = monthRange(_year, _month);
      final rows = await Repo.listInvoicesBetween(r.from, r.toExclusive);
      if (!mounted || token != _token || Repo.activeOrgId != org) return;
      LiveCache.put(key, rows);
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _token || Repo.activeOrgId != org) return;
      if (quiet && _rows != null) return; // refresco en segundo plano: se conserva lo que ya se ve
      setState(() => _error = friendly(e));
    }
  }

  void _shift(int delta) {
    HapticFeedback.selectionClick();
    final d = DateTime(_year, _month + delta, 1);
    _year = d.year;
    _month = d.month;
    _currency = null;
    _load();
  }

  Future<void> _export() async {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final name = 'ventas-$_year-${_month.toString().padLeft(2, '0')}.csv';
      final bytes = Uint8List.fromList(utf8.encode(invoicesToCsv(rows)));
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar reporte',
        fileName: name,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (!mounted) return;
      if (saved != null || kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte guardado')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = _rows;
    final report = rows == null ? const <String, CurrencyReport>{} : buildReport(rows);
    final currencies = report.keys.toList()..sort((a, b) => report[b]!.total.compareTo(report[a]!.total));
    final cur = currencies.contains(_currency) ? _currency : (currencies.isEmpty ? null : currencies.first);
    final r = cur == null ? null : report[cur];
    final org = AppState.instance.activeOrg?.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            SectorPhotoBanner(rubro: Access.instance.rubro,
              title: 'Tu negocio, en números', subtitle: sectorTagline(Access.instance.rubro), height: 142),
            const SizedBox(height: 16),
            if (org != null) Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(org, style: t.textTheme.bodySmall)),
            _monthBar(t),
            const SizedBox(height: 16),
            if (_error != null)
              SoftCard(
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
                ]),
              )
            else if (rows == null)
              const SkeletonList()
            else if (rows.isEmpty)
              const EmptyState(title: 'Sin ventas este mes', body: 'Cuando crees facturas de este mes, aquí verás tus totales.')
            else ...[
              if (currencies.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 8, children: [
                    for (final c in currencies)
                      ChoiceChip(label: Text(c), selected: c == cur, onSelected: (_) => setState(() => _currency = c)),
                  ]),
                ),
              if (r != null) ...[
                Reveal(index: 0, child: _hero(t, r)),
                const SizedBox(height: 12),
                Reveal(index: 1, child: _split(t, r)),
                const SizedBox(height: 12),
                Reveal(index: 2, child: _days(t, r)),
                const SizedBox(height: 12),
                Reveal(index: 3, child: _clients(t, r)),
              ],
              if (rows.any((i) => !countsAsSale(i)))
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text('Los comprobantes rechazados por SUNAT no se cuentan como venta.', style: t.textTheme.bodySmall),
                ),
              const SizedBox(height: 20),
              Reveal(
                index: 4,
                child: GradientButton(
                  label: 'Exportar a Excel (CSV)',
                  icon: Icons.download_rounded,
                  busy: _exporting,
                  onPressed: _exporting ? null : _export,
                ),
              ),
              const SizedBox(height: 8),
              Text('Incluye todos los comprobantes del mes, también los rechazados, con su estado.', textAlign: TextAlign.center, style: t.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthBar(ThemeData t) => SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          IconButton(tooltip: 'Mes anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                '${monthNames[_month - 1]} $_year',
                key: ValueKey('$_year-$_month'),
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            onPressed: _isCurrentMonth ? null : () => _shift(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
      );

  Widget _hero(ThemeData t, CurrencyReport r) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(26), boxShadow: Brand.softShadow(false)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ventas del mes', style: t.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
          const SizedBox(height: 6),
          CountUp(
            value: r.total,
            builder: (_, v) => Text(
              money(v, r.currency),
              style: t.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${r.count} ${r.count == 1 ? 'comprobante' : 'comprobantes'} · promedio ${money(r.average, r.currency)}',
            style: t.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ]),
      );

  Widget _split(ThemeData t, CurrencyReport r) => Column(children: [
        Row(children: [
          Expanded(child: _stat(t, 'Subtotal', money(r.subtotal, r.currency))),
          const SizedBox(width: 12),
          Expanded(child: _stat(t, 'Impuesto', money(r.tax, r.currency))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _stat(t, 'Por cobrar', money(r.receivable, r.currency))),
          const SizedBox(width: 12),
          Expanded(child: _stat(t, 'Vencido', money(r.overdue, r.currency), color: r.overdue > 0 ? Brand.bad : null)),
        ]),
      ]);

  Widget _stat(ThemeData t, String label, String value, {Color? color}) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.textTheme.bodySmall),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Money(value, size: 18, weight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _days(ThemeData t, CurrencyReport r) {
    final days = DateTime(_year, _month + 1, 0).day;
    final maxV = r.byDay.values.fold<double>(0, (a, b) => b > a ? b : a);
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Por día', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var d = 1; d <= days; d++)
              Expanded(
                child: Tooltip(
                  message: '$d: ${money(r.byDay[d] ?? 0, r.currency)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: maxV == 0 ? 0 : (r.byDay[d] ?? 0) / maxV),
                      duration: Duration(milliseconds: 500 + d * 12),
                      curve: Curves.easeOutCubic,
                      builder: (_, f, _) => Container(
                        height: 3 + 93 * f,
                        decoration: BoxDecoration(
                          gradient: (r.byDay[d] ?? 0) > 0 ? Brand.heroGradient : null,
                          color: (r.byDay[d] ?? 0) > 0 ? null : t.colorScheme.outline.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('1', style: t.textTheme.bodySmall),
          Text('$days', style: t.textTheme.bodySmall),
        ]),
      ]),
    );
  }

  Widget _clients(ThemeData t, CurrencyReport r) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mejores clientes', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final (i, c) in r.topClients.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: t.colorScheme.primary.withValues(alpha: .12),
                  child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.colorScheme.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Money(money(c.total, r.currency), size: 14),
              ]),
            ),
        ]),
      );
}
