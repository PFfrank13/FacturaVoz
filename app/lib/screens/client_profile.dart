// Ficha 360 del cliente (Fase 1): datos, mapa, deuda (facturas + fiados), puntaje de pago, historial, cotizaciones,
// trabajos, equipos instalados, notas y fotos. Botones grandes: Facturar · Cotizar · Cobrar · Agendar · WhatsApp.
// La edición se guarda SOLA (sin botón "guardar") y se puede deshacer desde la papelera.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access.dart';
import '../app_state.dart';
import '../business_templates.dart';
import '../errors.dart';
import '../logic/doc_voice.dart';
import '../logic/pay_score.dart';
import '../logic/regulars.dart';
import '../models.dart';
import '../models_pro.dart';
import '../models_v2.dart';
import '../services/location.dart';
import '../services/pro_repo.dart';
import '../services/v2_api.dart';
import '../services/v2_repo.dart';
import '../ui/mini_map.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../whatsapp.dart';
import 'fiados.dart';
import 'invoice_detail.dart';
import 'jobs.dart';
import 'new_invoice.dart';
import 'quotes.dart';
import 'trash.dart';

Future<void> openWhatsApp(BuildContext context, String phone, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  final n = normalizePhone(phone);
  if (n == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Agrega un celular válido al cliente (9 dígitos).')));
    return;
  }
  if (!await launchUrl(whatsappUri(n, text), mode: LaunchMode.externalApplication)) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
  }
}

