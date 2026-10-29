// Inicio limpio (E): saludo, resumen del día (cifras del servidor, nunca a medias), meta del mes, 1–2 sugerencias del
// Copiloto y 3–4 accesos de TU rubro. El botón fijo "Menú" es la única puerta a todas las funciones.
// La lista de comprobantes que antes vivía aquí sigue completa en Menú → Comprobantes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../models.dart';
import '../models_v2.dart';
import '../rubros.dart';
import '../services/growth_repo.dart';
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'goal_sheet.dart';
import 'home.dart' show CopilotCards;
import 'hubs_v3.dart' show showNewSaleSheet;
import 'menu.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _month;
  bool _tried = false;
  double? _goal;
  List<DailyAlert> _alerts = const [];
  RealtimeChannel? _chan;
  Timer? _debounce;
  String? _org;

  @override
  void initState() {
    super.initState();
    _org = Repo.activeOrgId;
    _load();
    _subscribe();
    AppState.instance.dataVersion.addListener(_live);
    AppState.instance.addListener(_onApp);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _chan?.unsubscribe();
    AppState.instance.dataVersion.removeListener(_live);
    AppState.instance.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    if (_org == Repo.activeOrgId) return;
    _org = Repo.activeOrgId;
    setState(() {
      _today = null;
      _month = null;
      _tried = false;
    });
    _load();
    _subscribe();
  }

  void _subscribe() {
    _chan?.unsubscribe();
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      PostgresChangeFilter f() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: org);
      _chan = Supabase.instance.client
          .channel('inicio-$org')
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'invoices', filter: f(), callback: (_) => _live())
          .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'payments', filter: f(), callback: (_) => _live())
          .subscribe();
    } catch (_) {}
  }

  // Varias ventas seguidas = una sola recarga (A3: debounce).
  void _live() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final now = DateTime.now();
    final today = todayIso(now);
    final tomorrow = todayIso(now.add(const Duration(days: 1)));
    final first = todayIso(DateTime(now.year, now.month, 1));
    final next = todayIso(DateTime(now.year, now.month + 1, 1));
    final seeMoney = Access.instance.can('finance') || Access.instance.can('collect');
    // Todo en paralelo y agregado en la base: dos números, no miles de filas.
    final results = await Future.wait<Object?>([
      seeMoney ? V2Repo.salesSummary(today, tomorrow, cur) : Future.value(null),
      seeMoney ? V2Repo.salesSummary(first, next, cur) : Future.value(null),
      GrowthRepo.monthlyGoal().catchError((Object _) => null),
      V2Repo.dailyAlerts().catchError((Object _) => const <DailyAlert>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _today = results[0] as Map<String, dynamic>?;
      _month = results[1] as Map<String, dynamic>?;
      _goal = results[2] as double?;
      _alerts = (results[3] as List<DailyAlert>?) ?? const [];
      _tried = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = Access.instance;
    final spec = rubroFor(a.rubro);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final name = a.displayName.isNotEmpty ? a.displayName.split(' ').first : '';
    final hour = DateTime.now().hour;
    final hello = hour < 12 ? 'Buenos días' : (hour < 19 ? 'Buenas tardes' : 'Buenas noches');
    final seeMoney = a.can('finance') || a.can('collect');
    final todayTotal = ((_today?['sales_total'] as num?) ?? 0).toDouble();
    final todayCount = ((_today?['sales_count'] as num?) ?? 0).toInt();
    final monthTotal = ((_month?['sales_total'] as num?) ?? 0).toDouble();
    final shortcuts = [for (final id in spec?.home ?? const ['facturar', 'clientes', 'cobranza', 'negocio']) if (featureById(id) case final f? when f.roleOk) f];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 64,
            titleSpacing: 20,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? hello : '$hello, $name', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(AppState.instance.activeOrg?.name ?? '', style: t.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              // Botón fijo "Menú": la única puerta a todas las funciones (con búsqueda por texto y voz).
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton.tonalIcon(
                  onPressed: () => pushPremium(context, const MenuScreen()),
                  icon: const Icon(Icons.menu_rounded),
                  label: const Text('Menú'),
                ),
              ),
              const AvatarButton(),
              const SizedBox(width: 12),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
            sliver: SliverList.list(children: [
              if (seeMoney)
                Reveal(
                  child: !_tried
                      ? const SkeletonCard() // esqueleto: nunca se muestra una cifra intermedia
                      : SoftCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Hoy', style: t.textTheme.labelLarge),
                            const SizedBox(height: 4),
                            _today == null
                                ? const Text('No pude traer tus ventas. Desliza hacia abajo para reintentar.')
                                : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Expanded(child: Money(money(todayTotal, cur), size: 30, weight: FontWeight.w800)),
                                    Text(todayCount == 1 ? '1 venta' : '$todayCount ventas', style: t.textTheme.bodyMedium),
                                  ]),
                            const SizedBox(height: 10),
                            if (_month != null) ...[
                              Row(children: [
                                Expanded(child: Text('Este mes: ${money(monthTotal, cur)}', style: t.textTheme.bodyMedium)),
                                TextButton(
                                  onPressed: a.isAdmin
                                      ? () async {
                                          final v = await showGoalSheet(context, current: _goal, salesSoFar: monthTotal);
                                          if (v != null && mounted) setState(() => _goal = v <= 0 ? null : v);
                                        }
                                      : null,
                                  child: Text(_goal == null ? 'Fijar meta' : 'Meta ${money(_goal!, cur)}'),
                                ),
                              ]),
                              if (_goal != null && _goal! > 0)
                                LinearProgressIndicator(value: (monthTotal / _goal!).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(8)),
                            ],
                            const SizedBox(height: 6),
                            Text('Con IGV, sin anulados, menos notas de crédito. Es la misma cifra en Mi negocio y en el Copiloto.', style: t.textTheme.bodySmall),
                          ]),
                        ),
                ),
              const SizedBox(height: 12),
              if (a.can('sell'))
                GradientButton(label: 'Nueva venta', icon: Icons.add_shopping_cart_rounded, onPressed: () => showNewSaleSheet(context)),
              CopilotCards(alerts: _alerts, onChanged: _load, max: AppState.instance.easyMode.value ? 1 : 2),
              const SizedBox(height: 16),
              if (shortcuts.isNotEmpty) ...[
                SectionTitle(spec == null ? 'Accesos' : 'Lo de tu ${spec.name.split(' ').first.toLowerCase()}'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: AppState.instance.easyMode.value ? 1.6 : 2.1,
                  children: [
                    for (final f in shortcuts.take(4))
                      Pressable(
                        onTap: f.planOk ? () => openFeature(context, f) : () => pushPremium(context, const MenuScreen()),
                        child: SoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Icon(f.planOk ? f.icon : Icons.lock_rounded, color: f.id == spec?.signature ? Brand.warn : t.colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(child: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
