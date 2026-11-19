// Inicio (v3.1): el Inicio que te gustaba de la v2.0, mejorado y con la plata correcta.
//  - Encabezado aurora con la cifra del mes que sube contando, píldora de "ventas emitidas", meta y gráfico de 14 días.
//  - Accesos de TU rubro (cada uno con su color), sugerencias del Copiloto, buscador y filtros.
//  - Lista de comprobantes: el que acabas de crear aparece arriba al instante.
//  - "Clientes de hoy": quién compró, a qué hora y qué se llevó (solo datos reales).
// Las cifras vienen del servidor con una sola regla (con IGV, sin anuladas, menos notas de crédito).

import 'package:flutter/material.dart';

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
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ui/work_queue.dart';
import '../ux/rubro_experience.dart';
import 'catalog.dart';
import 'goal_sheet.dart';
import 'home.dart' show CopilotCards, HomeHeader, HomeScreen, InvoiceRow;
import '../ux/commerce_navigation.dart';
import 'license_gate.dart' show PlanScreen;
import 'invoice_detail.dart';
import 'menu.dart';
import 'jobs.dart' show JobDetailScreen;

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> with LiveReload<InicioScreen> {
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _month;
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

  bool get _appointmentHome => false;
  bool get _showWork => false; // historical screens preserved; no sector navigation
  bool get _canReadInvoices => Access.instance.has('facturar') &&
      (Access.instance.can('sell') || Access.instance.can('finance') || Access.instance.can('collect'));
  bool get _canSeeMoney => Access.instance.has('facturar') &&
      (Access.instance.can('finance') || Access.instance.can('collect'));
  int _generation = 0;
  String? _summaryError;

  @override
  List<String> get liveTables => const ['invoices', 'payments'];

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
    Access.instance.addListener(_onAccess);
  }

  @override
  void dispose() {
    _generation++;
    Access.instance.removeListener(_onAccess);
    stopLive();
    AppState.instance.removeListener(_onApp);
    super.dispose();
  }

  void _onAccess() {
    _generation++;
    setState(() {
      _today = null; _month = null; _items = null;
      _goal = null; _alerts = const []; _summaryError = null; _error = null;
      _tried = false;
    });
    _load();
  }

  void _onApp() {
    if (_org == Repo.activeOrgId) return;
    _org = Repo.activeOrgId;
    setState(() {
      _today = null;
      _month = null;
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
    final generation = ++_generation;
    if (!Access.instance.licenseReady) return;
    final org = Repo.activeOrgId;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final now = DateTime.now();
    final today = todayIso(now);
    final tomorrow = todayIso(now.add(const Duration(days: 1)));
    final first = todayIso(DateTime(now.year, now.month, 1));
    final next = todayIso(DateTime(now.year, now.month + 1, 1));
    final seeMoney = _canSeeMoney;
    bool same() => mounted && generation == _generation && org == Repo.activeOrgId;
    if (mounted) setState(() => _summaryError = null);

    Future<void> piece<V>(Future<V> f, String key, void Function(V v) apply) async {
      try {
        final v = await f;
        if (!same()) return;
        if (key == 'inicio.today' || key == 'inicio.month') {
          if (v is! Map || v['sales_total'] is! num || v['sales_count'] is! num) {
            throw StateError('Resumen no disponible');
          }
        }
        LiveCache.put(key, v);
        setState(() {
          apply(v);
          _tried = true;
        });
      } catch (_) {
        if (same()) setState(() => _summaryError = 'No pudimos actualizar el resumen.');
      }
    }

    // Todo en paralelo y agregado en la base: dos números, no miles de filas.
    await Future.wait<void>([
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
      if (seeMoney) piece<double?>(GrowthRepo.monthlyGoal(), 'inicio.goal', (v) => _goal = v),
      if (!basicLocalPreview && Access.instance.license.plan.toUpperCase() != 'BASICO' && Access.instance.has('copiloto')) piece<List<DailyAlert>>(V2Repo.dailyAlerts(), 'inicio.alerts', (v) => _alerts = v),
      if (_canReadInvoices) () async {
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
    if (!_canReadInvoices) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id)));
    if (mounted) _load();
  }

  Future<void> _setGoal(double salesSoFar) async {
    if (!_canSeeMoney || !Access.instance.isAdmin) return;
    final v = await showGoalSheet(context, current: _goal, salesSoFar: salesSoFar);
    if (v != null && mounted) setState(() => _goal = v <= 0 ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final spec = rubroFor('bodega');
    final guide = experienceFor(spec?.id);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final seeMoney = _canSeeMoney;
    final todayTotal = ((_today?['sales_total'] as num?) ?? 0).toDouble();
    final todayCount = ((_today?['sales_count'] as num?) ?? 0).toInt();
    final monthTotal = ((_month?['sales_total'] as num?) ?? 0).toDouble();
    final monthCount = ((_month?['sales_count'] as num?) ?? 0).toInt();
    final drafts = ((_month?['drafts_count'] as num?) ?? 0).toInt();
    final draftsTotal = ((_month?['drafts_total'] as num?) ?? 0).toDouble();
    // La portada Básico prioriza operaciones reales, sin mostrar premium.
    // Cada destino mantiene las comprobaciones de licencia y rol existentes.
    final shortcuts = [
      for (final id in const ['pos', 'caja', 'productos', 'inventario', 'fiados'])
        if (featureById(id) case final f?
            when commerceEntryVisible(id: f.id, hubPlan: a.license.plan, roleOk: f.roleOk, planOk: f.planOk)) f,
    ];
    final list = _canReadInvoices ? _visible() : <InvoiceRecord>[];
    final buyers = _canReadInvoices && a.can('clients') ? _todayBuyers() : <InvoiceRecord>[];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: 140,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: HomeHeader(
              name: AppState.instance.activeOrg?.name ?? '',
              currency: cur,
              total: seeMoney ? monthTotal : 0,
              count: monthCount,
              drafts: drafts,
              draftsTotal: draftsTotal,
              loaded: seeMoney && _tried && _month != null && _summaryError == null,
              showMetrics: seeMoney,
              canEditGoal: seeMoney && a.isAdmin,
              summaryError: _summaryError,
              onRetrySummary: _load,
              goal: seeMoney ? _goal : null,
              series: seeMoney ? dailySeries(_items ?? const <InvoiceRecord>[], currency: cur, today: todayIso()) : const <double>[],
              onGoal: () => _setGoal(monthTotal),
              todayTotal: seeMoney && _today != null ? todayTotal : null,
              todayCount: todayCount,
              onToday: _canReadInvoices ? () => openFeature(context, FeatureEntry(id: 'comprobantes', title: 'Ventas de hoy', subtitle: '', icon: Icons.receipt_long, group: 'Vender', feature: 'facturar', builder: (_) => HomeScreen(initialDate: DateTime.now()))) : null,
              onMonth: featureById('reportes')!.allowed ? () => openFeature(context, featureById('reportes')!) : null,
              onMenu: () => pushPremium(context, const MenuScreen()),
            ),
          ),
          if (basicLocalPreview)
            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('BÁSICO · VISTA LOCAL DE NAVEGACIÓN',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: Color(0xFFE6B656), letterSpacing: 0.6)),
            )),
          // En mostrador la venta debe estar arriba: accesos antes de banners.
          // Acciones adaptables: sin desbordamiento horizontal ni botones
          // fantasma; todos abren destinos del catálogo existente.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: LayoutBuilder(builder: (context, constraints) {
                final actions = <Widget>[
                  for (final f in shortcuts)
                    _InicioBodegaAction(
                      label: f.id == 'pos' ? 'Nueva venta'
                          : f.id == 'productos' ? 'Productos'
                          : f.id == 'caja' ? 'Caja'
                          : f.id == 'fiados' ? 'Fiados'
                          : f.title,
                      icon: f.icon,
                      color: featureColor(f.id),
                      primary: f.id == 'pos',
                      onTap: () async {
                        await openBasicCommerceFeature(context, f);
                        if (mounted) _load();
                      },
                    ),
                  _InicioBodegaAction(
                    label: 'Ver todas', icon: Icons.grid_view_rounded,
                    color: Brand.indigo, onTap: () => pushPremium(context, const MenuScreen()),
                  ),
                ];
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final columns = constraints.maxWidth >= 290 && scale <= 1.5 ? 2 : 1;
                const gap = 12.0;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final action in actions) SizedBox(width: width, child: action),
                ]);
              }),
            ),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ActionChip(
              avatar: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: Text(commerceExperience(commerceViewPlan(a.license.plan))),
              onPressed: () => pushPremium(context, const PlanScreen()),
            ),
          )),
          if (spec != null)
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SectorPhotoBanner(
                  rubro: spec.id,
                  title: guide.homeTitle,
                  subtitle: guide.homeSubtitle,
                )),
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
          if (!basicLocalPreview && a.license.plan.toUpperCase() != 'BASICO' && a.has('copiloto')) SliverToBoxAdapter(child: CopilotCards(alerts: _alerts, onChanged: _load, max: AppState.instance.easyMode.value ? 1 : 2)),
          if (buyers.isNotEmpty)
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
          if (!_canReadInvoices)
            const SliverToBoxAdapter(child: SizedBox(height: 140))
          else if (_error != null && _items == null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Reintentar'))])))
          else if (_items == null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              sliver: SliverList.separated(itemCount: 4, separatorBuilder: (_, _) => const SizedBox(height: 12), itemBuilder: (_, _) => const SkeletonCard()),
            )
          else if (_items!.isEmpty)
            const SliverToBoxAdapter(
              child: Reveal(child: EmptyState(title: 'Aún no hay comprobantes', body: 'Cuando emitas una boleta o factura, aparecerá aquí.')),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: 'Buscar por cliente o número', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
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
            if (list.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 140),
                  child: Text('Nada coincide con tu búsqueda.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                sliver: SliverList.separated(
                  itemCount: list.length + (_items!.length >= _limit ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => i == list.length
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
                          key: ValueKey(list[i].id),
                          index: 3 + (i < 8 ? i : 8),
                          child: RepaintBoundary(child: InvoiceRow(inv: list[i], onTap: () => _open(list[i]))),
                        ),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}


/// Atajo de mostrador: área táctil amplia, 2 columnas en móviles normales,
/// texto accesible y sin deslizar horizontalmente para buscar funciones.
class _InicioBodegaAction extends StatelessWidget {
  const _InicioBodegaAction({required this.label, required this.icon,
    required this.color, required this.onTap, this.primary = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = primary ? Colors.white : t.colorScheme.onSurface;
    return Material(
      color: primary ? Brand.indigo : t.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: primary ? Brand.indigo : t.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 92),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 25, color: primary ? Colors.white : color),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelLarge?.copyWith(
                  color: fg, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