InvoiceDraft draftFor(ClientProfile c) {
  final p = AppState.instance.profile;
  return InvoiceDraft(clientName: c.name, clientTaxId: c.taxId, taxRate: p?.taxRate ?? 18, currency: (p?.currency ?? '').isEmpty ? 'PEN' : p!.currency, items: [LineItem()]);
}

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key, required this.clientId});
  final String clientId;

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  ClientProfile? _c;
  String? _error;
  List<InvoiceRecord> _invoices = const [];
  List<Map<String, dynamic>> _quotes = const [];
  List<Job> _jobs = const [];
  List<ClientAsset> _assets = const [];
  List<ClientNote> _notes = const [];
  List<MediaFile> _media = const [];
  double _fiado = 0;
  ClientPayStats? _stats;
  String _tab = 'historial';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await V2Repo.client(widget.clientId);
      if (c == null) {
        if (mounted) setState(() => _error = 'Este cliente ya no existe (quizá está en la papelera).');
        return;
      }
      if (mounted) setState(() => _c = c);
      final a = Access.instance;
      final results = await Future.wait<Object?>([
        V2Repo.clientInvoices(c.id).catchError((_) => <InvoiceRecord>[]),
        V2Repo.clientQuotes(c.id).catchError((_) => <Map<String, dynamic>>[]),
        V2Repo.jobs(clientId: c.id, limit: 100).catchError((_) => <Job>[]),
        V2Repo.assets(c.id).catchError((_) => <ClientAsset>[]),
        V2Repo.notes(c.id).catchError((_) => <ClientNote>[]),
        V2Repo.media(clientId: c.id).catchError((_) => <MediaFile>[]),
        a.has('fiados') ? V2Repo.creditMoves(c.id).catchError((_) => <CreditMove>[]) : Future.value(<CreditMove>[]),
        a.can('finance') || a.can('collect') ? ProRepo.clientStats().catchError((_) => <String, ClientPayStats>{}) : Future.value(<String, ClientPayStats>{}),
      ]);
      if (!mounted) return;
      final moves = results[6] as List<CreditMove>;
      final stats = results[7] as Map<String, ClientPayStats>;
      setState(() {
        _invoices = results[0] as List<InvoiceRecord>;
        _quotes = results[1] as List<Map<String, dynamic>>;
        _jobs = results[2] as List<Job>;
        _assets = results[3] as List<ClientAsset>;
        _notes = results[4] as List<ClientNote>;
        _media = results[5] as List<MediaFile>;
        _fiado = moves.fold(0.0, (s, m) => s + (m.kind == 'abono' ? -m.amount : m.amount));
        _stats = stats[c.name.trim().toLowerCase()];
      });
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  double get _debt => _invoices.where((i) => i.receivable).fold(0.0, (s, i) => s + i.balance);

  Future<void> _invoice({bool quote = false}) async {
    final c = _c;
    if (c == null) return;
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewInvoiceScreen(quote: quote, initial: draftFor(c))));
    AppState.instance.bump();
    if (id != null && !quote && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
    }
    _load();
  }

  Future<void> _collect() async {
    final c = _c;
    if (c == null) return;
    final open = _invoices.where((i) => i.receivable).toList();
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
          ListTile(title: Text('Cobrar a ${c.name}', style: Theme.of(ctx).textTheme.titleLarge)),
          if (open.isEmpty && _fiado <= 0) const ListTile(leading: Icon(Icons.check_circle_rounded, color: Brand.ok), title: Text('No te debe nada. 🎉')),
          for (final i in open)
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded),
              title: Text('${i.fiscalNumber ?? i.number} · saldo ${money(i.balance, i.currency)}'),
              subtitle: Text(i.dueDate == null ? 'Emitida ${displayDate(i.issueDate)}' : 'Vence ${displayDate(i.dueDate!)}'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: i.id))).then((_) => _load());
              },
            ),
          if (Access.instance.has('fiados'))
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(_fiado > 0 ? 'Abono de fiado (debe ${money(_fiado, cur)})' : 'Anotar fiado o abono'),
              onTap: () async {
                Navigator.pop(ctx);
                if (await showFiadoSheet(context, clientId: c.id, clientName: c.name, kind: _fiado > 0 ? 'abono' : 'cargo')) _load();
              },
            ),
          if (c.phone.isNotEmpty && (open.isNotEmpty || _fiado > 0))
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: Brand.ok),
              title: const Text('Recordarle por WhatsApp'),
              onTap: () {
                Navigator.pop(ctx);
                final total = _debt + (_fiado > 0 ? _fiado : 0);
                openWhatsApp(context, c.phone,
                    'Hola ${c.name.split(' ').first}, te escribimos de ${AppState.instance.activeOrg?.name ?? 'nuestro negocio'}. Tienes un saldo pendiente de ${money(total, cur)}. ¿Te paso los datos para pagar por Yape o Plin? ¡Gracias!');
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _schedule() async {
    final c = _c;
    if (c == null) return;
    final id = await showJobForm(context, clientId: c.id, clientName: c.name, address: c.address);
    if (id != null) _load();
  }

  Future<void> _edit() async {
    final c = _c;
    if (c == null) return;
    await showClientForm(context, client: c);
    _load();
  }

  Future<void> _delete() async {
    final c = _c;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Mover a la papelera?'),
        content: Text('${c.name} se podrá recuperar durante 30 días desde Ajustes → Papelera.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    try {
      await V2Repo.deleteClient(c.id);
      if (!mounted) return;
      showUndo(context, rowId: c.id, label: 'Cliente movido a la papelera');
      nav.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo: tiene comprobantes asociados o no tienes permiso. ${friendly(e)}')));
    }
  }

  Future<void> _setLocation() async {
    final c = _c;
    if (c == null) return;
    final ctrl = TextEditingController();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ubicación del cliente', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'gps'), icon: const Icon(Icons.my_location_rounded), label: const Text('Estoy aquí: usar mi ubicación')),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'O pega un enlace de Google Maps', hintText: 'https://maps.google.com/…')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'link'), child: const Text('Usar el enlace')),
        ]),
      ),
    );
    final link = ctrl.text;
    disposeAfterClose([ctrl]);
    if (choice == null || !mounted) return;
    try {
      ({double lat, double lng})? p;
      if (choice == 'gps') {
        p = await currentLocation();
      } else {
        p = parseCoordinates(link);
        if (p == null) throw AppException('Ese enlace no tiene coordenadas. En Google Maps toca "Compartir" y pega el enlace completo, o escribe "-12.04, -77.03".');
      }
      c.lat = p.lat;
      c.lng = p.lng;
      await V2Repo.saveClient(c);
      if (mounted) {
        showSuccess(context, 'Ubicación guardada', icon: Icons.location_on_rounded);
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  Future<void> _addNote() async {
    final c = _c;
    if (c == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva nota'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 4, maxLength: 1000, decoration: const InputDecoration(hintText: 'Ej.: prefiere que lo llamen después de las 6 pm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    disposeAfterClose([ctrl]);
    if (ok != true || text.isEmpty) return;
    try {
      await V2Repo.addNote(c.id, text);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
  }

  Future<void> _addPhoto() async {
    final c = _c;
    if (c == null) return;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 72);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final path = await V2Repo.upload('clients/${c.id}', bytes);
      await V2Repo.addMedia(clientId: c.id, path: path);
      if (mounted) showSuccess(context, 'Foto guardada', icon: Icons.photo_camera_rounded);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
  }

  Future<void> _addAsset() async {
    final c = _c;
    if (c == null) return;
    final name = TextEditingController(), model = TextEditingController(), serial = TextEditingController(), warranty = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Equipo instalado'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Equipo (ej.: Router, Aire acondicionado)')),
            TextField(controller: model, decoration: const InputDecoration(labelText: 'Marca / modelo')),
            TextField(controller: serial, decoration: const InputDecoration(labelText: 'N.° de serie o MAC')),
            TextField(controller: warranty, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Garantía hasta (AAAA-MM-DD)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final n = name.text.trim(), m = model.text, sr = serial.text, w = warranty.text.trim();
    disposeAfterClose([name, model, serial, warranty]);
    if (ok != true || n.isEmpty) return;
    try {
      await V2Repo.addAsset(clientId: c.id, name: n, model: m, serial: sr, installedOn: todayIso(), warrantyUntil: RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(w) ? w : null);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = _c;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final a = Access.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del cliente'),
        actions: [
          if (c != null) IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_rounded)),
          if (c != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'del') _delete();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Mover a la papelera'))],
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : c == null
              ? const SkeletonList(count: 4)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    Reveal(child: _header(context, c)),
                    const SizedBox(height: 14),
                    Reveal(
                      index: 1,
                      child: Row(children: [
                        if (a.can('sell')) _action(context, Icons.receipt_long_rounded, 'Facturar', Brand.goldDeep, () => _invoice()),
                        if (a.can('sell') && a.has('cotizaciones')) _action(context, Icons.request_quote_rounded, 'Cotizar', Brand.indigo, () => _invoice(quote: true)),
                        if (a.can('collect')) _action(context, Icons.payments_rounded, 'Cobrar', Brand.ok, _collect),
                        if (a.has('agenda') || a.has('trabajos')) _action(context, Icons.event_available_rounded, 'Agendar', Brand.lilac, _schedule),
                        _action(context, Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366),
                            () => openWhatsApp(context, c.phone, 'Hola ${c.name.split(' ').first}, te saluda ${AppState.instance.activeOrg?.name ?? ''}.')),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (a.can('collect') || a.can('finance')) Reveal(index: 2, child: _money(context, cur)),
                    const SizedBox(height: 12),
                    Reveal(index: 3, child: _place(context, c)),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (k, label, n) in [
                          ('historial', 'Historial', _invoices.length),
                          ('cotizaciones', 'Cotizaciones', _quotes.length),
                          ('trabajos', 'Trabajos', _jobs.length),
                          ('equipos', 'Equipos', _assets.length),
                          ('notas', 'Notas', _notes.length),
                          ('fotos', 'Fotos', _media.length),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(label: Text(n == 0 ? label : '$label ($n)'), selected: _tab == k, onSelected: (_) => setState(() => _tab = k)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(duration: Motion.d(context, Motion.fast), child: KeyedSubtree(key: ValueKey(_tab), child: _tabBody(context, c, cur))),
                    if (c.notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Notas internas', style: t.textTheme.titleSmall),
                      Text(c.notes, style: t.textTheme.bodyMedium),
                    ],
                  ]),
                ),
    );
  }

  Widget _header(BuildContext context, ClientProfile c) {
    final initial = c.name.trim().isEmpty ? '·' : c.name.trim().characters.first.toUpperCase();
    final days = c.lastContactAt == null ? null : DateTime.now().difference(c.lastContactAt!).inDays;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
            child: Text(initial, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              if (c.taxId.isNotEmpty)
                Text('${docKind(c.taxId) == 'ruc' ? 'RUC' : (docKind(c.taxId) == 'dni' ? 'DNI' : 'Doc.')} ${c.taxId}', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.88))),
              if (c.phone.isNotEmpty) Text(c.phone, style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.88))),
            ]),
          ),
        ]),
        if (c.tags.isNotEmpty || c.source.isNotEmpty || days != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final tag in c.tags) _chip(tag),
            if (c.source.isNotEmpty) _chip('Vino por ${clientSources[c.source] ?? c.source}'),
            if (days != null) _chip(days == 0 ? 'Contacto hoy' : 'Último contacto hace $days d'),
            if (c.birthday != null) _chip('🎂 ${displayDate(c.birthday!).substring(0, 5)}'),
          ]),
        ],
      ]),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(Radii.pill)),
        child: Text(text, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _action(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    final t = Theme.of(context);
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.lg)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _money(BuildContext context, String cur) {
    final t = Theme.of(context);
    final st = _stats;
    final score = st == null
        ? const PayScore(null, 'Sin historial suficiente', 'neutral')
        : payScore(creditInvoices: st.creditInvoices, settled: st.settled, avgDaysLate: st.avgDaysLate, maxDaysLate: st.maxDaysLate, overdueBalance: st.overdueBalance);
    final scoreColor = switch (score.tone) { 'ok' => Brand.ok, 'warn' => Brand.warn, 'bad' => Brand.bad, _ => t.colorScheme.onSurfaceVariant };
    final bought = _invoices.where((i) => i.countsAsSale).fold(0.0, (s, i) => s + i.signedTotal);
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Te debe', style: t.textTheme.bodySmall),
            Money(money(_debt + (_fiado > 0 ? _fiado : 0), cur), size: 22, weight: FontWeight.w800, color: _debt + _fiado > 0 ? Brand.bad : Brand.ok),
            if (_fiado > 0) Text('incluye fiado ${money(_fiado, cur)}', style: t.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text('Te compró ${money(bought, cur)} en total', style: t.textTheme.bodySmall),
            Builder(builder: (_) {
              final r = classifyRegular(_invoices, today: todayIso(), rubro: Access.instance.rubro);
              if (r.tier == RegularTier.sinCompras) return const SizedBox.shrink();
              final star = r.tier == RegularTier.casero || r.tier == RegularTier.frecuente;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusPill('${star ? '⭐ ' : ''}${r.label}', tone: star ? PillTone.ok : PillTone.neutral),
                  Text('${r.purchases90} ${r.purchases90 == 1 ? 'compra' : 'compras'} en ${r.rules.windowDays} días', style: t.textTheme.bodySmall),
                  if (r.suggestedDiscountPct > 0) Text('· descuento sugerido ${r.suggestedDiscountPct.toStringAsFixed(0)} %', style: t.textTheme.bodySmall),
                ]),
              );
            }),
          ]),
        ),
        Column(children: [
          ProgressRing(
            value: (score.value ?? 0) / 100,
            size: 64,
            stroke: 7,
            color: scoreColor,
            child: Text(score.value?.toString() ?? '—', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: scoreColor)),
          ),
          const SizedBox(height: 4),
          SizedBox(width: 96, child: Text(score.label, textAlign: TextAlign.center, maxLines: 2, style: t.textTheme.labelSmall)),
        ]),
      ]),
    );
  }

  Widget _place(BuildContext context, ClientProfile c) {
    final t = Theme.of(context);
    final hasPoint = c.lat != null && c.lng != null;
    final address = [c.address, c.district].where((e) => e.trim().isNotEmpty).join(', ');
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasPoint) MiniMap(lat: c.lat!, lng: c.lng!),
        if (hasPoint) const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.place_rounded, color: Brand.bad),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(address.isEmpty ? 'Sin dirección' : address, style: t.textTheme.bodyMedium),
              if (c.reference.isNotEmpty) Text('Ref.: ${c.reference}', style: t.textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (hasPoint) FilledButton.tonalIcon(onPressed: () => openDirections(c.lat!, c.lng!), icon: const Icon(Icons.directions_rounded), label: const Text('Cómo llegar')),
          if (!hasPoint && address.isNotEmpty) FilledButton.tonalIcon(onPressed: () => openMapSearch(address), icon: const Icon(Icons.map_rounded), label: const Text('Ver en el mapa')),
          OutlinedButton.icon(onPressed: _setLocation, icon: const Icon(Icons.add_location_alt_rounded), label: Text(hasPoint ? 'Cambiar ubicación' : 'Guardar ubicación')),
        ]),
      ]),
    );
  }

  Widget _tabBody(BuildContext context, ClientProfile c, String cur) {
    final t = Theme.of(context);
    Widget empty(String text, {String? action, VoidCallback? onAction}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(children: [
            Text(text, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            if (action != null) TextButton(onPressed: onAction, child: Text(action)),
          ]),
        );
    switch (_tab) {
      case 'historial':
        if (_invoices.isEmpty) return empty('Aún no le vendiste nada.', action: Access.instance.can('sell') ? 'Facturar ahora' : null, onAction: () => _invoice());
        return Column(children: [
          for (final i in _invoices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_rounded),
              title: Text('${switch (i.docKind) { 'factura' => 'Factura', 'boleta' => 'Boleta', 'nota_credito' => 'Nota de crédito', 'nota_venta' => 'Nota de venta', _ => 'Comprobante' }} ${i.fiscalNumber ?? i.number}'),
              subtitle: Text(
                '${displayDate(i.issueDate)}${i.receivable ? ' · saldo ${money(i.balance, i.currency)}' : ''}'
                '${i.items.isEmpty ? '' : '\n${i.items.first.description}${i.items.length > 1 ? ' y ${i.items.length - 1} más' : ''}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Money(money(i.totals.total, i.currency), weight: FontWeight.w700),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: i.id))).then((_) => _load()),
            ),
        ]);
      case 'cotizaciones':
        if (_quotes.isEmpty) return empty('Sin cotizaciones.', action: Access.instance.can('sell') ? 'Cotizar' : null, onAction: () => _invoice(quote: true));
        return Column(children: [
          for (final q in _quotes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.request_quote_rounded),
              title: Text('${q['number'] ?? ''}'),
              subtitle: Text('${displayDate('${q['issue_date'] ?? ''}')} · ${q['status'] ?? ''}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: q['id'] as String))).then((_) => _load()),
            ),
        ]);
      case 'trabajos':
        if (_jobs.isEmpty) return empty('Sin trabajos ni citas.', action: 'Agendar', onAction: _schedule);
        return Column(children: [
          for (final j in _jobs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(j.done ? Icons.check_circle_rounded : Icons.assignment_rounded, color: j.done ? Brand.ok : null),
              title: Text(j.title),
              subtitle: Text([jobKinds[j.kind] ?? j.kind, if (j.scheduledAt != null) shortDateTime(j.scheduledAt!)].join(' · ')),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: j.id!))).then((_) => _load()),
            ),
        ]);
      case 'equipos':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in _assets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.router_rounded),
              title: Text([e.name, e.model].where((x) => x.isNotEmpty).join(' · ')),
              subtitle: Text([
                if (e.serial.isNotEmpty) 'Serie ${e.serial}',
                if (e.installedOn != null) 'Instalado ${displayDate(e.installedOn!)}',
                if (e.warrantyUntil != null) 'Garantía hasta ${displayDate(e.warrantyUntil!)}',
              ].join(' · ')),
            ),
          if (_assets.isEmpty) empty('Registra aquí los equipos que instalaste (con serie y garantía).'),
          OutlinedButton.icon(onPressed: _addAsset, icon: const Icon(Icons.add_rounded), label: const Text('Agregar equipo')),
        ]);
      case 'notas':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final n in _notes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sticky_note_2_rounded),
              title: Text(n.body),
              subtitle: n.createdAt == null ? null : Text(shortDateTime(n.createdAt!)),
            ),
          if (_notes.isEmpty) empty('Sin notas.'),
          OutlinedButton.icon(onPressed: _addNote, icon: const Icon(Icons.add_comment_rounded), label: const Text('Agregar nota')),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_media.isEmpty) empty('Sin fotos.'),
          if (_media.isNotEmpty)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [for (final m in _media) StorageImage(path: m.path)],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _addPhoto, icon: const Icon(Icons.add_a_photo_rounded), label: const Text('Tomar foto')),
        ]);
    }
  }
}

