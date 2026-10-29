import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../errors.dart';
import '../finance.dart';
import '../growth.dart';
import '../models.dart';
import '../models_pro.dart';
import '../services/growth_repo.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../access.dart';
import '../models_v2.dart';
import '../services/v2_repo.dart';
import 'assistant.dart';
import 'catalog.dart';
import 'client_profile.dart' show openWhatsApp;
import 'jobs.dart' show JobDetailScreen;
import 'clients360.dart';
import 'expenses.dart';
import 'goal_sheet.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'products.dart';
import 'recurring.dart';
import 'scan.dart';
import 'store.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.embedded = false, this.onNavigate});

  /// true dentro de [MainShell]: el micrófono vive en el dock, no aquí.
  final bool embedded;

  /// Cambia de pestaña en el shell (1 Cotizar, 2 Cobrar, 3 Negocio).
  final ValueChanged<int>? onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<InvoiceRecord>? _items;
  String? _error;

  String? _orgSeen;
  String _filter = 'all';
  int _limit = 100;
  bool _more = false;
  String _query = '';
  final _searchFocus = FocusNode();
  RealtimeChannel? _chan;
  Timer? _debounce;
  List<ProductVelocity> _stock = const [];
  int _claims = 0;
  double? _goal;
  int _storeOrders = 0;
  int _recurringDrafts = 0;
  Map<String, dynamic>? _summary; // ventas del mes con la MISMA regla que "Mi negocio" (sales_summary)
  List<DailyAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _orgSeen = Repo.activeOrgId;
    AppState.instance.addListener(_onApp);
    AppState.instance.dataVersion.addListener(_liveReload);
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    _subscribe();
  }

  /// Cambios en vivo: cualquier factura o cobro de la empresa (aunque lo haga otro miembro) refresca los totales.
  void _subscribe() {
    _chan?.unsubscribe();
    _chan = null;
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      PostgresChangeFilter f() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: org);
      _chan = Supabase.instance.client
          .channel('home-$org')
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'invoices', filter: f(), callback: (_) => _liveReload())
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'payments', filter: f(), callback: (_) => _liveReload())
          .subscribe();
    } catch (_) {
      // Sin tiempo real igual funciona: se recarga al volver a esta pantalla.
    }
  }

  void _liveReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _chan?.unsubscribe();
    AppState.instance.removeListener(_onApp);
    AppState.instance.dataVersion.removeListener(_liveReload);
    _searchFocus.dispose();
    super.dispose();
  }

  List<InvoiceRecord> _visible() {
    final q = _query.trim().toLowerCase();
    return (_items ?? const <InvoiceRecord>[]).where((i) {
      final f = i.fiscalStatus;
      final okFilter = switch (_filter) {
        'draft' => f == null && i.status == 'draft',
        'issued' => f == 'accepted',
        'review' => f == 'rejected' || f == 'error' || f == 'pending',
        'due' => i.receivable,
        _ => true,
      };
      if (!okFilter) return false;
      return q.isEmpty || i.clientName.toLowerCase().contains(q) || (i.fiscalNumber ?? i.number).toLowerCase().contains(q);
    }).toList();
  }

  /// Al cambiar de empresa se vuelve a cargar la lista.
  void _onApp() {
    if (!mounted) return;
    if (_orgSeen != Repo.activeOrgId) {
      _orgSeen = Repo.activeOrgId;
      _limit = 100;
      setState(() => _items = null);
      _load();
      _subscribe();
    } else {
      setState(() {});
    }
  }

  Future<void> _load() async {
    try {
      final r = await Repo.listInvoices(limit: _limit);
      if (mounted) {
        setState(() {
          _items = r;
          _more = r.length >= _limit;
          _error = null;
        });
        _loadExtras();
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  /// Datos para los avisos del día (stock y pagos reportados). Si falta la migración, simplemente no aparecen.
  Future<void> _loadExtras() async {
    try {
      final v = await ProRepo.productVelocity();
      if (mounted) setState(() => _stock = v);
    } catch (_) {}
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final now = DateTime.now();
    final sum = await V2Repo.salesSummary(todayIso(DateTime(now.year, now.month, 1)), todayIso(DateTime(now.year, now.month + 1, 1)), cur);
    final alerts = await V2Repo.dailyAlerts();
    if (mounted) {
      setState(() {
        _summary = sum;
        _alerts = alerts;
      });
    }
    final c = await ProRepo.countPendingClaims();
    final goal = await GrowthRepo.monthlyGoal();
    final orders = await GrowthRepo.countNewStoreOrders();
    final drafts = await GrowthRepo.countRecurringDrafts();
    if (!mounted) return;
    if (c != _claims || goal != _goal || orders != _storeOrders || drafts != _recurringDrafts) {
      setState(() {
        _claims = c;
        _goal = goal;
        _storeOrders = orders;
        _recurringDrafts = drafts;
      });
    }
  }

  Future<void> _setGoal(double salesSoFar) async {
    final v = await showGoalSheet(context, current: _goal, salesSoFar: salesSoFar);
    if (v != null && mounted) {
      setState(() => _goal = v <= 0 ? null : v);
      showSuccess(context, v <= 0 ? 'Meta quitada' : '¡Meta fijada!', icon: Icons.flag_rounded);
    }
  }

  Future<void> _push(Widget page) async {
    await pushPremium(context, page);
    if (mounted) _load();
  }

  Future<void> _quickQuote() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewInvoiceScreen(quote: true)));
    AppState.instance.bump();
    widget.onNavigate?.call(1);
  }

  Future<void> _quickExpense() async {
    if (await showExpenseSheet(context) && mounted) {
      showSuccess(context, 'Gasto registrado');
      AppState.instance.bump();
    }
  }

  void _openInsight(Insight i) {
    Haptics.tap();
    switch (i.kind) {
      case 'stock':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductsScreen()));
      case 'pace':
        widget.onNavigate?.call(3);
      case 'due_soon':
        setState(() => _filter = 'due');
      case 'store_orders':
        widget.onNavigate?.call(1);
      case 'recurring':
        setState(() => _filter = 'draft');
      default:
        widget.onNavigate?.call(2);
    }
  }

  /// Último comprobante de cada cliente reciente (para repetir una factura con un toque).
  List<InvoiceRecord> _repeatable() {
    final seen = <String>{};
    final out = <InvoiceRecord>[];
    for (final i in _items ?? const <InvoiceRecord>[]) {
      final name = i.clientName.trim();
      if (name.isEmpty || name == '—' || i.fiscalStatus == 'rejected' || i.items.isEmpty) continue;
      if (seen.add(name.toLowerCase())) out.add(i);
      if (out.length >= 6) break;
    }
    return out;
  }

  Future<void> _repeat(InvoiceRecord inv) async {
    HapticFeedback.selectionClick();
    try {
      final id = await Repo.duplicateInvoice(inv);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Copia de la última factura de ${inv.clientName}. Revísala y emítela.')));
      await _openId(id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear la copia. ${friendly(e)}')));
    }
  }

  Future<void> _newInvoice() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    if (!mounted) return;
    await _load();
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
      if (mounted) _load();
    }
  }

  Future<void> _open(InvoiceRecord inv) => _openId(inv.id);

  Future<void> _openId(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)));
    if (mounted) _load();
  }

  /// Ventas del mes: UNA sola definición en toda la app (servidor: sales_summary). Cuenta comprobantes emitidos o
  /// cobrados (con IGV); NO cuenta borradores, rechazados por SUNAT ni anulados. Antes Inicio sumaba borradores y
  /// "Mi negocio" no: por eso mostraban cifras distintas. Sin la migración v2 se usa la misma regla en el teléfono.
  ({double total, int count, int drafts, double draftsTotal}) _month(String currency) {
    final s = _summary;
    if (s != null) {
      return (
        total: ((s['sales_total'] as num?) ?? 0).toDouble(),
        count: ((s['sales_count'] as num?) ?? 0).toInt(),
        drafts: ((s['drafts_count'] as num?) ?? 0).toInt(),
        draftsTotal: ((s['drafts_total'] as num?) ?? 0).toDouble(),
      );
    }
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    var total = 0.0, drafts = 0.0;
    var count = 0, nDrafts = 0;
    for (final i in _items ?? const <InvoiceRecord>[]) {
      if (!i.issueDate.startsWith(prefix) || i.currency != currency || i.fiscalStatus == 'rejected') continue;
      if (i.status == 'draft') {
        drafts += i.totals.total;
        nDrafts++;
        continue;
      }
      total += i.totals.total;
      count++;
    }
    return (total: round2(total), count: count, drafts: nDrafts, draftsTotal: round2(drafts));
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppState.instance.profile;
    final currency = profile?.currency ?? 'PEN';
    final m = _month(currency);
    final t = Theme.of(context);
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // El micrófono se esconde mientras se busca (teclado abierto o buscador enfocado).
      floatingActionButton: widget.embedded ? null : Builder(builder: (context) {
        final hide = _searchFocus.hasFocus || MediaQuery.viewInsetsOf(context).bottom > 0;
        return IgnorePointer(
          ignoring: hide,
          child: AnimatedScale(
            scale: hide ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            curve: hide ? Curves.easeInCubic : Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: hide ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Reveal(index: 4, dy: 30, child: RepaintBoundary(child: DictateButton(size: 66, onPressed: _newInvoice))),
            ),
          ),
        );
      }),
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: 140,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                name: AppState.instance.activeOrg?.name ?? profile?.businessName ?? '',
                currency: currency,
                total: m.total,
                count: m.count,
                drafts: m.drafts,
                draftsTotal: m.draftsTotal,
                loaded: _items != null,
                goal: _goal,
                series: dailySeries(_items ?? const <InvoiceRecord>[], currency: currency, today: todayIso()),
                onGoal: () => _setGoal(m.total),
              ),
            ),
            SliverToBoxAdapter(
              child: Reveal(
                index: 1,
                child: SizedBox(
                  height: 104,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
                    children: [
                      if (Access.instance.can('sell')) QuickAction(icon: Icons.mic_rounded, label: 'Facturar', colors: const [Color(0xFFFFA77F), Color(0xFFFF7E9A)], onTap: _newInvoice),
                      if (Access.instance.can('sell') && Access.instance.has('cotizaciones'))
                        QuickAction(icon: Icons.request_quote_rounded, label: 'Cotizar', colors: const [Color(0xFF8E7CF2), Color(0xFF6A62E2)], onTap: _quickQuote),
                      if (Access.instance.can('finance'))
                        QuickAction(icon: Icons.document_scanner_rounded, label: 'Escanear', colors: const [Color(0xFF5BC0EB), Color(0xFF3A86FF)], onTap: () => _push(const ScanScreen())),
                      if (Access.instance.can('finance')) QuickAction(icon: Icons.shopping_bag_rounded, label: 'Gasto', colors: const [Color(0xFFFFC56E), Color(0xFFFF9F43)], onTap: _quickExpense),
                      if (Access.instance.has('tienda'))
                        QuickAction(
                        icon: Icons.storefront_rounded,
                        label: 'Tienda',
                        badge: _storeOrders,
                        colors: const [Color(0xFF4FD1A1), Color(0xFF23956F)],
                        onTap: () {
                          // Con pedidos nuevos, lleva directo a atenderlos; si no, a configurar la tienda.
                          if (_storeOrders > 0 && widget.onNavigate != null) {
                            widget.onNavigate!(1);
                          } else {
                            _push(const StoreScreen());
                          }
                        },
                      ),
                      QuickAction(icon: Icons.groups_rounded, label: 'Clientes', colors: const [Color(0xFFF78FB3), Color(0xFFD94A8E)], onTap: () => _push(const Clients360Screen())),
                      if (Access.instance.has('recurrentes') && Access.instance.can('finance'))
                        QuickAction(
                        icon: Icons.event_repeat_rounded,
                        label: 'Mensuales',
                        badge: _recurringDrafts,
                        colors: const [Color(0xFFB58BF5), Color(0xFF8E5CF2)],
                        onTap: () => _push(const RecurringScreen()),
                      ),
                      QuickAction(icon: Icons.auto_awesome_rounded, label: 'Copiloto', colors: const [Color(0xFF26254B), Color(0xFF5048C8)], onTap: () => openCopilot(context)),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _CopilotCards(alerts: _alerts, onChanged: _load)),
            if (_items != null && _items!.isNotEmpty)
              SliverToBoxAdapter(
                child: _InsightsStrip(
                  insights: buildInsights(
                    invoices: _items!,
                    today: todayIso(),
                    currency: currency,
                    stock: _stock,
                    pendingClaims: _claims,
                    storeOrders: _storeOrders,
                    recurringDrafts: _recurringDrafts,
                  ),
                  onTap: _openInsight,
                ),
              ),
            if (_error != null && _items == null)
              SliverToBoxAdapter(child: _ErrorBox(message: _error!, onRetry: _load))
            else if (_items == null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                sliver: SliverList.separated(
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, _) => const SkeletonCard(),
                ),
              )
            else if (_items!.isEmpty)
              const SliverToBoxAdapter(
                child: Reveal(
                  child: EmptyState(
                    title: 'Tu primera factura está a una frase',
                    body: 'Toca el micrófono y di el cliente, el servicio y el importe. La revisas antes de guardarla.',
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Reveal(
                  index: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextField(
                        focusNode: _searchFocus,
                        onChanged: (v) => setState(() => _query = v),
                        onSubmitted: (_) => _searchFocus.unfocus(),
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Buscar por cliente o número',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final (k, label) in const [('all', 'Todas'), ('draft', 'Borradores'), ('issued', 'Emitidas'), ('due', 'Por cobrar'), ('review', 'Por revisar')])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: _filter == k,
                                onSelected: (_) => setState(() => _filter = k),
                              ),
                            ),
                        ]),
                      ),
                      if (_query.isEmpty && _filter == 'all' && _repeatable().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Repetir factura', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Un toque crea una copia de la última factura del cliente.', style: t.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final inv in _repeatable())
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  avatar: const Icon(Icons.replay_rounded, size: 18),
                                  label: Text(inv.clientName.length > 22 ? '${inv.clientName.substring(0, 22)}…' : inv.clientName),
                                  onPressed: () => _repeat(inv),
                                ),
                              ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
              Builder(builder: (context) {
                final list = _visible();
                if (list.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
                      child: Text('Nada coincide con tu búsqueda.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                  sliver: SliverList.separated(
                    itemCount: list.length + (_more ? 1 : 0),
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
                      child: RepaintBoundary(child: _Row(inv: list[i], onTap: () => _open(list[i]))),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Buenos días';
  if (h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: SoftCard(
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Brand.bad.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_rounded, color: Brand.bad),
          ),
          const SizedBox(height: 14),
          Text('No pudimos cargar tus comprobantes', textAlign: TextAlign.center, style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.currency,
    required this.total,
    required this.count,
    required this.drafts,
    required this.draftsTotal,
    required this.loaded,
    required this.goal,
    required this.series,
    required this.onGoal,
  });
  final String name;
  final String currency;
  final double total;
  final int count;
  final int drafts;
  final double draftsTotal;
  final bool loaded;
  final double? goal;
  final List<double> series;
  final VoidCallback onGoal;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sym = currencySymbols[currency] ?? currency;
    String fmt(double v) {
      final parts = v.toStringAsFixed(2).split('.');
      return '${parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}.${parts[1]}';
    }

    final g = goal == null || goal! <= 0 ? null : goalProgress(goal: goal!, sales: total, today: todayIso());
    final white85 = Colors.white.withValues(alpha: 0.85);
    return Aurora(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, top + 12, 24, 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Reveal(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting(), style: TextStyle(fontFamily: 'Inter', color: white85, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(
                    name.isEmpty ? 'FacturaVoz' : name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                  ),
                ]),
              ),
              Pressable(
                onTap: () => openCopilot(context),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 19),
                    SizedBox(width: 6),
                    Text('Copiloto', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              const SearchButton(onDark: true),
              const SizedBox(width: 8),
              const AvatarButton(onDark: true),
            ]),
          ),
          const SizedBox(height: 22),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Reveal(
                  index: 1,
                  child: Text('Vendido este mes (con IGV)', style: TextStyle(fontFamily: 'Inter', color: white85, fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 4),
                if (!loaded)
                  const SizedBox(height: 56)
                else
                  Reveal(
                    index: 2,
                    child: CountUp(
                      value: total,
                      builder: (context, v) {
                        final f = fmt(v).split('.');
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '$sym ', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                              TextSpan(text: f[0], style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1.6)),
                              TextSpan(text: '.${f[1]}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75))),
                            ]),
                            style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        );
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Reveal(
              index: 3,
              child: Semantics(
                button: true,
                label: g == null ? 'Fijar meta del mes' : 'Meta del mes al ${(g.percent * 100).round()} por ciento',
                child: Pressable(
                  onTap: onGoal,
                  child: g == null
                      ? Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 2)),
                          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.flag_rounded, color: Colors.white, size: 22),
                            Text('Fijar meta', style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                          ]),
                        )
                      : ProgressRing(
                          value: g.percent,
                          size: 78,
                          stroke: 8,
                          color: Colors.white,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(g.reached ? '🎉' : '${(g.percent * 100).round()}%',
                                style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                            Text('de la meta', style: TextStyle(fontFamily: 'Inter', color: white85, fontSize: 9.5)),
                          ]),
                        ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (loaded)
            Reveal(
              index: 3,
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                _HeaderPill(count == 0 ? 'Aún sin ventas emitidas este mes' : (count == 1 ? '1 venta emitida' : '$count ventas emitidas')),
                if (drafts > 0) _HeaderPill('$drafts ${drafts == 1 ? 'borrador' : 'borradores'} sin emitir · ${money(draftsTotal, currency)}'),
                if (g != null && !g.reached)
                  _HeaderPill(g.onTrack ? 'Vas bien · cierras en ${money(g.projected, currency)}' : 'Te faltan ${money(g.neededPerDay, currency)}/día'),
                if (g != null && g.reached) const _HeaderPill('¡Meta cumplida!'),
              ]),
            ),
          if (loaded && series.any((v) => v > 0)) ...[
            const SizedBox(height: 14),
            Reveal(
              index: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Últimos 14 días', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
                const SizedBox(height: 4),
                Sparkline(values: series, height: 44),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.inv, required this.onTap});
  final InvoiceRecord inv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fiscal = inv.fiscalStatus;
    final label = fiscal == null ? statusLabel(inv.status) : fiscalStatusLabel(fiscal);
    final tone = fiscal == null ? (inv.status == 'paid' ? PillTone.ok : PillTone.neutral) : StatusPill.toneForFiscal(fiscal);
    final overdue = inv.isOverdue(todayIso());
    final partial = inv.receivable && inv.paid > 0;
    final initial = inv.clientName.trim().isEmpty || inv.clientName == '—' ? '·' : inv.clientName.trim().characters.first.toUpperCase();
    return Pressable(
      onTap: onTap,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Hero(
            tag: 'avatar-${inv.id}',
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Text(initial, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: t.colorScheme.primary)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('${inv.fiscalNumber ?? inv.number}  ·  ${displayDate(inv.issueDate)}', style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusPill(label, tone: tone),
                if (overdue) const StatusPill('Vencida', tone: PillTone.bad) else if (partial) StatusPill('Saldo ${money(inv.balance, inv.currency)}', tone: PillTone.warn),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          Money(money(inv.totals.total, inv.currency), size: 16, weight: FontWeight.w700),
        ]),
      ),
    );
  }
}


