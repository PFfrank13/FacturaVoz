import 'package:flutter/material.dart';

import 'catalog.dart' show AvatarButton, FeatureStrip;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../whatsapp.dart';
import 'invoice_detail.dart';
import 'pay_settings.dart';
import 'scan.dart';

/// Cobranza: cuánto te deben, quién paga tarde, pagos reportados por confirmar y recordatorios con un toque.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  List<InvoiceRecord>? _items;
  Map<String, ClientPayStats> _stats = const {};
  List<PaymentClaim> _claims = const [];
  Map<String, String> _reminded = const {};
  PaySettings? _settings;
  String? _error;
  String? _orgSeen;
  RealtimeChannel? _chan;
  final _debounce = Debouncer(500);
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _orgSeen = Repo.activeOrgId;
    AppState.instance.addListener(_onApp);
    AppState.instance.dataVersion.addListener(_reload);
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
    _debounce.dispose();
    AppState.instance.removeListener(_onApp);
    AppState.instance.dataVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _debounce(() {
        if (mounted) _load();
      });

  void _onApp() {
    if (_orgSeen != Repo.activeOrgId) {
      _orgSeen = Repo.activeOrgId;
      setState(() => _items = null);
      _load();
      _subscribe();
    }
  }

  /// En vivo: un cliente reporta un pago desde su enlace → aparece aquí al instante.
  void _subscribe() {
    _chan?.unsubscribe();
    _chan = null;
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      PostgresChangeFilter f() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: org);
      _chan = Supabase.instance.client
          .channel('collections-$org')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'payment_claims',
            filter: f(),
            callback: (_) {
              Haptics.warning();
              _reload();
            },
          )
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'payments', filter: f(), callback: (_) => _reload())
          .subscribe();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final items = await ProRepo.listReceivables();
      Map<String, ClientPayStats> stats = const {};
      List<PaymentClaim> claims = const [];
      PaySettings? settings;
      Map<String, String> reminded = const {};
      try {
        stats = await ProRepo.clientStats();
        claims = await ProRepo.listClaims();
        settings = await ProRepo.loadPaySettings();
        reminded = await ProRepo.lastReminders(items.map((i) => i.id));
      } catch (e) {
        if (!ProRepo.isMissingMigration(e)) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _stats = stats;
        _claims = claims;
        _settings = settings;
        _reminded = reminded;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _resolve(PaymentClaim c, bool accept) async {
    setState(() => _busy.add(c.id));
    try {
      await ProRepo.resolveClaim(c.id, accept);
      AppState.instance.bump();
      if (!mounted) return;
      if (accept) {
        showSuccess(context, 'Cobro registrado');
      } else {
        _snack('Pago reportado descartado');
      }
      await _load();
    } catch (e) {
      _snack(friendly(e));
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  Future<void> _remind(InvoiceRecord inv) async {
    setState(() => _busy.add(inv.id));
    try {
      String link = '';
      try {
        link = await ProRepo.payLinkUrl(inv.id);
      } catch (_) {}
      final profile = AppState.instance.profile;
      final msg = reminderText(
        clientName: inv.clientName,
        businessName: AppState.instance.activeOrg?.name ?? profile?.businessName ?? '',
        number: inv.fiscalNumber ?? inv.number,
        currency: inv.currency,
        total: inv.totals.total,
        balance: inv.balance,
        dueDate: inv.dueDate,
        today: todayIso(),
      );
      final text = link.isEmpty ? msg : '$msg\nPuedes pagar aquí (Yape, Plin, transferencia o tarjeta): $link';
      final ok = await launchUrl(Uri.https('wa.me', '/', {'text': text}), mode: LaunchMode.externalApplication);
      if (ok) {
        await ProRepo.logWhatsAppReminder(inv, todayIso());
        Haptics.success();
        await _load();
      } else {
        _snack('No se pudo abrir WhatsApp.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(inv.id));
    }
  }

  Future<void> _reconcile() async {
    final items = _items ?? const <InvoiceRecord>[];
    if (items.isEmpty) {
      _snack('No tienes facturas por cobrar.');
      return;
    }
    final done = await reconcileFromPhoto(context, items);
    if (done) {
      AppState.instance.bump();
      await _load();
    }
  }

  Future<void> _openSettings() async {
    await pushPremium(context, const PaySettingsScreen());
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final today = todayIso();
    final items = [...?_items]
      ..sort((a, b) {
        final ao = a.isOverdue(today), bo = b.isOverdue(today);
        if (ao != bo) return ao ? -1 : 1;
        return (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999');
      });
    final aging = agingOf(items.where((i) => i.currency == cur), today);
    final top = MediaQuery.paddingOf(context).top;
    final week = forecastCash(receivables: items.where((i) => i.currency == cur), stats: _stats, dailyExpense: 0, today: today, weeks: 4);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Cobranza'), actions: [IconButton(onPressed: _openSettings, icon: const Icon(Icons.tune_rounded))]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, widget.embedded ? top + 18 : 8, 16, 190),
          children: [
            if (widget.embedded)
              Reveal(
                child: Row(children: [
                  Expanded(child: Text('Cobrar y pagar', style: t.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton.filledTonal(onPressed: _openSettings, icon: const Icon(Icons.tune_rounded), tooltip: 'Medios de cobro y recordatorios'),
                  const SizedBox(width: 6),
                  const AvatarButton(),
                ]),
              ),
            // v2.0: todo lo de cobrar y pagar a un toque (solo lo que el plan y el rol permiten).
            if (widget.embedded) ...[
              const SizedBox(height: 12),
              const FeatureStrip(ids: ['fiados', 'caja', 'avisos', 'banco', 'gastos', 'escanear']),
            ],
            const SizedBox(height: 12),
            if (_error != null)
              SoftCard(child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Reintentar'))]))
            else if (_items == null)
              const SkeletonList(count: 4)
            else ...[
              Reveal(index: 1, child: _summary(context, aging, cur, week)),
              const SizedBox(height: 12),
              Reveal(index: 2, child: _autoBanner(context)),
              if (_claims.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionTitle('Pagos reportados por tus clientes (${_claims.length})'),
                for (final (i, c) in _claims.indexed) Reveal(key: ValueKey(c.id), index: 3 + i, child: _claimCard(context, c)),
              ],
              const SizedBox(height: 14),
              Reveal(
                index: 3,
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reconcile,
                      icon: const Icon(Icons.document_scanner_rounded),
                      label: const Text('Conciliar captura de pago'),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              SectionTitle(items.isEmpty ? 'Por cobrar' : 'Por cobrar (${items.length})'),
              if (items.isEmpty)
                const EmptyState(title: '¡Nadie te debe!', body: 'Cuando vendas al crédito, aquí verás quién te debe, cuándo pagará y le recordarás con un toque.')
              else
                for (final (i, inv) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Reveal(key: ValueKey(inv.id), index: 4 + (i < 8 ? i : 8), child: _row(context, inv, today)),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, Aging aging, String cur, CashForecast f) {
    const colors = [Color(0xFF9B8CF5), Color(0xFFFFB454), Color(0xFFFF9376), Color(0xFFFF6F8E), Color(0xFFD94A5E)];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(28), boxShadow: Brand.softShadow(false, a: 0.25)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Te deben', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
        const SizedBox(height: 4),
        CountUp(
          value: aging.total,
          builder: (c, v) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(v, cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          aging.overdue > 0 ? '${money(aging.overdue, cur)} ya vencidos' : 'Nada vencido. ¡Bien!',
          style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SegmentBar(values: aging.values, colors: colors, height: 10),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (var i = 0; i < 5; i++)
            if (aging.values[i] > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${Aging.labels[i]} ${money(aging.values[i], cur)}', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontSize: 11.5)),
              ]),
        ]),
        if (f.weeks.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Según cómo paga cada cliente, esperas cobrar ${money(f.weeks.first.inflow, cur)} esta semana y ${money(f.totalIn, cur)} en 4 semanas.',
                  style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 12.5, height: 1.35),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _autoBanner(BuildContext context) {
    final t = Theme.of(context);
    final s = _settings;
    final on = s?.remindersEnabled == true;
    final offsets = (s?.offsets ?? const <int>[]).map((d) => d == 0 ? 'día 0' : (d < 0 ? '$d' : '+$d')).join(' · ');
    return Pressable(
      onTap: _openSettings,
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          on ? const PulseDot() : Icon(Icons.notifications_off_outlined, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(on ? 'Cobranza automática activa' : 'Activa la cobranza automática', style: t.textTheme.titleSmall),
              Text(
                on ? 'Recordatorios por correo con enlace de pago: $offsets días del vencimiento.' : 'Recordamos a tus clientes por correo, antes y después del vencimiento, sin que hagas nada.',
                style: t.textTheme.bodySmall,
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  Widget _claimCard(BuildContext context, PaymentClaim c) {
    final t = Theme.of(context);
    final busy = _busy.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Brand.indigo.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.payments_rounded, color: Brand.indigo),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.clientName.isEmpty ? 'Cliente' : c.clientName, style: t.textTheme.titleSmall),
                Text(
                  '${paymentMethods[c.method] ?? c.method} · ${c.invoiceNumber}${c.operationCode.isEmpty ? '' : ' · op. ${c.operationCode}'}',
                  style: t.textTheme.bodySmall,
                ),
              ]),
            ),
            Money(money(c.amount, c.currency), size: 16, weight: FontWeight.w700),
          ]),
          const SizedBox(height: 10),
          Text('Verifica en tu app de Yape/Plin o en tu banco antes de confirmar.', style: t.textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: busy ? null : () => _resolve(c, false), child: const Text('No llegó'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : () => _resolve(c, true),
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                label: const Text('Confirmar'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, InvoiceRecord inv, String today) {
    final t = Theme.of(context);
    final stats = _stats[clientKey(inv.clientName)];
    final score = scoreClient(stats);
    final overdue = inv.isOverdue(today);
    final days = inv.dueDate == null ? null : daysBetween(today, inv.dueDate!);
    final when = days == null
        ? 'Sin fecha de vencimiento'
        : (days < 0 ? 'Vencida hace ${-days} ${days == -1 ? 'día' : 'días'}' : (days == 0 ? 'Vence hoy' : 'Vence en $days ${days == 1 ? 'día' : 'días'}'));
    final expected = expectedPayDate(inv, stats, today);
    final reminded = _reminded[inv.id];
    final busy = _busy.contains(inv.id);
    final gc = switch (score.grade) {
      Grade.a => Brand.ok,
      Grade.b => Brand.indigo,
      Grade.c => Brand.warn,
      Grade.d => Brand.bad,
      Grade.unknown => t.colorScheme.onSurfaceVariant,
    };
    return Pressable(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id)));
        if (mounted) _load();
      },
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Tooltip(
              message: '${score.label}. ${score.advice}',
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                child: Text(score.letter, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: gc)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                Text('${inv.fiscalNumber ?? inv.number} · ${score.label}', style: t.textTheme.bodySmall),
              ]),
            ),
            Money(money(inv.balance, inv.currency), size: 16, weight: FontWeight.w700, color: overdue ? Brand.bad : null),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusPill(when, tone: overdue ? PillTone.bad : (days != null && days <= 3 ? PillTone.warn : PillTone.neutral)),
            StatusPill('Pago probable ${dayMonth(expected)}', tone: PillTone.info),
            if (reminded != null) StatusPill('Recordado ${dayMonth(reminded)}', tone: PillTone.neutral),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => _remind(inv),
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chat_rounded),
                label: const Text('Recordar por WhatsApp'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
