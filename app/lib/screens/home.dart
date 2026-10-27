import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../errors.dart';
import '../finance.dart';
import '../models.dart';
import '../models_pro.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'assistant.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'products.dart';
import 'settings.dart';

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
    final c = await ProRepo.countPendingClaims();
    if (mounted && c != _claims) setState(() => _claims = c);
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

  /// Total del mes en la moneda del negocio. Excluye comprobantes rechazados por SUNAT.
  ({double total, int count}) _month(String currency) {
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    var total = 0.0;
    var count = 0;
    for (final i in _items ?? const <InvoiceRecord>[]) {
      if (!i.issueDate.startsWith(prefix) || i.currency != currency || i.fiscalStatus == 'rejected') continue;
      total += i.totals.total;
      count++;
    }
    return (total: round2(total), count: count);
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
          cacheExtent: 600,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(name: AppState.instance.activeOrg?.name ?? profile?.businessName ?? '', currency: currency, total: m.total, count: m.count, loaded: _items != null),
            ),
            if (_items != null && _items!.isNotEmpty)
              SliverToBoxAdapter(
                child: _InsightsStrip(
                  insights: buildInsights(invoices: _items!, today: todayIso(), currency: currency, stock: _stock, pendingClaims: _claims),
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
  const _Header({required this.name, required this.currency, required this.total, required this.count, required this.loaded});
  final String name;
  final String currency;
  final double total;
  final int count;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sym = currencySymbols[currency] ?? currency;
    String fmt(double v) {
      final parts = v.toStringAsFixed(2).split('.');
      return '${parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}.${parts[1]}';
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(24, top + 12, 24, 34),
      decoration: const BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Stack(children: [
        Positioned(right: -70, top: -50, child: _Orb(size: 190, alpha: 0.10)),
        Positioned(right: 40, bottom: -90, child: _Orb(size: 150, alpha: 0.08)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Reveal(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting(), style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.8), fontSize: 13.5)),
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
              Pressable(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          Reveal(
            index: 1,
            child: Text('Facturado este mes',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 6),
          if (!loaded)
            const SizedBox(height: 62)
          else
            Reveal(
              index: 2,
              child: CountUp(
                value: total,
                builder: (context, v) {
                  final f = fmt(v).split('.');
                  return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text(sym, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: f[0], style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w700, letterSpacing: -1.8)),
                            TextSpan(text: '.${f[1]}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75))),
                          ]),
                          style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          const SizedBox(height: 12),
          if (loaded)
            Reveal(
              index: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
                child: Text(
                  count == 0 ? 'Aún sin comprobantes este mes' : (count == 1 ? '1 comprobante' : '$count comprobantes'),
                  style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
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
