// Inicio (v3.1): el Inicio que te gustaba de la v2.0, mejorado y con la plata correcta.
//  - Encabezado aurora con la cifra del mes que sube contando, píldora de "ventas emitidas", meta y gráfico de 14 días.
//  - Accesos de TU rubro (cada uno con su color), sugerencias del Copiloto, buscador y filtros.
//  - Lista de comprobantes: el que acabas de crear aparece arriba al instante.
//  - "Clientes de hoy": quién compró, a qué hora y qué se llevó (solo datos reales).
// Las cifras vienen del servidor con una sola regla (con IGV, sin anuladas, menos notas de crédito).

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../growth.dart';
import '../models.dart';
import '../models_v2.dart';
import '../rubros.dart';
import '../services/growth_repo.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/widgets.dart';
import '../ui/retail_layout.dart';
import '../ui/work_queue.dart';
import '../ux/rubro_experience.dart';
import 'catalog.dart';
import 'goal_sheet.dart';
import 'home.dart' show CopilotCards, HomeHeader, InvoiceRow;
import 'invoice_detail.dart';
import 'role_home.dart';
import 'jobs.dart' show JobDetailScreen, showJobForm;
import 'new_invoice.dart' show NewInvoiceScreen;
import '../nav/navigation_contract.dart';
import '../permissions.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> with LiveReload<InicioScreen> {
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _month;
  ({String currency, DateTime end, List<double> days})? _trend;
  int _trendRequest = 0;
  List<InvoiceRecord>? _items;
  String? _error;
  String _filter = 'all';
  String _query = '';
  int _limit = 100;
  bool _tried = false;
  double? _goal;
  List<DailyAlert> _alerts = const [];
  String? _org;
  List<Job> _work = const [];
  String? _workError;
  bool _workLoading = true;

  bool get _appointmentHome => const ['salon', 'consultorio', 'educacion'].contains(Access.instance.rubro);
  bool get _showWork => Access.instance.can('jobs') && (_appointmentHome
      ? Access.instance.has('agenda')
      : const ['servicios_tecnicos', 'taller', 'construccion'].contains(Access.instance.rubro) && Access.instance.has('trabajos'));

  @override
  List<String> get liveTables => const ['invoices', 'payments', 'jobs'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _org = Repo.activeOrgId;
    // Lo último que se vio de esta empresa aparece YA; los datos nuevos llegan detrás y se actualizan solos.
    _today = LiveCache.get<Map<String, dynamic>>('inicio.today');
    _month = LiveCache.get<Map<String, dynamic>>('inicio.month');
    _items = LiveCache.get<List<InvoiceRecord>>('inicio.items');
    _goal = LiveCache.get<double>('inicio.goal');
    _alerts = LiveCache.get<List<DailyAlert>>('inicio.alerts') ?? const [];
    _tried = _month != null || _items != null;
    _load();
    startLive(); // tiempo real: venta o cobro nuevo = se actualiza sin tocar nada
    AppState.instance.addListener(_onApp);
  }

  @override
  void dispose() {
    stopLive();
    AppState.instance.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    if (_org == Repo.activeOrgId) return;
    _org = Repo.activeOrgId;
    setState(() {
      _today = null;
      _month = null;
      _trend = null;
      _items = null;
      _goal = null;
      _alerts = const [];
      _tried = false;
      _work = const [];
      _workError = null;
      _workLoading = true;
    });
    _load();
  }

  /// Cada pieza se muestra apenas llega (no espera a la más lenta) y se guarda para la próxima vez.
  Future<void> _load() async {
    final org = Repo.activeOrgId;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final now = DateTime.now();
    final today = todayIso(now);
    final tomorrow = todayIso(now.add(const Duration(days: 1)));
    final first = todayIso(DateTime(now.year, now.month, 1));
    final next = todayIso(DateTime(now.year, now.month + 1, 1));
    final seeMoney = Access.instance.can('finance') || Access.instance.can('collect');
    final trendRequest = ++_trendRequest;
    bool same() => mounted && org == Repo.activeOrgId;

    Future<void> piece<V>(Future<V> f, String key, void Function(V v) apply) async {
      try {
        final v = await f;
        if (!same()) return;
        LiveCache.put(key, v);
        setState(() {
          apply(v);
          _tried = true;
        });
      } catch (_) {}
    }

    // Todo en paralelo y agregado en la base: dos números, no miles de filas.
    await Future.wait<void>([
      if (seeMoney && Access.instance.rubro == 'bodega' && Access.instance.allows('reports.view')) () async {
        final days = await V2Repo.salesDaily(today, cur);
        if (days != null && same() && trendRequest == _trendRequest) {
          setState(() => _trend = (currency: cur, end: now, days: days));
        }
      }(),
      if (_showWork) () async {
        try {
          final jobs = await V2Repo.jobs(openOnly: true, limit: 100,
            from: _appointmentHome ? DateTime(now.year, now.month, now.day) : null,
            to: _appointmentHome ? DateTime(now.year, now.month, now.day + 1) : null);
          if (same()) {
            setState(() {
            _work = jobs.where((j) => _appointmentHome ? j.kind == 'cita' : j.kind != 'cita').take(4).toList();
            _workLoading = false;
            _workError = null;
            });
          }
        } catch (_) {
          if (same()) {
            setState(() { _workError = 'No pudimos cargar tus actividades.'; _workLoading = false; });
          }
        }
      }(),
      if (seeMoney) piece<Map<String, dynamic>?>(V2Repo.salesSummary(today, tomorrow, cur), 'inicio.today', (v) => _today = v),
      if (seeMoney) piece<Map<String, dynamic>?>(V2Repo.salesSummary(first, next, cur), 'inicio.month', (v) => _month = v),
      piece<double?>(GrowthRepo.monthlyGoal().catchError((Object _) => null), 'inicio.goal', (v) => _goal = v),
      piece<List<DailyAlert>>(V2Repo.dailyAlerts().catchError((Object _) => const <DailyAlert>[]), 'inicio.alerts', (v) => _alerts = v),
      () async {
        try {
          final inv = await Repo.listInvoices(limit: _limit);
          if (!same()) return;
          LiveCache.put('inicio.items', inv);
          setState(() {
            _items = inv;
            _error = null;
            _tried = true;
          });
        } catch (e) {
          if (same()) setState(() => _error = friendly(e));
        }
      }(),
    ]);
  }

  List<InvoiceRecord> _visible() {
    final q = _query.trim().toLowerCase();
    return (_items ?? const <InvoiceRecord>[]).where((i) {
      final f = i.fiscalStatus;
      final ok = switch (_filter) {
        'draft' => f == null && i.status == 'draft',
        'issued' => f == 'accepted',
        'review' => f == 'rejected' || f == 'error' || f == 'pending',
        'due' => i.receivable,
        _ => true,
      };
      if (!ok) return false;
      return q.isEmpty || i.clientName.toLowerCase().contains(q) || (i.fiscalNumber ?? i.number).toLowerCase().contains(q);
    }).toList();
  }

  /// Compras de hoy: quién, a qué hora y qué se llevó. Solo ventas reales (no borradores, anuladas ni notas de crédito).
  List<InvoiceRecord> _todayBuyers() {
    final today = todayIso();
    final list = (_items ?? const <InvoiceRecord>[]).where((i) => i.issueDate == today && i.countsAsSale && !i.isCreditNote).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    return list;
  }

  static String _hour(DateTime? d) {
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  static String _what(InvoiceRecord i) {
    if (i.items.isEmpty) return 'Sin detalle';
    final first = i.items.first.description.trim();
    final more = i.items.length - 1;
    return more > 0 ? '$first y $more más' : first;
  }

  Future<void> _open(InvoiceRecord inv) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id)));
    if (mounted) _load();
  }

  Future<void> _setGoal(double salesSoFar) async {
    final v = await showGoalSheet(context, current: _goal, salesSoFar: salesSoFar);
    if (v != null && mounted) setState(() => _goal = v <= 0 ? null : v);
  }

  /// Acción principal del rubro (contrato de navegación). Bodega ya la tiene en la cabecera ("Vender").
  PrimaryAction? _primary(Access a) {
    if (a.rubro == 'bodega') return null;
    final p = primaryActionFor(a.rubro);
    if (p == null || !a.allows(p.permission) || (p.feature != null && !a.has(p.feature!))) return null;
    if (p.kind == PrimaryKind.feature && !(featureById(p.featureId!)?.allowed ?? false)) return null;
    return p;
  }

  Future<void> _runPrimary(PrimaryAction p) async {
    switch (p.kind) {
      case PrimaryKind.feature:
        final f = featureById(p.featureId!);
        if (f != null && f.allowed) await openFeature(context, f);
      case PrimaryKind.jobForm:
        final jobId = await showJobForm(context, kind: p.jobKind);
        if (jobId != null && mounted) showSuccess(context, '${p.label} registrada');
      case PrimaryKind.quote:
        final quoteId = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen(quote: true)));
        if (quoteId != null && mounted) showSuccess(context, 'Pedido guardado');
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final spec = rubroFor(a.rubro);
    final guide = experienceFor(spec?.id);
    final isBodega = a.rubro == 'bodega';
    final dockInset = MediaQuery.paddingOf(context).bottom;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final seeMoney = a.can('finance') || a.can('collect');
    final todayTotal = ((_today?['sales_total'] as num?) ?? 0).toDouble();
    final todayCount = ((_today?['sales_count'] as num?) ?? 0).toInt();
    final monthTotal = ((_month?['sales_total'] as num?) ?? 0).toDouble();
    final monthCount = ((_month?['sales_count'] as num?) ?? 0).toInt();
    final drafts = ((_month?['drafts_count'] as num?) ?? 0).toInt();
    final draftsTotal = ((_month?['drafts_total'] as num?) ?? 0).toDouble();
    final list = _visible();
    // Inicio muestra un resumen: la búsqueda completa corresponde a Comprobantes.
    final activity = isBodega ? list.take(4).toList() : list;
    final buyers = _todayBuyers();
    final cupertinoRefresh = isBodega &&
        (t.platform == TargetPlatform.iOS || t.platform == TargetPlatform.macOS);
    final scrollView = CustomScrollView(physics: cupertinoRefresh
        ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
        : const AlwaysScrollableScrollPhysics(), slivers: [
          if (cupertinoRefresh) CupertinoSliverRefreshControl(onRefresh: _load),
          if (isBodega)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 19, 20, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(MaterialLocalizations.of(context).formatFullDate(DateTime.now()),
                      style: t.textTheme.labelMedium?.copyWith(
                        color: t.colorScheme.primary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Semantics(header: true, child: Text(
                      'Hola, ${AppState.instance.activeOrg?.name ?? 'tu negocio'}',
                      style: t.textTheme.headlineMedium?.copyWith(
                        fontSize: 33, height: 1.10, letterSpacing: -1.1))),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: isBodega
                  ? const EdgeInsets.fromLTRB(16, 12, 16, 0)
                  : EdgeInsets.zero,
              child: HomeHeader(
              compact: isBodega,
              name: AppState.instance.activeOrg?.name ?? '',
              currency: cur,
              total: seeMoney ? monthTotal : 0,
              count: monthCount,
              drafts: drafts,
              draftsTotal: draftsTotal,
              loaded: seeMoney && _tried && _month != null,
              showMonth: a.allows('reports.view'),
              goal: seeMoney ? _goal : null,
              series: !seeMoney ? const <double>[] : isBodega
                  ? (_trend?.currency == cur ? _trend!.days : const <double>[])
                  : dailySeries(_items ?? const <InvoiceRecord>[], currency: cur, today: todayIso()),
              seriesEndDate: isBodega ? _trend?.end : null,
              onGoal: () => _setGoal(monthTotal),
              todayTotal: seeMoney && _today != null ? todayTotal : null,
              todayCount: isBodega && _today == null ? null : todayCount,
              // La navegación y las acciones de voz viven únicamente en MainShell.
              onMenu: null,
              onSale: null,
              ),
            ),
          ),
          if ((!isBodega ? _primary(a) : null) case final p?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: ConstrainedBox(
                  // Altura mínima, no fija: con letra grande (modo Fácil) el botón crece y no corta el texto.
                  constraints: const BoxConstraints(minHeight: 56, minWidth: double.infinity),
                  child: FilledButton.icon(
                    key: const ValueKey('inicio-primary-action'),
                    onPressed: () => _runPrimary(p),
                    icon: Icon(p.icon),
                    label: Text(p.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ),
            ),
          // Bodega usa exclusivamente el Drawer/rail de MainShell. Aquí solo
          // quedan indicadores y actividad; el grid antiguo duplicaba el menú.
          if (!isBodega && spec != null)
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SectorPhotoBanner(
                  rubro: spec.id,
                  title: guide.homeTitle,
                  subtitle: guide.homeSubtitle,
                )),
            ),
          // Conservar métricas y operaciones pendientes, sin otros menús en Bodega.
          SliverToBoxAdapter(
            child: RoleHomePanel(
              key: ValueKey('role-home-${Repo.activeOrgId}-${a.role}-${a.license.plan}'),
              showLinks: !isBodega,
              exclude: {if (a.rubro == 'bodega' || primaryActionFor(a.rubro)?.featureId == 'pos') 'sell_cta'},
            ),
          ),
          if (_showWork) SliverToBoxAdapter(child: WorkQueue(
            title: _appointmentHome ? 'Tus citas de hoy' : 'Trabajos por avanzar', jobs: _work,
            loading: _workLoading, error: _workError, onRetry: _load,
            onOpen: (job) async {
              if (!_showWork || job.id == null) return;
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id!)));
              if (mounted) _load();
            },
          )),
          if (a.has('copiloto')) SliverToBoxAdapter(child: CopilotCards(alerts: _alerts, onChanged: _load, max: AppState.instance.easyMode.value ? 1 : 2)),
          if (!isBodega && buyers.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Reveal(
                  index: 2,
                  child: SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.groups_rounded, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${spec?.word('clients') ?? 'Clientes'} de hoy', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                        Text(buyers.length == 1 ? '1 compra' : '${buyers.length} compras', style: t.textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 6),
                      for (final b in buyers.take(6))
                        Pressable(
                          onTap: () => _open(b),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(children: [
                              SizedBox(width: 62, child: Text(_hour(b.createdAt), style: t.textTheme.bodySmall)),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(b.clientName == '—' ? 'Cliente sin nombre' : b.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                                  Text(_what(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                                ]),
                              ),
                              if (seeMoney) Text(money(b.totals.total, b.currency), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          if (_error != null && _items == null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          else if (_items == null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              sliver: SliverList.separated(itemCount: 4, separatorBuilder: (_, _) => const SizedBox(height: 12), itemBuilder: (_, _) => const SkeletonCard()),
            )
          else if (_items!.isEmpty)
            const SliverToBoxAdapter(
              child: Reveal(child: EmptyState(title: 'Aún no hay comprobantes', body: 'Cuando emitas una boleta o factura, aparecerá aquí. Las citas, pedidos y trabajos siguen en sus propias secciones.')),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (isBodega) ...[
                    Text('Actividad reciente', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Últimas operaciones del negocio', style: t.textTheme.bodySmall),
                  ],
                  if (!isBodega) TextField(
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: 'Buscar por cliente o número', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                  if (!isBodega) const SizedBox(height: 10),
                  if (!isBodega) SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (k, label) in const [('all', 'Todas'), ('draft', 'Borradores'), ('issued', 'Emitidas'), ('due', 'Por cobrar'), ('review', 'Por revisar')])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
            if (activity.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32, 40, 32, isBodega ? 24 : 140),
                  child: Text('Nada coincide con tu búsqueda.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, isBodega ? 16 : 160),
                sliver: SliverList.separated(
                  itemCount: activity.length + (!isBodega && _items!.length >= _limit ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => i == activity.length
                      ? Center(
                          child: TextButton.icon(
                            onPressed: () {
                              _limit += 100;
                              _load();
                            },
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Cargar más'),
                          ),
                        )
                      : Reveal(
                          key: ValueKey(activity[i].id),
                          index: 3 + (i < 8 ? i : 8),
                          child: RepaintBoundary(child: InvoiceRow(
                            inv: activity[i], onTap: () => _open(activity[i]))),
                        ),
                ),
              ),
          ],
          if (isBodega)
            SliverToBoxAdapter(child: SizedBox(height: dockInset + 16)),
        ]);
    return RetailResponsiveFrame(maxWidth: 1200, child: Scaffold(
      backgroundColor: isBodega ? Colors.transparent : null,
      body: cupertinoRefresh ? scrollView : RefreshIndicator(
        onRefresh: _load, edgeOffset: isBodega ? 0 : 140, child: scrollView),
    ));
  }
}