/// Avisos del día: lo que conviene hacer hoy (cobrar, confirmar pagos, reponer stock…).
class _InsightsStrip extends StatelessWidget {
  const _InsightsStrip({required this.insights, required this.onTap});
  final List<Insight> insights;
  final ValueChanged<Insight> onTap;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    return Reveal(
      index: 2,
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: insights.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _InsightCard(insight: insights[i], onTap: () => onTap(insights[i])),
          ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.onTap});
  final Insight insight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (Color c, IconData icon) = switch (insight.kind) {
      'claims' => (Brand.indigo, Icons.notifications_active_rounded),
      'overdue' => (Brand.bad, Icons.warning_amber_rounded),
      'due_soon' => (Brand.warn, Icons.schedule_rounded),
      'pace' => (insight.tone == 'ok' ? Brand.ok : Brand.warn, insight.tone == 'ok' ? Icons.trending_up_rounded : Icons.trending_down_rounded),
      'stock' => (Brand.goldDeep, Icons.inventory_2_rounded),
      'store_orders' => (Brand.ok, Icons.storefront_rounded),
      'recurring' => (Brand.lilac, Icons.event_repeat_rounded),
      _ => (Brand.indigo, Icons.lightbulb_rounded),
    };
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.withValues(alpha: 0.25)),
          boxShadow: Brand.softShadow(t.brightness == Brightness.dark, a: 0.06),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(insight.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(insight.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}


/// Copiloto 2.0 proactivo: tarjetas con lo que conviene hacer HOY (visitas, fiados vencidos, cumpleaños) y el
/// resumen ejecutivo hablado de 30 segundos. Todo viene de daily_alerts (RLS: cada rol ve lo suyo).
class _CopilotCards extends StatelessWidget {
  const _CopilotCards({required this.alerts, required this.onChanged});
  final List<DailyAlert> alerts;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final org = AppState.instance.activeOrg?.name ?? 'tu negocio';
    final cards = <Widget>[
      if (a.has('copiloto'))
        _card(
          context,
          icon: Icons.record_voice_over_rounded,
          color: Brand.indigo,
          title: 'Tu resumen en 30 segundos',
          body: 'Ventas, quién te debe, gastos, impuestos y qué hacer hoy. Te lo leo en voz alta.',
          action: 'Escuchar',
          onTap: () => openCopilot(context, ask: 'Dame mi resumen ejecutivo de hoy en 30 segundos: ventas, por cobrar, gastos, impuestos a guardar y una acción para hoy.'),
        ),
      for (final x in alerts.take(4))
        (switch (x.kind) {
          'visit_today' || 'visit_tomorrow' => _card(
              context,
              icon: Icons.event_available_rounded,
              color: Brand.lilac,
              title: '${x.kind == 'visit_today' ? 'Hoy' : 'Mañana'}: ${x.title}',
              body: x.client.isEmpty ? 'Visita o cita agendada' : 'Con ${x.client}',
              action: 'Ver',
              onTap: () {
                final id = x.data['job_id'] as String?;
                if (id != null) pushPremium(context, JobDetailScreen(jobId: id)).then((_) => onChanged());
              },
            ),
          'fiado_due' => _card(
              context,
              icon: Icons.menu_book_rounded,
              color: Brand.bad,
              title: 'Fiado vencido: ${x.client}',
              body: 'Recuérdale con un mensaje amable por WhatsApp.',
              action: 'Escribir',
              onTap: () => openWhatsApp(context, x.phone, 'Hola ${x.client.split(' ').first}, te saluda $org. Te recordamos tu cuenta pendiente. ¡Gracias!'),
            ),
          'birthday' => _card(
              context,
              icon: Icons.cake_rounded,
              color: Brand.goldDeep,
              title: '¡${x.client} cumple años!',
              body: 'Un saludo hoy fideliza más que un descuento.',
              action: 'Saludar',
              onTap: () => openWhatsApp(context, x.phone, '¡Feliz cumpleaños, ${x.client.split(' ').first}! 🎂 Te saluda $org.'),
            ),
          'job_late' => _card(
              context,
              icon: Icons.running_with_errors_rounded,
              color: Brand.bad,
              title: 'Atrasado: ${x.title}',
              body: x.client,
              action: 'Ver',
              onTap: () {
                final id = x.data['job_id'] as String?;
                if (id != null) pushPremium(context, JobDetailScreen(jobId: id)).then((_) => onChanged());
              },
            ),
          _ => _card(
              context,
              icon: Icons.person_search_rounded,
              color: Brand.warn,
              title: '${x.client}: hace ${x.data['days'] ?? 'tiempo'} días no compra',
              body: 'Escríbele: un mensaje a tiempo recupera clientes.',
              action: 'Escribir',
              onTap: () => openWhatsApp(context, x.phone, 'Hola ${x.client.split(' ').first}, te saluda $org. ¡Hace tiempo no te vemos! ¿Te ayudamos con algo?'),
            ),
        }),
      if (a.can('finance') && a.has('reportes'))
        _card(
          context,
          icon: Icons.savings_rounded,
          color: Brand.ok,
          title: '¿Cuánto me queda?',
          body: 'Lo que debes guardar para SUNAT y tu ganancia real del mes.',
          action: 'Ver',
          onTap: () {
            final f = featureById('impuestos');
            if (f != null) openFeature(context, f);
          },
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Reveal(
      index: 2,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 18, color: Brand.indigo),
              const SizedBox(width: 6),
              Text('Tu copiloto te sugiere', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => cards[i],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, {required IconData icon, required Color color, required String title, required String body, required String action, required VoidCallback onTap}) {
    final t = Theme.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: Brand.softShadow(t.brightness == Brightness.dark, a: 0.06),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Expanded(child: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall)),
          Align(alignment: Alignment.centerRight, child: Text(action, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: color))),
        ]),
      ),
    );
  }
}
