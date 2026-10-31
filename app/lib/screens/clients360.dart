import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../errors.dart';
import '../growth.dart';
import '../models.dart';
import '../services/growth_repo.dart';
import '../services/pro_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'new_invoice.dart';

Color segmentColor(Segment s) => switch (s) {
      Segment.vip => const Color(0xFFB8860B),
      Segment.loyal => Brand.ok,
      Segment.atRisk => Brand.warn,
      Segment.lost => Brand.bad,
      Segment.newcomer => Brand.indigo,
      Segment.occasional => const Color(0xFF8A8CAB),
    };

IconData segmentIcon(Segment s) => switch (s) {
      Segment.vip => Icons.workspace_premium_rounded,
      Segment.loyal => Icons.favorite_rounded,
      Segment.atRisk => Icons.trending_down_rounded,
      Segment.lost => Icons.heart_broken_rounded,
      Segment.newcomer => Icons.waving_hand_rounded,
      Segment.occasional => Icons.person_outline_rounded,
    };

/// Clientes 360: quién te compra más, quién se está yendo y cuánto dinero está en riesgo.
/// Un toque envía un mensaje cálido por WhatsApp o prepara una cotización para recuperarlo.
class Clients360Screen extends StatefulWidget {
  const Clients360Screen({super.key});

  @override
  State<Clients360Screen> createState() => _Clients360ScreenState();
}

class _Clients360ScreenState extends State<Clients360Screen> {
  List<ClientInsight>? _all;
  String? _error;
  Segment? _filter;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await GrowthRepo.clientActivity();
      if (!mounted) return;
      final list = segmentClients(rows, todayIso());
      setState(() {
        _all = list;
        _error = null;
        // La primera vez abre directo en lo urgente si hay clientes yéndose.
        if (_first) {
          _first = false;
          _filter = list.any((i) => i.segment == Segment.atRisk) ? Segment.atRisk : null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261102_revolucion.sql en Supabase.' : friendly(e));
    }
  }

  Future<void> _message(ClientInsight i) async {
    final business = AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? '';
    final ok = await launchUrl(Uri.https('wa.me', '/', {'text': clientMessage(i, business)}), mode: LaunchMode.externalApplication);
    if (ok) Haptics.success();
  }

  Future<void> _quote(ClientInsight i) async {
    final p = AppState.instance.profile;
    if (p == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NewInvoiceScreen(
        quote: true,
        initial: InvoiceDraft(clientName: i.activity.name, taxRate: p.taxRate ?? 18, currency: p.currency, items: [LineItem()]),
      ),
    ));
    AppState.instance.bump();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final all = _all;
    final counts = <Segment, int>{};
    for (final i in all ?? const <ClientInsight>[]) {
      counts[i.segment] = (counts[i.segment] ?? 0) + 1;
    }
    final atRisk = round2((all ?? const <ClientInsight>[]).fold<double>(0, (s, i) => s + i.atRiskValue));
    final vipShare = () {
      final list = all ?? const <ClientInsight>[];
      final total = list.fold<double>(0, (s, i) => s + i.activity.total);
      final vip = list.where((i) => i.segment == Segment.vip).fold<double>(0, (s, i) => s + i.activity.total);
      return total <= 0 ? 0.0 : vip / total;
    }();
    final visible = (all ?? const <ClientInsight>[]).where((i) => _filter == null || i.segment == _filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes 360')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (_error != null)
            SoftCard(child: Text(_error!, textAlign: TextAlign.center))
          else if (all == null)
            const SkeletonList(count: 5)
          else if (all.isEmpty)
            const EmptyState(title: 'Aún no hay historial', body: 'Cuando tengas ventas emitidas verás aquí a tus mejores clientes y a los que se están yendo.')
          else ...[
            Reveal(
              child: Aurora(
                borderRadius: BorderRadius.circular(Radii.xl),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Ventas en riesgo', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
                        const SizedBox(height: 4),
                        CountUp(
                          value: atRisk,
                          builder: (c, v) => FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(money(v, cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -1)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(counts[Segment.atRisk] ?? 0) + (counts[Segment.lost] ?? 0)} clientes dejaron de comprar a su ritmo de siempre',
                          style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5),
                        ),
                      ]),
                    ),
                    ProgressRing(
                      value: vipShare,
                      size: 78,
                      stroke: 8,
                      color: Colors.white,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${(vipShare * 100).round()}%', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('de VIP', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text('Todos (${all.length})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                ),
                for (final s in Segment.values)
                  if ((counts[s] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(segmentIcon(s), size: 16, color: segmentColor(s)),
                        label: Text('${segmentLabel(s)} (${counts[s]})'),
                        selected: _filter == s,
                        onSelected: (_) {
                          Haptics.select();
                          setState(() => _filter = s);
                        },
                      ),
                    ),
              ]),
            ),
            const SizedBox(height: 12),
            for (final (k, i) in visible.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Reveal(key: ValueKey(i.activity.key), index: k < 8 ? k : 8, child: _card(context, i, cur)),
              ),
            if (visible.isEmpty) Padding(padding: const EdgeInsets.only(top: 30), child: Text('Nadie en este grupo.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium)),
          ],
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, ClientInsight i, String cur) {
    final t = Theme.of(context);
    final c = segmentColor(i.segment);
    final a = i.activity;
    final urgent = i.segment == Segment.atRisk || i.segment == Segment.lost;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Text(a.name.trim().isEmpty ? '·' : a.name.trim().characters.first.toUpperCase(),
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: c)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
              const SizedBox(height: 3),
              TagChip(segmentLabel(i.segment), color: c, icon: segmentIcon(i.segment)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Money(money(a.total, cur), size: 15, weight: FontWeight.w700),
            Text('${a.purchases} ${a.purchases == 1 ? 'compra' : 'compras'}', style: t.textTheme.bodySmall),
          ]),
        ]),
        const SizedBox(height: 10),
        Text(i.reason, style: t.textTheme.bodySmall),
        Text('Ticket promedio ${money(a.avgTicket, cur)} · última compra ${displayDate(a.lastPurchase)}', style: t.textTheme.bodySmall),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: urgent
                ? FilledButton.icon(onPressed: () => _message(i), icon: const Icon(Icons.chat_rounded), label: const Text('Recuperarlo'))
                : FilledButton.tonalIcon(onPressed: () => _message(i), icon: const Icon(Icons.chat_rounded), label: const Text('Escribirle')),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(onPressed: () => _quote(i), tooltip: 'Cotizarle', icon: const Icon(Icons.request_quote_rounded)),
        ]),
      ]),
    );
  }
}