String shortDateTime(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}

/// Imagen privada del bucket (enlace firmado temporal; nunca pública).
class StorageImage extends StatefulWidget {
  const StorageImage({super.key, required this.path, this.fit = BoxFit.cover});
  final String path;
  final BoxFit fit;

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  String? _url;

  @override
  void initState() {
    super.initState();
    V2Repo.signedUrl(widget.path).then((u) {
      if (mounted) setState(() => _url = u);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: _url == null
          ? Container(color: t.colorScheme.surfaceContainerHighest)
          : GestureDetector(
              onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(_url!)))),
              child: Image.network(
                _url!,
                fit: widget.fit,
                cacheWidth: 600,
                errorBuilder: (_, _, _) => Container(color: t.colorScheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_rounded)),
              ),
            ),
    );
  }
}

// ═════════════════════════ Formulario de cliente (guardado automático) ═════════════════════════
/// Crea o edita un cliente. Al editar, cada cambio se guarda solo a los 0,8 s. Devuelve el id.
Future<String?> showClientForm(BuildContext context, {ClientProfile? client, String initialName = ''}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ClientForm(client: client, initialName: initialName),
    );

class _ClientForm extends StatefulWidget {
  const _ClientForm({this.client, this.initialName = ''});
  final ClientProfile? client;
  final String initialName;

  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  late final ClientProfile _c = widget.client ?? ClientProfile(id: '', name: widget.initialName);
  late final _name = TextEditingController(text: _c.name);
  late final _doc = TextEditingController(text: _c.taxId);
  late final _phone = TextEditingController(text: _c.phone);
  late final _email = TextEditingController(text: _c.email);
  late final _address = TextEditingController(text: _c.address);
  late final _district = TextEditingController(text: _c.district);
  late final _ref = TextEditingController(text: _c.reference);
  late final _tags = TextEditingController(text: _c.tags.join(', '));
  late final _notes = TextEditingController(text: _c.notes);
  late final _birthday = TextEditingController(text: _c.birthday ?? '');
  late final _limit = TextEditingController(text: _c.creditLimit?.toStringAsFixed(2) ?? '');
  final Map<String, TextEditingController> _extra = {};
  OrgSettings? _settings;
  Timer? _auto;
  String _status = '';
  bool _busy = false;
  bool _looking = false;
  String _lookupMsg = '';
  int _shake = 0;

