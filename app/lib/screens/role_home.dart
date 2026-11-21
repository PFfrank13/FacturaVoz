// Inicio por rol (Prompt Maestro §6 y §12). Lo arma el motor rubro × plan × rol (nav/role_matrix.dart):
// cada bloque existe solo si el rol tiene el permiso y el plan la función. Los indicadores leen datos reales
// (day_summary, credit_balances, productos) con estado de carga, error y "Reintentar"; nunca cifras inventadas.
// Cada bloque lleva a su ruta canónica del catálogo (una función = una pantalla).
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../models.dart';
import '../logic/data_scope.dart';
import '../models_v2.dart';
import '../nav/role_matrix.dart';
import '../permissions.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/ds.dart';
import '../ui/theme.dart';
import '../ui/retail_home_premium.dart';
import 'catalog.dart';
import 'menu.dart';
import '../ui/motion.dart' show pushPremium, showSuccess;

/// Bloques que muestran una cifra (el resto son accesos).
const _statBlocks = {'today_sales', 'cash_status', 'fiados_total', 'stock_low'};

class RoleHomePanel extends StatefulWidget {
  const RoleHomePanel({super.key, this.exclude = const {}, this.showLinks = true});

  /// Bloques que la pantalla ya muestra de otra forma (p. ej. el botón principal).
  final Set<String> exclude;

  /// Oculta los enlaces duplicados cuando Inicio muestra el tablero especializado del rubro.
  final bool showLinks;

  @override
  State<RoleHomePanel> createState() => _RoleHomePanelState();
}

class _RoleHomePanelState extends State<RoleHomePanel> {
  DaySummary? _day;
  Map<String, dynamic>? _closing;
  List<CreditBalance>? _credit;
  int? _low;
  final _errors = <String>{};
  String? _org;
  int _gen = 0;
  int _pending = 0;

  RoleExperience _experience(Access a) {
    final role = roleForUser(a.rubro, a.role);
    return roleExperience(rubro: a.rubro ?? '', role: role, allows: a.allows, has: a.has);
  }

  @override
  void initState() {
    super.initState();
    dataScope.addListener(_onScopeChanged);
    _load();
  }

  @override
  void dispose() {
    dataScope.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (!mounted) return;
    setState(_clear); // nada de la empresa anterior queda en pantalla
    _load();
  }

  void _clear() {
    _day = null;
    _closing = null;
    _credit = null;
    _low = null;
    _errors.clear();
    _pending = 0;
  }

  @override
  void didUpdateWidget(covariant RoleHomePanel old) {
    super.didUpdateWidget(old);
    if (_org != Repo.activeOrgId) _onScopeChanged();
  }

  static String? _uid() => Supabase.instance.client.auth.currentUser?.id;

  Future<void> _load() async {
    // §9: cada respuesta se aplica SOLO si sigue siendo la misma empresa, el mismo usuario y la misma generación.
    final ticket = ScopeTicket(dataScope.value, Repo.activeOrgId, _uid());
    final gen = ++_gen;
    bool current() => mounted && gen == _gen && ticket.matches(dataScope.value, Repo.activeOrgId, _uid());
    if (_org != ticket.org) _clear();
    _org = ticket.org;
    final blocks = _experience(Access.instance).home.toSet();
    final today = todayIso();
    _errors.clear();
    Future<void> guard(String key, Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {
        if (current()) setState(() => _errors.add(key));
      }
    }

    await Future.wait([
      guard('pending', () async {
        final n = (await Repo.pendingFinancial()).length;
        if (current()) setState(() => _pending = n);
      }),
      if (blocks.contains('today_sales') || blocks.contains('cash_status'))
        guard('day', () async {
          final d = await V2Repo.daySummary(today);
          final c = blocks.contains('cash_status') ? await V2Repo.dayClosing(today) : null;
          if (current()) setState(() { _day = d; _closing = c; });
        }),
      if (blocks.contains('fiados_total'))
        guard('credit', () async {
          final c = await V2Repo.creditBalances();
          if (current()) setState(() => _credit = c);
        }),
      if (blocks.contains('stock_low'))
        guard('stock', () async {
          final p = await Repo.listProducts(activeOnly: true);
          if (current()) setState(() => _low = p.where((x) => x.lowStock).length);
        }),
    ]);
  }

  Future<void> _resolvePending() async {
    final scope = dataScope.value;
    final done = await Repo.resolvePendingFinancial();
    if (!mounted || scope != dataScope.value) return;
    showSuccess(context, done == 0 ? 'Aún sin conexión: siguen pendientes de confirmar.' : '$done operación(es) confirmada(s), sin duplicar.');
    _load();
  }

  void _open(String? route) {
    if (route == null) return;
    final f = featureById(route) ?? (route == 'pos' ? featureById('facturar') : null);
    if (f != null && f.allowed) openFeature(context, f).then((_) { if (mounted) _load(); });
  }

  String _money(double v) => money(v, _day?.currency ?? AppState.instance.profile?.currency ?? 'PEN');

  Widget _metric({
    required String label,
    required String value,
    String? detail,
    required IconData icon,
    Color? tone,
    VoidCallback? onTap,
    required Color accent,
  }) {
    if (Access.instance.rubro == 'bodega') {
      return RetailHomeStat(
        label: label, value: value, detail: detail,
        icon: icon, tint: accent, tone: tone, onTap: onTap,
      );
    }
    return DsStat(
      label: label, value: value, detail: detail,
      icon: icon, tone: tone, onTap: onTap,
    );
  }

