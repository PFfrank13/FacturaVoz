import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../models_pro.dart';
import '../services/live.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'share_sheet.dart';

PillTone _toneFor(String status) => switch (status) {
      'accepted' => PillTone.ok,
      'converted' => PillTone.info,
      'rejected' => PillTone.bad,
      'sent' => PillTone.warn,
      _ => PillTone.neutral,
    };

/// Cotizaciones: crear por voz, enviar enlace al cliente, ver en vivo si acepta y convertir en factura con un toque.
class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  List<QuoteRecord>? _items;
  String? _error;
  String _filter = 'open';
  RealtimeChannel? _chan;
  String? _orgSeen;
  final _debounce = Debouncer(400);

  @override
  void initState() {
    super.initState();
    _orgSeen = Repo.activeOrgId;
    AppState.instance.addListener(_onApp);
    _items = LiveCache.get<List<QuoteRecord>>('quotes.all');
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
    _debounce.dispose();
    AppState.instance.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    if (_orgSeen != Repo.activeOrgId) {
      _orgSeen = Repo.activeOrgId;
      setState(() => _items = null);
      _load();
      _subscribe();
    }
  }

  /// En vivo: si el cliente acepta desde el enlace, la app lo celebra al instante.
  void _subscribe() {
    _chan?.unsubscribe();
    _chan = null;
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      _chan = Supabase.instance.client
          .channel('quotes-$org')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'quotes',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: org),
            callback: (p) {
              final n = p.newRecord;
              final before = _items?.where((q) => q.id == n['id']).firstOrNull;
              if (mounted && n['status'] == 'accepted' && before != null && before.status != 'accepted') {
                showSuccess(context, '¡${before.clientName} aceptó ${before.number}!', icon: Icons.celebration_rounded);
              }
              // Pedido nuevo desde la tienda en línea
              if (mounted && p.eventType == PostgresChangeEvent.insert && n['source'] == 'store') {
                showSuccess(context, '🛍️ Nuevo pedido web ${n['number'] ?? ''}', icon: Icons.storefront_rounded);
                if (_filter != 'store') setState(() => _filter = 'store');
              }
              _debounce(() {
                if (mounted) _load();
              });
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final r = await ProRepo.listQuotes();
      LiveCache.put('quotes.all', r);
      if (mounted) {
        setState(() {
          _items = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261101_negocio_pro.sql en Supabase.' : friendly(e));
      }
    }
  }

  Future<void> _new() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewInvoiceScreen(quote: true)));
    await _load();
    if (id != null && mounted) {
      showSuccess(context, 'Cotización creada');
      await _open(id, share: true);
    }
  }

  Future<void> _open(String id, {bool share = false}) async {
    await pushPremium(context, QuoteDetailScreen(quoteId: id, shareOnOpen: share));
    if (mounted) _load();
  }

  List<QuoteRecord> _visible() {
    final today = todayIso();
    return (_items ?? const <QuoteRecord>[]).where((q) => switch (_filter) {
          'open' => (q.status == 'draft' || q.status == 'sent') && !q.isExpired(today),
          'store' => q.fromStore && q.status != 'converted' && q.status != 'rejected',
          'accepted' => q.status == 'accepted',
          'converted' => q.status == 'converted',
          'closed' => q.status == 'rejected' || q.isExpired(today),
          _ => true,
        }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final all = _items ?? const <QuoteRecord>[];
    final open = all.where((q) => q.status == 'draft' || q.status == 'sent' || q.status == 'accepted').toList();
    final pipeline = round2(open.where((q) => q.currency == cur).fold<double>(0, (s, q) => s + q.totals.total));
    final decided = all.where((q) => q.status == 'accepted' || q.status == 'converted' || q.status == 'rejected').length;
    final won = all.where((q) => q.status == 'accepted' || q.status == 'converted').length;
    final rate = decided == 0 ? null : (won / decided * 100).round();
    final top = MediaQuery.paddingOf(context).top;
    final list = _visible();
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Cotizaciones')),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: widget.embedded ? 96 : 0),
        child: FloatingActionButton.extended(
          heroTag: 'new-quote',
          onPressed: _new,
          icon: const Icon(Icons.mic_rounded),
          label: const Text('Nueva cotización'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, widget.embedded ? top + 18 : 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.embedded) Reveal(child: Text('Cotizaciones', style: t.textTheme.headlineMedium)),
                const SizedBox(height: 14),
                Reveal(
                  index: 1,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(26), boxShadow: Brand.softShadow(false, a: 0.25)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('En negociación', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                          const SizedBox(height: 4),
                          CountUp(
                            value: pipeline,
                            builder: (c, v) => FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(money(v, cur), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('${open.length} ${open.length == 1 ? 'cotización abierta' : 'cotizaciones abiertas'}',
                              style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                        ]),
                      ),
                      ProgressRing(
                        value: (rate ?? 0) / 100,
                        size: 74,
                        stroke: 8,
                        color: Colors.white,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(rate == null ? '—' : '$rate%', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                          Text('cierre', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5)),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (k, label) in const [
                      ('open', 'Pendientes'),
                      ('store', 'Pedidos web'),
                      ('accepted', 'Aceptadas'),
                      ('converted', 'Facturadas'),
                      ('closed', 'Rechazadas o vencidas'),
                      ('all', 'Todas'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == k,
                          onSelected: (_) {
                            Haptics.select();
                            setState(() => _filter = k);
                          },
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SoftCard(
                  child: Column(children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
                  ]),
                ),
              ),
            )
          else if (_items == null)
            const SliverPadding(padding: EdgeInsets.all(16), sliver: SliverToBoxAdapter(child: SkeletonList(count: 4)))
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                title: all.isEmpty ? 'Cotiza en 10 segundos' : 'Nada por aquí',
                body: all.isEmpty
                    ? 'Dicta "Cotización para Corpax: 3 sillas a 150". Envíale el enlace y, si acepta, la conviertes en factura con un toque.'
                    : 'Prueba con otro filtro.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 190),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => Reveal(
                  key: ValueKey(list[i].id),
                  index: i < 8 ? i : 8,
                  child: _QuoteRow(q: list[i], onTap: () => _open(list[i].id)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.q, required this.onTap});
  final QuoteRecord q;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final expired = q.isExpired(todayIso());
    return Pressable(
      onTap: onTap,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Hero(
            tag: 'quote-${q.id}',
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.request_quote_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('${q.number}  ·  ${displayDate(q.issueDate)}', style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                expired ? const StatusPill('Vencida', tone: PillTone.bad) : StatusPill(quoteStatusLabel(q.status), tone: _toneFor(q.status)),
                if (q.status == 'accepted') const StatusPill('Lista para facturar', tone: PillTone.info),
                if (q.fromStore) const TagChip('Pedido web', color: Brand.ok, icon: Icons.storefront_rounded),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          Money(money(q.totals.total, q.currency), size: 16, weight: FontWeight.w700),
        ]),
      ),
    );
  }
}

/// Detalle de una cotización con su acción principal según el estado.
class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quoteId, this.shareOnOpen = false});
  final String quoteId;
  final bool shareOnOpen;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  QuoteRecord? _q;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.shareOnOpen && mounted && _q != null) _share();
    });
  }

  Future<void> _load() async {
    try {
      final q = await ProRepo.getQuote(widget.quoteId);
      if (mounted) setState(() => _q = q);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _share() async {
    final q = _q!;
    final business = AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? '';
    final shared = await shareLinkSheet(
      context,
      title: 'Enviar cotización',
      subtitle: 'Tu cliente la verá en su celular y podrá aceptarla con un toque. Te avisamos al instante.',
      url: ProRepo.quoteUrl(q.publicToken),
      message: 'Hola ${q.clientName == '—' ? '' : q.clientName}, te comparto la cotización ${q.number} de $business por ${money(q.totals.total, q.currency)}. Puedes revisarla y aceptarla aquí:',
    );
    if (shared && q.status == 'draft') {
      try {
        await ProRepo.setQuoteStatus(q.id, 'sent');
        await _load();
      } catch (_) {}
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await ProRepo.setQuoteStatus(widget.quoteId, status);
      await _load();
      if (status == 'accepted' && mounted) showSuccess(context, 'Marcada como aceptada');
    } catch (e) {
      _snack(friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// La magia: un toque y la cotización es una factura (borrador) lista para emitir a SUNAT.
  Future<void> _convert() async {
    final q = _q!;
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Convertir en factura', style: t.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Se crea con el mismo cliente, líneas e impuesto. Solo elige la condición de pago.', style: t.textTheme.bodySmall),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (d, l) in const [(0, 'Al contado'), (7, 'Crédito 7 días'), (15, 'Crédito 15 días'), (30, 'Crédito 30 días')])
                  ActionChip(label: Text(l), onPressed: () => Navigator.pop(ctx, d)),
              ]),
            ]),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final due = choice == 0 ? null : todayIso(DateTime.now().add(Duration(days: choice)));
      final invoiceId = await ProRepo.convertQuote(q.id, dueDate: due);
      AppState.instance.bump();
      if (!mounted) return;
      showSuccess(context, '¡Listo! Ya es factura', icon: Icons.auto_awesome_rounded);
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId)));
    } catch (e) {
      _snack('No se pudo convertir. ${friendly(e)}');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicate() async {
    final q = _q!;
    final p = AppState.instance.profile;
    if (p == null) return;
    await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => NewInvoiceScreen(
        quote: true,
        initial: InvoiceDraft(
          clientName: q.clientName == '—' ? '' : q.clientName,
          clientTaxId: q.clientTaxId,
          taxRate: q.taxRate,
          currency: q.currency,
          notes: q.notes,
          items: q.items.map((i) => LineItem(description: i.description, quantity: i.quantity, unitPrice: i.unitPrice)).toList(),
        ),
      ),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: const Text('No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProRepo.deleteQuote(widget.quoteId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(q?.number ?? 'Cotización'),
        actions: [
          if (q != null)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'accepted' => _setStatus('accepted'),
                'rejected' => _setStatus('rejected'),
                'dup' => _duplicate(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => [
                if (q.status == 'draft' || q.status == 'sent') const PopupMenuItem(value: 'accepted', child: Text('Marcar como aceptada')),
                if (q.status == 'draft' || q.status == 'sent') const PopupMenuItem(value: 'rejected', child: Text('Marcar como rechazada')),
                const PopupMenuItem(value: 'dup', child: Text('Duplicar como nueva')),
                if (q.status == 'draft' || q.status == 'rejected') const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: q == null
            ? Center(
                child: _error == null
                    ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3))
                    : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
              )
            : ListView(padding: const EdgeInsets.all(16), children: [
                Reveal(
                  child: TicketPaper(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Hero(
                          tag: 'quote-${q.id}',
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(15)),
                            child: const Icon(Icons.request_quote_rounded, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Cotización', style: t.textTheme.bodySmall),
                            Text(q.number, style: t.textTheme.headlineSmall),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        q.isExpired(todayIso()) ? const StatusPill('Vencida', tone: PillTone.bad) : StatusPill(quoteStatusLabel(q.status), tone: _toneFor(q.status)),
                        if (q.validUntil != null) StatusPill('Válida hasta ${displayDate(q.validUntil!)}', tone: PillTone.neutral),
                      ]),
                      if (q.responderName.isNotEmpty || q.responseNote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.md)),
                          child: Text(
                            '${q.status == 'rejected' ? 'Rechazada' : 'Aceptada'} por ${q.responderName.isEmpty ? 'el cliente' : q.responderName}'
                            '${q.responseNote.isEmpty ? '' : ': “${q.responseNote}”'}',
                            style: t.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(q.clientName, style: t.textTheme.titleMedium),
                      if (q.clientTaxId.isNotEmpty) Text(q.clientTaxId, style: t.textTheme.bodySmall),
                      Text(displayDate(q.issueDate), style: t.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      const Divider(),
                      for (final i in q.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(i.description, style: t.textTheme.bodyMedium),
                                Text('${qtyText(i.quantity)} × ${money(i.unitPrice, q.currency)}', style: t.textTheme.bodySmall),
                              ]),
                            ),
                            Money(money(i.amount, q.currency), size: 14.5),
                          ]),
                        ),
                      const Divider(),
                      DataRow2('Subtotal', money(q.totals.subtotal, q.currency)),
                      DataRow2('IGV (${qtyText(q.taxRate)}%)', money(q.totals.tax, q.currency)),
                      DataRow2('Total', money(q.totals.total, q.currency), strong: true),
                      if (q.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(q.notes, style: t.textTheme.bodySmall)),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                if (q.fromStore && q.contactPhone.isNotEmpty) ...[
                  Reveal(
                    index: 1,
                    child: SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        const Icon(Icons.storefront_rounded, color: Brand.ok),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Pedido desde tu tienda · cel. ${q.contactPhone}', style: t.textTheme.titleSmall)),
                        FilledButton.tonalIcon(
                          onPressed: () => launchUrl(
                            Uri.https('wa.me', '/51${q.contactPhone}', {
                              'text': 'Hola ${q.clientName}, recibimos tu pedido ${q.number} por ${money(q.totals.total, q.currency)}. ¡Ya lo estamos preparando!',
                            }),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('Confirmar'),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (q.status == 'converted' && q.invoiceId != null)
                  GradientButton(
                    label: 'Ver factura',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: q.invoiceId!))),
                  )
                else if (q.status == 'accepted')
                  Reveal(index: 2, child: GradientButton(label: 'Convertir en factura', icon: Icons.auto_awesome_rounded, busy: _busy, onPressed: _busy ? null : _convert))
                else if (q.status != 'rejected') ...[
                  Reveal(index: 2, child: GradientButton(label: q.status == 'draft' ? 'Enviar al cliente' : 'Reenviar enlace', icon: Icons.send_rounded, onPressed: _busy ? null : _share)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: _busy ? null : _convert, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Convertir en factura ya')),
                ] else
                  OutlinedButton.icon(onPressed: _duplicate, icon: const Icon(Icons.copy_all_rounded), label: const Text('Duplicar como nueva')),
                if (q.status == 'accepted') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.link_rounded), label: const Text('Ver enlace del cliente')),
                ],
              ]),
      ),
    );
  }
}
