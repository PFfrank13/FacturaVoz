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
import '../ux/rubro_experience.dart';
import 'catalog.dart';
import 'goal_sheet.dart';
import 'home.dart' show CopilotCards, HomeHeader, InvoiceRow;
import 'hubs_v3.dart' show showNewSaleSheet;
import 'invoice_detail.dart';
import 'menu.dart';

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
      _items = null;
      _goal = null;
      _alerts = const [];
      _tried = false;
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final spec = rubroFor(a.rubro);
    final guide = experienceFor(spec?.id);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final seeMoney = a.can('finance') || a.can('collect');
    final todayTotal = ((_today?['sales_total'] as num?) ?? 0).toDouble();
    final todayCount = ((_today?['sales_count'] as num?) ?? 0).toInt();
    final monthTotal = ((_month?['sales_total'] as num?) ?? 0).toDouble();
    final monthCount = ((_month?['sales_count'] as num?) ?? 0).toInt();
    final drafts = ((_month?['drafts_count'] as num?) ?? 0).toInt();
    final draftsTotal = ((_month?['drafts_total'] as num?) ?? 0).toDouble();
    final shortcuts = [for (final id in spec?.home ?? const ['facturar', 'clientes', 'cobranza', 'negocio']) if (!(a.can('sell') && id == 'pos')) if (featureById(id) case final f? when f.roleOk) f];
    final list = _visible();
    final buyers = _todayBuyers();
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
              loaded: seeMoney && _tried && _month != null,
              goal: seeMoney ? _goal : null,
              series: seeMoney ? dailySeries(_items ?? const <InvoiceRecord>[], currency: cur, today: todayIso()) : const <double>[],
              onGoal: () => _setGoal(monthTotal),
              todayTotal: seeMoney && _today != null ? todayTotal : null,
              todayCount: todayCount,
              onMenu: () => pushPremium(context, const MenuScreen()),
            ),
          ),
          if (spec != null)
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SectorPhotoBanner(
                  rubro: spec.id,
                  title: guide.homeTitle,
                  subtitle: guide.homeSubtitle,
                )),
            ),
          if (a.can('sell') || shortcuts.isNotEmpty)
            SliverToBoxAdapter(
              child: Reveal(
                index: 1,
                child: SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(104),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
                    children: [
                      if (a.can('sell'))
                        QuickAction(icon: Icons.add_shopping_cart_rounded, label: 'Nueva venta', colors: Brand.coralGradient.colors, onTap: () => showNewSaleSheet(context).then((_) {
                              if (mounted) _load();
                            })),
                      for (final f in shortcuts.take(3))
                        QuickAction(
                          icon: f.planOk ? f.icon : Icons.lock_rounded,
                          label: shortActionLabel(f.id, f.title),
                          colors: [featureColor(f.id).withValues(alpha: 0.8), featureColor(f.id)],
                          onTap: f.planOk ? () => openFeature(context, f) : () => pushPremium(context, const MenuScreen()),
                        ),
                      QuickAction(icon: Icons.menu_rounded, label: 'Ver todas', colors: const [Brand.lightInk, Brand.indigoDeep], onTap: () => pushPremium(context, const MenuScreen())),
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(child: CopilotCards(alerts: _alerts, onChanged: _load, max: AppState.instance.easyMode.value ? 1 : 2)),
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
