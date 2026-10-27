import 'package:flutter/material.dart';

import '../app_state.dart';
import '../errors.dart';
import '../finance.dart';
import '../models.dart';
import '../models_pro.dart';
import '../reports.dart' show monthNames, monthRange;
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'assistant.dart';
import 'expenses.dart';
import 'products.dart';
import 'reports.dart';
import 'scan.dart';

/// "Negocio": rentabilidad real (ventas − gastos), flujo de caja, IGV estimado, proyección y radar de stock.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  bool _loading = true;
  String? _error;
  bool _missing = false;
  int _token = 0;

  List<InvoiceRecord> _invoices = const [];
  List<Expense> _expenses = const [];
  List<DatedPayment> _payments = const [];
  List<InvoiceRecord> _receivables = const [];
  Map<String, ClientPayStats> _stats = const {};
  List<ProductVelocity> _stock = const [];
  String? _orgSeen;

  @override
  void initState() {
    super.initState();
    _orgSeen = Repo.activeOrgId;
    AppState.instance.addListener(_onApp);
    AppState.instance.dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onApp);
    AppState.instance.dataVersion.removeListener(_load);
    super.dispose();
  }

  void _onApp() {
    if (_orgSeen != Repo.activeOrgId) {
      _orgSeen = Repo.activeOrgId;
      _load();
    }
  }

  String get _today => todayIso();
  String get _monthKey => '$_year-${_month.toString().padLeft(2, '0')}';
  bool get _isCurrent => _year == DateTime.now().year && _month == DateTime.now().month;

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final first = monthRange(DateTime(_year, _month - 5, 1).year, DateTime(_year, _month - 5, 1).month).from;
      final r = monthRange(_year, _month);
      final invoices = await Repo.listInvoicesBetween(first, r.toExclusive);
      var expenses = const <Expense>[];
      var payments = const <DatedPayment>[];
      var receivables = const <InvoiceRecord>[];
      var stats = const <String, ClientPayStats>{};
      var stock = const <ProductVelocity>[];
      var missing = false;
      try {
        // Para el ritmo de gasto se miran también los 90 días previos a hoy.
        final from = [first, addDays(_today, -90)].reduce((a, b) => a.compareTo(b) < 0 ? a : b);
        expenses = await ProRepo.listExpenses(from, addDays(_today, 1).compareTo(r.toExclusive) > 0 ? addDays(_today, 1) : r.toExclusive);
        payments = await ProRepo.listPaymentsBetween(r.from, r.toExclusive);
        receivables = await ProRepo.listReceivables();
        stats = await ProRepo.clientStats();
        stock = await ProRepo.productVelocity();
      } catch (e) {
        if (!ProRepo.isMissingMigration(e)) rethrow;
        missing = true;
      }
      if (!mounted || token != _token) return;
      setState(() {
        _invoices = invoices;
        _expenses = expenses;
        _payments = payments;
        _receivables = receivables;
        _stats = stats;
        _stock = stock;
        _missing = missing;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  void _shift(int delta) {
    Haptics.select();
    final d = DateTime(_year, _month + delta, 1);
    final now = DateTime.now();
    if (d.isAfter(DateTime(now.year, now.month, 1))) return;
    setState(() {
      _year = d.year;
      _month = d.month;
    });
    _load();
  }

  Future<void> _addExpense() async {
    if (await showExpenseSheet(context) && mounted) {
      showSuccess(context, 'Gasto registrado');
      AppState.instance.bump();
    }
  }

  Future<void> _scan() async {
    final saved = await pushPremium<bool>(context, const ScanScreen());
    if (saved == true) AppState.instance.bump();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final top = MediaQuery.paddingOf(context).top;
    final prevKey = () {
      final d = DateTime(_year, _month - 1, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    }();
    bool inMonth(String iso, String key) => iso.startsWith(key);
    final monthInv = _invoices.where((i) => inMonth(i.issueDate, _monthKey));
    final monthExp = _expenses.where((e) => inMonth(e.spentOn, _monthKey));
    final p = profitOf(invoices: monthInv, expenses: monthExp, payments: _payments, currency: cur);
    final prev = profitOf(
      invoices: _invoices.where((i) => inMonth(i.issueDate, prevKey)),
      expenses: _expenses.where((e) => inMonth(e.spentOn, prevKey)),
      payments: const [],
      currency: cur,
    );
    final series = monthlySeries(invoices: _invoices, expenses: _expenses, currency: cur, today: '$_monthKey-01');
    final cats = expensesByCategory(monthExp, cur);
    final daily = dailyExpenseRate(_expenses.where((e) => e.currency == cur && e.spentOn.compareTo(addDays(_today, -90)) >= 0), 90);
    final forecast = forecastCash(receivables: _receivables.where((i) => i.currency == cur), stats: _stats, dailyExpense: daily, today: _today);
    final risky = _stock.where((s) => s.atRisk).toList()..sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));

    String? delta(double now, double before) {
      if (before <= 0 || !_isCurrent && now <= 0) return null;
      final pct = ((now - before) / before * 100).round();
      return '${pct >= 0 ? '+' : ''}$pct %';
    }

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Mi negocio')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, widget.embedded ? top + 18 : 8, 16, 190),
          children: [
            Reveal(
              child: Row(children: [
                Expanded(child: Text(widget.embedded ? 'Mi negocio' : '', style: t.textTheme.headlineMedium)),
                IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text('${monthNames[_month - 1]} $_year', key: ValueKey(_monthKey), style: t.textTheme.titleSmall),
                ),
                IconButton(onPressed: _isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
              ]),
            ),
            const SizedBox(height: 10),
            if (_error != null)
              SoftCard(child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Reintentar'))]))
            else if (_loading && _invoices.isEmpty)
              const SkeletonList(count: 4)
            else ...[
              if (_missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SoftCard(
                    color: Brand.warn.withValues(alpha: 0.10),
                    child: const Text('Ejecuta la migración 20261101_negocio_pro.sql en Supabase para ver gastos, cobros y proyecciones.'),
                  ),
                ),
              Reveal(index: 1, child: _hero(context, p, cur)),
              const SizedBox(height: 12),
              Reveal(
                index: 2,
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.2,
                  children: [
                    MetricTile(icon: Icons.trending_up_rounded, label: 'Ventas (sin IGV)', value: money(p.sales, cur), delta: delta(p.sales, prev.sales), deltaGood: p.sales >= prev.sales),
                    MetricTile(
                      icon: Icons.shopping_bag_rounded,
                      label: 'Gastos (sin IGV)',
                      value: money(p.expenses, cur),
                      delta: delta(p.expenses, prev.expenses),
                      deltaGood: p.expenses <= prev.expenses,
                      color: Brand.goldDeep,
                    ),
                    MetricTile(icon: Icons.south_west_rounded, label: 'Cobrado', value: money(p.cashIn, cur), color: Brand.ok),
                    MetricTile(icon: Icons.north_east_rounded, label: 'Pagado', value: money(p.cashOut, cur), color: Brand.bad),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Reveal(index: 3, child: _igv(context, p, cur)),
              const SizedBox(height: 12),
              Reveal(
                index: 4,
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _addExpense, icon: const Icon(Icons.add_rounded), label: const Text('Gasto'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.document_scanner_rounded), label: const Text('Escanear'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: () => openCopilot(context), icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Preguntar'))),
                ]),
              ),
              const SizedBox(height: 20),
              const SectionTitle('Últimos 6 meses'),
              Reveal(
                index: 5,
                child: SoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _legend(t.colorScheme.primary, 'Ventas'),
                      const SizedBox(width: 14),
                      _legend(Brand.gold, 'Gastos'),
                    ]),
                    const SizedBox(height: 14),
                    DualBars(labels: [for (final m in series) m.label], a: [for (final m in series) m.sales], b: [for (final m in series) m.expenses]),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              SectionTitle('Proyección de caja · 5 semanas', action: 'Ver gastos', onAction: () => pushPremium(context, const ExpensesScreen())),
              Reveal(index: 6, child: _forecast(context, forecast, cur, daily)),
              if (cats.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionTitle('¿En qué se va el dinero?'),
                Reveal(index: 7, child: _categories(context, cats, cur)),
              ],
              const SizedBox(height: 20),
              SectionTitle('Radar de stock', action: 'Productos', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductsScreen()))),
              Reveal(index: 8, child: _stockCard(context, risky)),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen())),
                  icon: const Icon(Icons.table_view_rounded),
                  label: const Text('Reporte de ventas y exportar a Excel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);

  Widget _hero(BuildContext context, ProfitSummary p, String cur) {
    final positive = p.profit >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: positive ? Brand.heroGradient : const LinearGradient(colors: [Color(0xFFD94A5E), Color(0xFFFF8A7A)]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: Brand.softShadow(false, a: 0.25),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(positive ? 'Ganancia del mes' : 'Pérdida del mes', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
            const SizedBox(height: 4),
            CountUp(
              value: p.profit,
              builder: (c, v) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(v, cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              p.invoiceCount == 0 ? 'Aún sin ventas este mes' : '${p.invoiceCount} ventas · flujo de caja ${p.netCash >= 0 ? '+' : ''}${money(p.netCash, cur)}',
              style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5),
            ),
          ]),
        ),
        ProgressRing(
          value: p.margin.clamp(0, 1).toDouble(),
          size: 82,
          stroke: 9,
          color: Colors.white,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(p.margin * 100).round()}%', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            Text('margen', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _igv(BuildContext context, ProfitSummary p, String cur) {
    final t = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Brand.indigo.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.account_balance_rounded, color: Brand.indigo),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('IGV estimado del mes: ${money(p.igvEstimate, cur)}', style: t.textTheme.titleSmall),
            Text(
              'IGV de ventas ${money(p.salesTax, cur)} − crédito fiscal de compras ${money(p.expenseTax, cur)}. Referencial: confírmalo con tu contador.',
              style: t.textTheme.bodySmall,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _forecast(BuildContext context, CashForecast f, String cur, double daily) {
    final t = Theme.of(context);
    final maxAbs = f.weeks.fold<double>(1, (m, w) => [m, w.inflow, w.outflow].reduce((a, b) => a > b ? a : b));
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Entradas esperadas ${money(f.totalIn, cur)} · salidas ${money(f.totalOut, cur)}',
          style: t.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          daily > 0
              ? 'Cobros según cómo paga cada cliente; gastos al ritmo de los últimos 90 días (${money(daily, cur)}/día).'
              : 'Registra tus gastos para proyectar también las salidas.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        for (final w in f.weeks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 52, child: Text(dayMonth(w.start), style: t.textTheme.labelMedium)),
              Expanded(
                child: Column(children: [
                  _hbar(w.inflow / maxAbs, Brand.ok),
                  const SizedBox(height: 3),
                  _hbar(w.outflow / maxAbs, Brand.goldDeep),
                ]),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: Text(
                  '${w.cumulative >= 0 ? '+' : ''}${money(w.cumulative, cur)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: w.cumulative >= 0 ? Brand.ok : Brand.bad),
                ),
              ),
            ]),
          ),
        if (f.warning != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Brand.bad.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Brand.bad, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(f.warning!, style: t.textTheme.bodySmall?.copyWith(color: Brand.bad, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }

  Widget _hbar(double v, Color c) => LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v.clamp(0, 1).toDouble()),
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, k, _) => Container(
              width: (box.maxWidth * k).clamp(3, box.maxWidth).toDouble(),
              height: 8,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      );

  Widget _categories(BuildContext context, List<MapEntry<String, double>> cats, String cur) {
    final t = Theme.of(context);
    final total = cats.fold<double>(0, (s, e) => s + e.value);
    const palette = [Brand.indigo, Brand.goldDeep, Brand.lilac, Brand.gold, Brand.ok, Color(0xFF4FA3D9), Brand.warn, Brand.bad];
    return SoftCard(
      child: Column(children: [
        SegmentBar(values: [for (final c in cats) c.value], colors: palette, height: 12),
        const SizedBox(height: 14),
        for (final (i, c) in cats.take(6).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[i % palette.length], shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(expenseCategories[c.key] ?? c.key, style: t.textTheme.bodyMedium)),
              Text('${(c.value / total * 100).round()}%  ', style: t.textTheme.bodySmall),
              Money(money(c.value, cur), size: 14),
            ]),
          ),
      ]),
    );
  }

  Widget _stockCard(BuildContext context, List<ProductVelocity> risky) {
    final t = Theme.of(context);
    if (risky.isEmpty) {
      final tracked = _stock.where((s) => s.stock != null).length;
      return SoftCard(
        child: Row(children: [
          const Icon(Icons.inventory_rounded, color: Brand.ok),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tracked == 0
                  ? 'Activa el control de stock en tus productos y te avisaré días antes de que se acaben, según lo que vendes.'
                  : 'Todo en orden: ningún producto se acaba en las próximas 2 semanas.',
              style: t.textTheme.bodyMedium,
            ),
          ),
        ]),
      );
    }
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        for (final p in risky.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(Icons.inventory_2_rounded, color: (p.daysLeft ?? 99) < 3 ? Brand.bad : Brand.warn, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                  Text(
                    'Quedan ${qtyText(p.stock ?? 0)} · vendes ${p.perDay.toStringAsFixed(1)}/día',
                    style: t.textTheme.bodySmall,
                  ),
                ]),
              ),
              StatusPill(
                p.daysLeft == null ? 'Stock bajo' : (p.daysLeft! < 1 ? 'Agotado' : '~${p.daysLeft!.round()} días'),
                tone: (p.daysLeft ?? 99) < 3 ? PillTone.bad : PillTone.warn,
              ),
            ]),
          ),
      ]),
    );
  }
}
