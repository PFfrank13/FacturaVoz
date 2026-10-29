// Pestaña CLIENTES (Fase 1 y 7): recordatorios inteligentes del día + lista de clientes con búsqueda y gestos
// (desliza a la derecha = Facturar, a la izquierda = WhatsApp) + accesos a Trabajos y Agenda.
import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'catalog.dart';
import 'client_profile.dart';
import 'fiados.dart';
import 'invoice_detail.dart';
import 'jobs.dart';
import 'new_invoice.dart';

class ClientsHubScreen extends StatefulWidget {
  const ClientsHubScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<ClientsHubScreen> createState() => _ClientsHubScreenState();
}

class _ClientsHubScreenState extends State<ClientsHubScreen> {
  List<ClientProfile>? _clients;
  List<DailyAlert> _alerts = const [];
  String? _error;
  String _q = '';
  final _debounce = Debouncer(500);
  String? _orgSeen;

  @override
  void initState() {
    super.initState();
    _orgSeen = AppState.instance.activeOrg?.id;
    AppState.instance.addListener(_onApp);
    AppState.instance.dataVersion.addListener(_soon);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onApp);
    AppState.instance.dataVersion.removeListener(_soon);
    _debounce.dispose();
    super.dispose();
  }

  void _onApp() {
    if (_orgSeen != AppState.instance.activeOrg?.id) {
      _orgSeen = AppState.instance.activeOrg?.id;
      setState(() => _clients = null);
      _load();
    }
  }

  void _soon() => _debounce(() {
        if (mounted) _load();
      });

  Future<void> _load() async {
    try {
      final list = await V2Repo.clients();
      final alerts = await V2Repo.dailyAlerts();
      if (mounted) {
        setState(() {
          _clients = list;
          _alerts = alerts;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _new() async {
    final id = await showClientForm(context);
    if (id != null && mounted) {
      await pushPremium(context, ClientProfileScreen(clientId: id));
      _load();
    }
  }

  Future<void> _open(ClientProfile c) async {
    await pushPremium(context, ClientProfileScreen(clientId: c.id));
    _load();
  }

  Future<void> _invoice(ClientProfile c) async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewInvoiceScreen(initial: draftFor(c))));
    AppState.instance.bump();
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
    }
  }

  void _alertTap(DailyAlert a) {
    final jobId = a.data['job_id'] as String?;
    final clientId = a.data['client_id'] as String?;
    if (jobId != null) {
      pushPremium(context, JobDetailScreen(jobId: jobId)).then((_) => _load());
    } else if (a.kind == 'fiado_due' && clientId != null) {
      showFiadoSheet(context, clientId: clientId, clientName: a.client, kind: 'abono').then((ok) {
        if (ok) _load();
      });
    } else if (clientId != null) {
      pushPremium(context, ClientProfileScreen(clientId: clientId)).then((_) => _load());
    }
  }

  void _alertWhatsApp(DailyAlert a) {
    final org = AppState.instance.activeOrg?.name ?? 'nuestro negocio';
    final first = a.client.split(' ').first;
    final text = switch (a.kind) {
      'birthday' => '¡Feliz cumpleaños, $first! 🎂 Te saluda $org. Gracias por tu preferencia.',
      'no_contact' => 'Hola $first, te saluda $org. ¡Hace tiempo no te vemos! ¿Te podemos ayudar con algo?',
      'fiado_due' => 'Hola $first, te saluda $org. Te recordamos tu saldo pendiente${a.data['amount'] != null ? ' de ${money((a.data['amount'] as num).toDouble(), AppState.instance.profile?.currency ?? 'PEN')}' : ''}. ¡Gracias!',
      'visit_today' || 'visit_tomorrow' => 'Hola $first, te escribe $org para confirmar la visita${a.at != null ? ' del ${shortDateTime(a.at!)}' : ''}. ¿Te viene bien?',
      _ => 'Hola $first, te saluda $org.',
    };
    openWhatsApp(context, a.phone, text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final q = _q.trim().toLowerCase();
    final list = (_clients ?? const <ClientProfile>[])
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.taxId.contains(q) || c.phone.replaceAll(' ', '').contains(q) || c.tags.any((x) => x.toLowerCase().contains(q)))
        .toList();
    final a = Access.instance;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Clientes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, widget.embedded ? top + 14 : 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.embedded)
                  Reveal(
                    child: Row(children: [
                      Expanded(child: Text('Clientes', style: t.textTheme.headlineMedium)),
                      const SearchButton(),
                      const SizedBox(width: 8),
                      const AvatarButton(),
                    ]),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(hintText: 'Nombre, DNI/RUC, celular o etiqueta', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(tooltip: 'Nuevo cliente', onPressed: _new, icon: const Icon(Icons.person_add_alt_1_rounded)),
                ]),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(child: FeatureStrip(ids: const ['trabajos', 'agenda', 'fiados', 'encuestas', 'clientes360'])),
          if (_alerts.isNotEmpty && q.isEmpty) ...[
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 0), child: SectionTitle('Para hoy'))),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _alerts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => Reveal(index: i < 6 ? i : 6, child: _alertCard(context, _alerts[i])),
                ),
              ),
            ),
          ],
          if (_error != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          else if (_clients == null)
            const SliverPadding(padding: EdgeInsets.all(16), sliver: SliverToBoxAdapter(child: SkeletonList(count: 6)))
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: q.isEmpty
                  ? const EmptyState(title: 'Tus clientes aparecerán aquí', body: 'Se guardan solos cuando les facturas. También puedes agregarlos con el botón +.')
                  : Padding(padding: const EdgeInsets.all(32), child: Text('Nadie coincide con "$_q".', textAlign: TextAlign.center)),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text('${list.length} ${list.length == 1 ? 'cliente' : 'clientes'} · desliza para facturar o escribir', style: t.textTheme.bodySmall),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 170),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final c = list[i];
                  return Reveal(
                    key: ValueKey(c.id),
                    index: i < 10 ? i : 10,
                    child: SwipeActions(
                      left: a.can('sell') ? SwipeAction(icon: Icons.receipt_long_rounded, label: 'Facturar', color: Brand.goldDeep, onTrigger: () => _invoice(c)) : null,
                      right: c.phone.isEmpty
                          ? null
                          : SwipeAction(
                              icon: Icons.chat_rounded,
                              label: 'WhatsApp',
                              color: const Color(0xFF1FA855),
                              onTrigger: () => openWhatsApp(context, c.phone, 'Hola ${c.name.split(' ').first}, te saluda ${AppState.instance.activeOrg?.name ?? ''}.'),
                            ),
                      child: RepaintBoundary(child: _row(context, c)),
                    ),
                  );
                },
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, ClientProfile c) {
    final t = Theme.of(context);
    final initial = c.name.trim().isEmpty ? '·' : c.name.trim().characters.first.toUpperCase();
    return Pressable(
      onTap: () => _open(c),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Text(initial, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: t.colorScheme.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
              Text([c.taxId, c.phone, c.district].where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
              if (c.tags.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final tag in c.tags.take(3)) TagChip(tag, color: Brand.lilac)]),
              ],
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  Widget _alertCard(BuildContext context, DailyAlert a) {
    final t = Theme.of(context);
    final (IconData icon, Color color, String title) = switch (a.kind) {
      'visit_today' => (Icons.event_available_rounded, Brand.indigo, 'Hoy${a.at != null ? ' ${shortDateTime(a.at!).split(' ').last}' : ''}: ${a.title}'),
      'visit_tomorrow' => (Icons.event_rounded, Brand.lilac, 'Mañana: ${a.title}'),
      'job_late' => (Icons.running_with_errors_rounded, Brand.bad, 'Atrasado: ${a.title}'),
      'no_contact' => (Icons.person_search_rounded, Brand.warn, 'Hace ${a.data['days']} días no compra'),
      'birthday' => (Icons.cake_rounded, Brand.goldDeep, '¡Hoy cumple años!'),
      'fiado_due' => (Icons.menu_book_rounded, Brand.bad, 'Fiado vencido'),
      _ => (Icons.notifications_rounded, Brand.indigo, a.title),
    };
    return Pressable(
      onTap: () => _alertTap(a),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: t.colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.28))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(a.client, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
          const Spacer(),
          if (a.phone.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _alertWhatsApp(a),
                icon: const Icon(Icons.chat_rounded, size: 16),
                label: const Text('Escribir'),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Atajo para abrir la ficha desde otros lados por id (p. ej., resultados de búsqueda).
Future<void> openClient(BuildContext context, String id) => pushPremium(context, ClientProfileScreen(clientId: id));