  bool get _isNew => widget.client == null;

  @override
  void initState() {
    super.initState();
    V2Repo.settings().then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        for (final f in s.fields) {
          _extra[f.key] = TextEditingController(text: (_c.extra[f.key] ?? '').toString());
        }
      });
    });
  }

  @override
  void dispose() {
    final pending = _auto?.isActive ?? false;
    _auto?.cancel();
    if (!_isNew && pending) _flush(); // lo último escrito no se pierde al cerrar
    for (final c in [_name, _doc, _phone, _email, _address, _district, _ref, _tags, _notes, _birthday, _limit, ..._extra.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    _c
      ..name = _name.text
      ..taxId = _doc.text.replaceAll(RegExp(r'\s'), '')
      ..phone = _phone.text
      ..email = _email.text
      ..address = _address.text
      ..district = _district.text
      ..reference = _ref.text
      ..tags = _tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
      ..notes = _notes.text
      ..birthday = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_birthday.text.trim()) ? _birthday.text.trim() : null
      ..creditLimit = parseDecimal(_limit.text);
    for (final e in _extra.entries) {
      final v = e.value.text.trim();
      if (v.isEmpty) {
        _c.extra.remove(e.key);
      } else {
        _c.extra[e.key] = v;
      }
    }
  }

  void _changed() {
    if (_isNew) return;
    _auto?.cancel();
    setState(() => _status = 'Guardando…');
    _auto = Timer(const Duration(milliseconds: 800), _flush);
  }

  Future<void> _flush() async {
    _auto?.cancel();
    _apply();
    if (_c.name.trim().isEmpty) return;
    try {
      await V2Repo.saveClient(_c);
      if (mounted) setState(() => _status = 'Guardado ✓');
    } catch (e) {
      if (mounted) setState(() => _status = V2Repo.missingHint(e));
    }
  }

  Future<void> _lookup() async {
    final n = _doc.text.replaceAll(RegExp(r'\D'), '');
    if (docKind(n) == null) {
      setState(() {
        _lookupMsg = 'Escribe un DNI (8 dígitos) o RUC (11 dígitos) válido.';
        _shake++;
      });
      return;
    }
    setState(() {
      _looking = true;
      _lookupMsg = '';
    });
    final r = await V2Api.lookup(n);
    if (!mounted) return;
    setState(() {
      _looking = false;
      if (r.ok) {
        final d = r.data!;
        _name.text = d.name;
        if (d.address.isNotEmpty) _address.text = d.address;
        if (d.district.isNotEmpty) _district.text = d.district;
        _lookupMsg = d.kind == 'ruc' && (!d.rucActive || !d.rucHabido) ? 'Ojo: RUC ${d.status} / ${d.condition}. Verifica antes de emitir factura.' : 'Datos completados ✓';
      } else {
        _lookupMsg = r.message;
      }
    });
    _changed();
  }

  Future<void> _create() async {
    _apply();
    if (_c.name.trim().isEmpty) {
      setState(() => _shake++);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await V2Repo.saveClient(_c, isNew: true);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = V2Repo.missingHint(e);
        });
      }
    }
  }

  Widget _field(TextEditingController c, String label, {TextInputType? type, String? hint, int maxLines = 1, Widget? suffix}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: type,
          maxLines: maxLines,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, children: [
        Row(children: [
          Expanded(child: Text(_isNew ? 'Nuevo cliente' : 'Editar cliente', style: t.textTheme.titleLarge)),
          if (_status.isNotEmpty) Text(_status, style: t.textTheme.bodySmall?.copyWith(color: _status.startsWith('Guardado') ? Brand.ok : null)),
        ]),
        const SizedBox(height: 12),
        Shake(
          trigger: _shake,
          child: Column(children: [
            _field(_doc, 'DNI o RUC',
                type: TextInputType.number,
                suffix: IconButton(
                  tooltip: 'Buscar datos',
                  onPressed: _looking ? null : _lookup,
                  icon: _looking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore_rounded),
                )),
            if (_lookupMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_lookupMsg, style: t.textTheme.bodySmall)),
            _field(_name, 'Nombre o razón social *'),
          ]),
        ),
        _field(_phone, 'Celular (WhatsApp)', type: TextInputType.phone),
        _field(_email, 'Correo', type: TextInputType.emailAddress),
        _field(_address, 'Dirección'),
        _field(_district, 'Distrito'),
        _field(_ref, 'Referencia', hint: 'Ej.: frente al parque, puerta verde'),
        for (final f in _settings?.fields ?? const <ClientField>[])
          if (_extra[f.key] != null) _field(_extra[f.key]!, f.label, hint: f.hint.isEmpty ? null : f.hint),
        DropdownButtonFormField<String>(
          // "initialValue" (no "value"): evita el error de Flutter 3.35 al reconstruir el formulario.
          initialValue: clientSources.containsKey(_c.source) ? _c.source : null,
          decoration: const InputDecoration(labelText: '¿Cómo te conoció?'),
          items: [for (final e in clientSources.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            _c.source = v ?? '';
            _changed();
          },
        ),
        const SizedBox(height: 10),
        _field(_tags, 'Etiquetas (separadas por coma)', hint: 'vip, mayorista, zona norte'),
        _field(_birthday, 'Cumpleaños (AAAA-MM-DD)', type: TextInputType.datetime),
        if (Access.instance.has('fiados')) _field(_limit, 'Límite de fiado (opcional)', type: const TextInputType.numberWithOptions(decimal: true)),
        _field(_notes, 'Notas internas', maxLines: 3),
        if (_isNew) ...[
          const SizedBox(height: 6),
          GradientButton(label: 'Guardar cliente', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _create),
        ] else
          TextButton(onPressed: () => Navigator.of(context).pop(_c.id), child: const Text('Listo')),
      ]),
    );
  }
}