  Widget? _stat(String id) {
    final b = homeBlocks[id]!;
    Widget err() => _metric(accent: RetailAccent.amber, label: b.label, value: '—', detail: 'No se pudo cargar · toca para reintentar', tone: DsColors.of(context).bad, icon: Icons.refresh_rounded, onTap: _load);
    switch (id) {
      case 'today_sales':
        if (_errors.contains('day')) return err();
        final d = _day;
        return _metric(accent: RetailAccent.blue, label: b.label, value: d == null ? '…' : _money(d.salesTotal), detail: d == null ? null : '${d.salesCount} ventas', icon: Icons.trending_up_rounded, onTap: () => _open(b.route));
      case 'cash_status':
        if (_errors.contains('day')) return err();
        final d = _day;
        final closed = _closing != null;
        // Arqueo ciego (cash_day.dart): antes del cierre NO se muestra el efectivo esperado, solo el estado.
        final opened = (d?.opening ?? 0) > 0;
        return _metric(
          accent: RetailAccent.amber,
          label: b.label,
          value: d == null ? '…' : closed ? 'Cerrada' : opened ? 'Abierta' : 'Sin abrir',
          detail: d == null ? null : closed ? 'Cierre de hoy registrado' : opened ? 'Cierra con arqueo al final del día' : 'Toca para abrir la caja',
          tone: closed ? DsColors.of(context).ok : opened ? null : DsColors.of(context).warn,
          icon: Icons.point_of_sale_rounded,
          onTap: () => _open(b.route),
        );
      case 'fiados_total':
        if (_errors.contains('credit')) return err();
        final c = _credit;
        final owing = c?.where((x) => x.balance > 0.004).toList();
        final total = owing?.fold<double>(0, (s, x) => s + x.balance);
        return _metric(
          accent: RetailAccent.violet,
          label: b.label,
          value: total == null ? '…' : _money(total),
          detail: owing == null ? null : owing.length == 1 ? '1 cliente' : '${owing.length} clientes',
          tone: (total ?? 0) > 0 ? DsColors.of(context).warn : null,
          icon: Icons.menu_book_rounded,
          onTap: () => _open(b.route),
        );
      case 'stock_low':
        if (_errors.contains('stock')) return err();
        return _metric(
          accent: RetailAccent.mint,
          label: b.label,
          value: _low == null ? '…' : '$_low',
          detail: _low == null ? null : _low == 0 ? 'Todo en orden' : 'productos por reponer',
          tone: (_low ?? 0) > 0 ? DsColors.of(context).warn : DsColors.of(context).ok,
          icon: Icons.inventory_2_rounded,
          onTap: () => _open(b.route),
        );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Access.instance,
      builder: (context, _) {
        final a = Access.instance;
        final exp = _experience(a);
        final ids = [for (final id in exp.home) if (!widget.exclude.contains(id)) id];
        final stats = [for (final id in ids) if (_statBlocks.contains(id)) ?_stat(id)];
        final links = [
          for (final id in ids)
            if (!_statBlocks.contains(id))
              if (homeBlocks[id] case final b? when b.route != null && (featureById(b.route!)?.allowed ?? b.route == 'pos'))
                b,
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_pending > 0) ...[
              const SizedBox(height: Gap.md),
              Material(
                color: DsColors.of(context).surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: DsColors.of(context).warn)),
                child: DsRow(
                  title: '$_pending operación(es) pendiente(s) de confirmar',
                  subtitle: 'Cobros o movimientos enviados sin respuesta. No los repitas: comprueba aquí.',
                  leading: Icons.sync_problem_rounded,
                  trailing: TextButton(onPressed: _resolvePending, child: const Text('Comprobar')),
                ),
              ),
            ],
            if (stats.isNotEmpty) ...[
              const DsSection('Hoy'),
              if (a.rubro == 'bodega')
                RetailHomeStatGrid(children: stats)
              else
                DsStatGrid(children: stats),
            ],
            if (widget.showLinks) ...[
              DsSection('Tu trabajo · ${roleForUser(a.rubro, a.role).label}'),
              Material(
              color: DsColors.of(context).surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: DsColors.of(context).line)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final b in links) DsRow(title: _linkTitle(b), leading: _icon(b.id), onTap: () => _open(b.route)),
                DsRow(title: 'Todas mis funciones', leading: Icons.apps_rounded, onTap: () => pushPremium(context, const MenuScreen())),
              ]),
              ),
            ],
          ]),
        );
      },
    );
  }

  String _linkTitle(HomeBlock b) => b.id == 'sell_cta' ? 'Nueva venta' : b.label;

  IconData _icon(String id) => switch (id) {
        'sell_cta' => Icons.point_of_sale_rounded,
        'last_ops' => Icons.receipt_long_rounded,
        'margin' => Icons.insights_rounded,
        'purchases' => Icons.local_shipping_rounded,
        'team' => Icons.groups_rounded,
        'reports' => Icons.table_view_rounded,
        'my_jobs' || 'all_jobs' => Icons.assignment_rounded,
        'agenda_today' => Icons.calendar_month_rounded,
        'tables' => Icons.table_restaurant_rounded,
        'collect_due' => Icons.account_balance_wallet_rounded,
        'orders' => Icons.request_quote_rounded,
        'pensions_due' => Icons.school_rounded,
        'works_margin' => Icons.engineering_rounded,
        'my_commissions' => Icons.emoji_events_rounded,
        'clients' => Icons.people_alt_rounded,
        _ => Icons.chevron_right_rounded,
      };
}
