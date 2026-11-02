// Funciones estrella de cada rubro (B3). Todas leen datos reales de la empresa: si no hay datos, lo dicen.
//   Bodega ............ ReorderScreen        (reposición inteligente)
//   Restaurante ....... DishesScreen         (cuenta dividida, propina y costo por plato)
//   Servicios técnicos  CutoffScreen         (mensualidades y corte por mora)
//   Salón / academia .. PackagesScreen       (paquetes, sesiones y no-shows)
//   Consultorio ....... PrivateHistoryScreen (historial privado con consentimiento)
//   Taller ............ PlateScreen + RemindersScreen (placa, historial y mantenimientos)
//   Mayorista ......... CreditScreen         (crédito con límite)
//   Academia .......... MorosityScreen       (morosidad por grupo y apoderados)
//   Construcción ...... JobMarginScreen      (margen por obra)
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../errors.dart';
import '../finance.dart' show addDays, daysBetween;
import '../logic/cutoff.dart';
import '../logic/obra.dart';
import '../logic/stagnant.dart';
import '../models.dart';
import '../models_pro.dart';
import '../models_v2.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../services/rubro_repo.dart';
import '../services/live.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show ClientProfileScreen, openWhatsApp;

String get _cur => AppState.instance.profile?.currency ?? 'PEN';
String get _biz => AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? '';

Future<void> _shareText(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await launchUrl(Uri.https('wa.me', '/', {'text': text}), mode: LaunchMode.externalApplication)) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
  }
}

Widget _empty(BuildContext context, IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );

/// Elegir un cliente (con búsqueda). Devuelve null si se cancela.
Future<ClientProfile?> pickClient(BuildContext context, {String title = 'Elige el cliente'}) => showModalBottomSheet<ClientProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _ClientPicker(title: title),
    );

class _ClientPicker extends StatefulWidget {
  const _ClientPicker({required this.title});
  final String title;
  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  List<ClientProfile>? _list;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await V2Repo.clients(q: _q);
    if (mounted) setState(() => _list = r);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Nombre, DNI/RUC o celular'),
                onChanged: (v) {
                  _q = v;
                  _load();
                },
              ),
            ),
            Expanded(
              child: _list == null
                  ? const Center(child: CircularProgressIndicator())
                  : _list!.isEmpty
                      ? const Center(child: Text('No hay clientes con ese dato.'))
                      : ListView(children: [
                          for (final c in _list!)
                            ListTile(title: Text(c.name), subtitle: Text([c.taxId, c.phone].where((x) => x.isNotEmpty).join(' · ')), onTap: () => Navigator.pop(context, c)),
                        ]),
            ),
          ]),
        ),
      );
}

// ═════════════════════════ Bodega: reposición inteligente ═════════════════════════
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key});
  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

/// Cuánto pedir para cubrir [days] días al ritmo de los últimos 30, menos lo que hay (redondeado hacia arriba).
double suggestedOrder(ProductVelocity v, {int days = 14}) {
  final need = v.perDay * days - (v.stock ?? 0);
  final floor = (v.reorderPoint ?? 0) - (v.stock ?? 0);
  return math.max(0, math.max(need, floor)).ceilToDouble();
}

class _ReorderScreenState extends State<ReorderScreen> {
  List<ProductVelocity>? _rows;
  String? _error;
  int _days = 14;

  @override
  void initState() {
    super.initState();
    ProRepo.productVelocity().then((r) {
      if (mounted) setState(() => _rows = r);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendly(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = (_rows ?? const <ProductVelocity>[]).where((v) => v.stock != null && suggestedOrder(v, days: _days) > 0).toList()
      ..sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));
    final untracked = (_rows ?? const <ProductVelocity>[]).where((v) => v.stock == null).length;
    final stuck = stagnantProducts(_rows ?? const <ProductVelocity>[]);
    return Scaffold(
      appBar: AppBar(title: const Text('Reposición inteligente')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _rows == null
              ? const SkeletonList()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
                  Text('Según lo que vendiste los últimos 30 días, esto alcanza para menos de $_days días.', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [ButtonSegment(value: 7, label: Text('1 semana')), ButtonSegment(value: 14, label: Text('2 semanas')), ButtonSegment(value: 30, label: Text('1 mes'))],
                    selected: {_days},
                    onSelectionChanged: (s) => setState(() => _days = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    _empty(context, Icons.inventory_2_outlined, 'No hay nada urgente por reponer',
                        untracked > 0 ? '$untracked productos no tienen stock registrado: ponles su cantidad en Productos para que pueda calcular.' : 'Cuando vendas, aquí verás lo que se acaba primero.')
                  else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final v in rows)
                          ListTile(
                            title: Text(v.name),
                            subtitle: Text('Quedan ${qtyText(v.stock ?? 0)} · vendes ${v.perDay.toStringAsFixed(1)} al día'
                                '${v.daysLeft == null ? '' : ' · alcanza ${v.daysLeft!.floor()} días'}'),
                            trailing: Text('Pedir ${qtyText(suggestedOrder(v, days: _days))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ),
                  if (stuck.isNotEmpty) ...[
                    const SizedBox(height: Gap.lg),
                    const SectionTitle('No se movieron en 30 días'),
                    Text('Tienen stock pero no vendiste ninguno. No compres más hasta que roten; los recién agregados también pueden salir aquí.', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: Gap.sm),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final v in stuck) ListTile(dense: true, title: Text(v.name), trailing: Text('${qtyText(v.stock ?? 0)} en stock')),
                      ]),
                    ),
                  ],
                ]),
      floatingActionButton: rows.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar pedido al proveedor'),
              onPressed: () => _shareText(context, 'Hola, soy de $_biz. Quisiera pedir:\n${rows.map((v) => '• ${qtyText(suggestedOrder(v, days: _days))} × ${v.name}').join('\n')}\nGracias.'),
            ),
    );
  }
}

// ═════════════════════════ Restaurante: cuenta dividida, propina y costo por plato ═════════════════════════
class DishesScreen extends StatefulWidget {
  const DishesScreen({super.key});
  @override
  State<DishesScreen> createState() => _DishesScreenState();
}

/// Partes iguales con el redondeo en la última persona (la suma siempre da el total exacto).
List<double> splitEven(double total, int people) {
  if (people <= 1) return [round2(total)];
  final each = (total / people * 10).floor() / 10; // al décimo, más fácil de pagar en efectivo
  return [for (var i = 0; i < people - 1; i++) each, round2(total - each * (people - 1))];
}

class _DishesScreenState extends State<DishesScreen> {
  final _total = TextEditingController();
  int _people = 2;
  double _tipPct = 0;
  List<Product>? _products;

  @override
  void initState() {
    super.initState();
    Repo.listProducts(activeOnly: true).then((p) {
      if (mounted) setState(() => _products = p);
    });
  }

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final total = double.tryParse(_total.text.replaceAll(',', '.')) ?? 0;
    final tip = round2(total * _tipPct / 100);
    final parts = splitEven(total + tip, _people);
    final dishes = (_products ?? const <Product>[]).where((p) => p.margin != null).toList()..sort((a, b) => a.margin!.compareTo(b.margin!));
    final noCost = (_products ?? const <Product>[]).where((p) => p.unitCost == null).length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Cuentas y platos'), bottom: const TabBar(tabs: [Tab(text: 'Dividir cuenta'), Tab(text: 'Costo por plato')])),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Total de la cuenta (con IGV)', prefixText: '${currencySymbols[_cur] ?? _cur} '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('¿Entre cuántos?')),
              IconButton(onPressed: _people > 1 ? () => setState(() => _people--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_people', style: t.textTheme.titleLarge),
              IconButton(onPressed: _people < 30 ? () => setState(() => _people++) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 8),
            const Text('Propina voluntaria (va para el equipo, no entra al comprobante)'),
            Wrap(spacing: 8, children: [
              for (final p in const [0.0, 5.0, 10.0, 15.0]) ChoiceChip(label: Text(p == 0 ? 'Sin propina' : '${p.toInt()} %'), selected: _tipPct == p, onSelected: (_) => setState(() => _tipPct = p)),
            ]),
            const SizedBox(height: 16),
            if (total > 0)
              SoftCard(
                child: Column(children: [
                  DataRow2('Cuenta', money(total, _cur)),
                  if (tip > 0) DataRow2('Propina', money(tip, _cur)),
                  const Divider(),
                  for (final (i, p) in parts.indexed) DataRow2('Persona ${i + 1}', money(p, _cur), strong: true),
                ]),
              ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.send_rounded),
                label: const Text('Mandar el detalle por WhatsApp'),
                onPressed: () => _shareText(context, 'Cuenta en $_biz: ${money(total, _cur)}${tip > 0 ? ' + propina ${money(tip, _cur)}' : ''}. '
                    'Entre $_people: ${parts.map((p) => money(p, _cur)).join(' / ')}.'),
              ),
            ],
          ]),
          _products == null
              ? const SkeletonList()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (dishes.isEmpty)
                    _empty(context, Icons.restaurant_menu_rounded, 'Aún no sé cuánto te cuesta cada plato',
                        'Abre Productos y escribe el costo (insumos) de cada plato. Así te digo cuáles te dejan más y cuáles menos.')
                  else ...[
                    Text('De menor a mayor margen (precio sin IGV menos costo).', style: t.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final p in dishes)
                          ListTile(
                            title: Text(p.name),
                            subtitle: Text('Precio ${money(p.unitPrice, _cur)} · costo ${money(p.unitCost!, _cur)}'),
                            trailing: Text('${(p.margin! * 100).round()} %',
                                style: TextStyle(fontWeight: FontWeight.w800, color: p.margin! < 0.3 ? Brand.bad : p.margin! < 0.5 ? Brand.warn : Brand.ok)),
                          ),
                      ]),
                    ),
                    if (noCost > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('$noCost platos sin costo registrado no aparecen aquí.', style: t.textTheme.bodySmall)),
                  ],
                ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════ Servicios técnicos: mensualidades y corte por mora ═════════════════════════
class CutoffScreen extends StatefulWidget {
  const CutoffScreen({super.key});
  @override
  State<CutoffScreen> createState() => _CutoffScreenState();
}

class _Debtor {
  _Debtor(this.name);
  final String name;
  double balance = 0;
  int maxDays = 0;
  int count = 0;
  ClientProfile? client;
}

class _CutoffScreenState extends State<CutoffScreen> {
  List<_Debtor>? _rows;
  String? _error;
  int _minDays = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rec = await ProRepo.listReceivables();
      final clients = await V2Repo.clients();
      final byName = {for (final c in clients) c.name.trim().toLowerCase(): c};
      final today = todayIso();
      final m = <String, _Debtor>{};
      for (final i in rec.where((i) => i.currency == _cur)) {
        final days = i.dueDate == null ? 0 : daysBetween(i.dueDate!, today);
        final d = m.putIfAbsent(i.clientName, () => _Debtor(i.clientName)..client = byName[i.clientName.trim().toLowerCase()]);
        d.balance = round2(d.balance + i.balance);
        d.count++;
        d.maxDays = math.max(d.maxDays, days);
      }
      if (mounted) setState(() => _rows = m.values.toList()..sort((a, b) => b.maxDays.compareTo(a.maxDays)));
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _state(_Debtor d, String state) async {
    final c = d.client;
    if (c == null) return;
    await RubroRepo.setServiceState(c.id, c.extra, state);
    c.extra['servicio'] = state;
    c.extra['servicio_fecha'] = todayIso();
    if (state == 'activo') c.extra.remove('aviso_corte_fecha');
    if (mounted) {
      setState(() {});
      showSuccess(context, state == 'cortado' ? 'Registrado: servicio cortado' : 'Registrado: servicio reconectado');
    }
  }

  Future<void> _notice(_Debtor d) async {
    final c = d.client;
    if (c == null) return;
    await openWhatsApp(context, c.phone,
        'Hola ${d.name.split(' ').first}, te escribe $_biz. Tienes ${money(d.balance, _cur)} pendiente de tu servicio. '
        'Para evitar la suspensión, por favor regulariza tu pago. Si ya pagaste, envíanos tu constancia. ¡Gracias!');
    await RubroRepo.setCutoffNotice(c.id, c.extra);
    c.extra['aviso_corte_fecha'] = todayIso();
    if (mounted) {
      setState(() {});
      showSuccess(context, 'Aviso registrado hoy. Podrás registrar el corte desde mañana.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = (_rows ?? const <_Debtor>[]).where((d) => d.maxDays >= _minDays).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Mensualidades y corte por mora')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _rows == null
              ? const SkeletonList()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                    Wrap(spacing: 8, children: [
                      for (final d in const [1, 5, 15, 30]) ChoiceChip(label: Text('Atrasados $d+ días'), selected: _minDays == d, onSelected: (_) => setState(() => _minDays = d)),
                    ]),
                    const SizedBox(height: 8),
                    Text('Primero se avisa por WhatsApp; el corte se habilita desde el día siguiente al aviso. Registra cada corte y reconexión.', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      _empty(context, Icons.wifi_rounded, 'Nadie con ese atraso', 'Todos tus abonados están al día para este filtro.')
                    else
                      for (final d in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SoftCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(d.name, style: Theme.of(context).textTheme.titleMedium)),
                                if (d.client?.extra['servicio'] == 'cortado') const StatusPill('Cortado', tone: PillTone.bad),
                              ]),
                              Text('Debe ${money(d.balance, _cur)} · ${d.count} recibo(s) · ${d.maxDays} días de atraso'),
                              if (d.client != null && d.client?.extra['servicio'] != 'cortado') Text(noticeLabel(d.client!.extra, todayIso()), style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 6, children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.chat_rounded, size: 18),
                                  label: const Text('Aviso previo'),
                                  onPressed: d.client == null || d.client!.phone.isEmpty ? null : () => _notice(d),
                                ),
                                if (d.client?.extra['servicio'] != 'cortado')
                                  TextButton(onPressed: d.client == null || !canCut(d.client!.extra, todayIso()) ? null : () => _state(d, 'cortado'), child: const Text('Registrar corte'))
                                else
                                  TextButton(onPressed: () => _state(d, 'activo'), child: const Text('Registrar reconexión')),
                              ]),
                            ]),
                          ),
                        ),
                  ]),
                ),
    );
  }
}

// ═════════════════════════ Paquetes y sesiones (salón, consultorio, academia) ═════════════════════════
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  List<ServicePackage>? _rows;
  List<Job>? _noShows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await RubroRepo.packages();
      final jobs = await V2Repo.jobs(from: DateTime.now().subtract(const Duration(days: 90)));
      if (mounted) {
        setState(() {
          _rows = p;
          _noShows = jobs.where((j) => j.status == 'no_vino').toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _add() async {
    final c = await pickClient(context);
    if (c == null || !mounted) return;
    final name = TextEditingController(text: '4 sesiones');
    final n = TextEditingController(text: '4');
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Paquete para ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del paquete')),
          TextField(controller: n, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Número de sesiones')),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio (opcional)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Guardar'))],
      ),
    );
    final sessions = int.tryParse(n.text) ?? 0;
    if (ok != true || sessions < 1 || name.text.trim().isEmpty) return;
    try {
      await RubroRepo.addPackage(clientId: c.id, name: name.text, sessions: sessions, price: double.tryParse(price.text.replaceAll(',', '.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  Future<void> _use(ServicePackage p) async {
    try {
      final left = await RubroRepo.useSession(p.id);
      if (mounted) showSuccess(context, left == 0 ? 'Última sesión usada' : 'Le quedan $left sesiones');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = todayIso();
    final active = (_rows ?? const <ServicePackage>[]).where((p) => p.left > 0 && !p.expired(today)).toList();
    final counts = <String, int>{};
    for (final j in _noShows ?? const <Job>[]) {
      counts[j.clientName] = (counts[j.clientName] ?? 0) + 1;
    }
    final ranking = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Paquetes y sesiones')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Nuevo paquete')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _rows == null
              ? const SkeletonList()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
                  const SectionTitle('Paquetes con sesiones por usar'),
                  if (active.isEmpty)
                    _empty(context, Icons.card_giftcard_rounded, 'No hay paquetes activos', 'Vende paquetes (por ejemplo 4 sesiones) y descuenta cada visita con un toque.')
                  else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final p in active)
                          ListTile(
                            title: Text('${p.clientName} · ${p.name}'),
                            subtitle: Text('Usó ${p.used} de ${p.total}${p.expiresOn == null ? '' : ' · vence ${displayDate(p.expiresOn!)}'}'),
                            trailing: FilledButton.tonal(onPressed: () => _use(p), child: const Text('Usar 1')),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 16),
                  const SectionTitle('Faltaron a su cita (últimos 90 días)'),
                  if (ranking.isEmpty)
                    const Padding(padding: EdgeInsets.all(8), child: Text('Nadie marcado como "No vino". Márcalo en la Agenda cuando pase.'))
                  else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final e in ranking.take(10))
                          ListTile(title: Text(e.key), trailing: Text('${e.value} ${e.value == 1 ? 'vez' : 'veces'}', style: TextStyle(color: e.value >= 2 ? Brand.bad : null, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  if (ranking.any((e) => e.value >= 2))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Idea: a quien faltó 2 veces o más, pídele un adelanto (Yape) para reservar.', style: Theme.of(context).textTheme.bodySmall),
                    ),
                ]),
    );
  }
}

// ═════════════════════════ Consultorio: historial privado ═════════════════════════
class PrivateHistoryScreen extends StatefulWidget {
  const PrivateHistoryScreen({super.key, this.client});
  final ClientProfile? client;
  @override
  State<PrivateHistoryScreen> createState() => _PrivateHistoryScreenState();
}

class _PrivateHistoryScreenState extends State<PrivateHistoryScreen> {
  ClientProfile? _c;
  List<PrivateNote>? _notes;
  final _text = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = widget.client;
    if (_c != null) _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final n = await RubroRepo.privateNotes(_c!.id);
      if (mounted) setState(() => _notes = n);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _choose() async {
    final c = await pickClient(context, title: 'Elige el paciente');
    if (c == null) return;
    setState(() {
      _c = c;
      _notes = null;
    });
    _load();
  }

  bool get _consent => _c?.extra['consentimiento_salud'] != null;

  Future<void> _recordConsent() async {
    final c = _c!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Consentimiento del paciente'),
        content: const Text('Los datos de salud son sensibles (Ley 29733). Antes de guardar notas necesitas el consentimiento '
            'POR ESCRITO del paciente (firma en papel o digital). Guárdalo en tu archivo.\n\n¿El paciente ya firmó su consentimiento?'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Todavía no')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sí, firmó'))],
      ),
    );
    if (ok != true) return;
    c.extra['consentimiento_salud'] = todayIso();
    await V2Repo.saveClient(c);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (_text.text.trim().isEmpty) return;
    try {
      await RubroRepo.addPrivateNote(_c!.id, _text.text);
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial privado')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SoftCard(
          child: Row(children: [
            const Icon(Icons.lock_rounded, color: Brand.indigo),
            const SizedBox(width: 10),
            const Expanded(child: Text('Solo lo ves tú y el dueño/administrador. No lo lee el Copiloto ni sale en reportes.')),
          ]),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.person_rounded),
          title: Text(_c?.name ?? 'Elige un paciente'),
          subtitle: _c == null ? null : Text(_consent ? 'Consentimiento registrado el ${displayDate(_c!.extra['consentimiento_salud'] as String)}' : 'Sin consentimiento registrado'),
          trailing: TextButton(onPressed: _choose, child: Text(_c == null ? 'Elegir' : 'Cambiar')),
        ),
        if (_c != null && !_consent) FilledButton.icon(onPressed: _recordConsent, icon: const Icon(Icons.draw_rounded), label: const Text('Registrar consentimiento firmado')),
        if (_c != null && _consent) ...[
          TextField(controller: _text, minLines: 2, maxLines: 6, maxLength: 4000, decoration: const InputDecoration(labelText: 'Nueva nota (no se puede editar después)')),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _add, child: const Text('Guardar nota'))),
        ],
        if (_error != null) Text(_error!, style: const TextStyle(color: Brand.bad)),
        if (_c != null && _notes != null) ...[
          const SizedBox(height: 8),
          if (_notes!.isEmpty) const Text('Aún no hay notas.'),
          for (final n in _notes!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftCard(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${displayDate(todayIso(n.createdAt))} ${TimeOfDay.fromDateTime(n.createdAt).format(context)}${n.mine ? '' : ' · de otro profesional'}', style: t.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(n.body),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

// ═════════════════════════ Recordatorios de volver (taller, salón, consultorio) ═════════════════════════
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> with LiveReload<RemindersScreen> {
  List<Reminder>? _rows;
  String? _error;

  @override
  List<String> get liveTables => const ['service_reminders'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _rows = LiveCache.get<List<Reminder>>('reminders.30');
    _load();
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await RubroRepo.reminders(days: 30);
      LiveCache.put('reminders.30', r);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _add() async {
    final c = await pickClient(context);
    if (c == null || !mounted) return;
    final title = TextEditingController(text: 'Mantenimiento');
    var days = 90;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Recordar a ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: '¿Qué toca?')),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final n in const [15, 30, 90, 180]) ChoiceChip(label: Text(n < 30 ? '$n días' : '${n ~/ 30} ${n == 30 ? 'mes' : 'meses'}'), selected: days == n, onSelected: (_) => set(() => days = n)),
            ]),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Guardar'))],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await RubroRepo.addReminder(clientId: c.id, dueOn: addDays(todayIso(), days), title: title.text);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = todayIso();
    return Scaffold(
      appBar: AppBar(title: const Text('Les toca volver')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.alarm_add_rounded), label: const Text('Recordar')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _rows == null
              ? const SkeletonList()
              : _rows!.isEmpty
                  ? _empty(context, Icons.event_available_rounded, 'Nadie para los próximos 30 días', 'Al cerrar un servicio, agenda cuándo debe volver (mantenimiento, control, retoque).')
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
                      for (final r in _rows!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SoftCard(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: ListTile(
                              title: Text('${r.clientName} · ${r.title}'),
                              subtitle: Text('${r.dueOn.compareTo(today) < 0 ? 'Atrasado desde' : 'Toca el'} ${displayDate(r.dueOn)}${r.assetName.isEmpty ? '' : ' · ${r.assetName}'}'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: 'Avisar por WhatsApp',
                                  icon: const Icon(Icons.chat_rounded),
                                  onPressed: r.clientPhone.isEmpty
                                      ? null
                                      : () => openWhatsApp(context, r.clientPhone, 'Hola ${r.clientName.split(' ').first}, te escribe $_biz: ya te toca ${r.title.toLowerCase()}. ¿Te reservo un horario?'),
                                ),
                                IconButton(
                                  tooltip: 'Hecho',
                                  icon: const Icon(Icons.check_circle_outline_rounded),
                                  onPressed: () async {
                                    await RubroRepo.doneReminder(r.id);
                                    _load();
                                  },
                                ),
                              ]),
                            ),
                          ),
                        ),
                    ]),
    );
  }
}

// ═════════════════════════ Taller: buscar por placa ═════════════════════════
class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<PlateScreen> createState() => _PlateScreenState();
}

class _PlateScreenState extends State<PlateScreen> {
  final _q = TextEditingController();
  List<VehicleHit>? _hits;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final r = await RubroRepo.findPlate(_q.text);
      if (mounted) setState(() => _hits = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    final c = await pickClient(context, title: '¿De quién es el carro?');
    if (c == null || !mounted) return;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Placa ${RubroRepo.normPlate(_q.text)}'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Marca y modelo', hintText: 'Toyota Yaris 2018')),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Guardar'))],
      ),
    );
    if (ok != true) return;
    await V2Repo.addAsset(clientId: c.id, name: name.text.trim().isEmpty ? 'Vehículo' : name.text.trim(), serial: RubroRepo.normPlate(_q.text));
    await _search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Buscar por placa')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _q,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: 'Placa', hintText: 'ABC-123', suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search)),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_hits != null && _hits!.isEmpty) ...[
            _empty(context, Icons.directions_car_rounded, 'No tengo esa placa', 'Regístrala una vez y la próxima la encuentras al instante con su historial.'),
            FilledButton.icon(onPressed: _q.text.trim().length < 5 ? null : _register, icon: const Icon(Icons.add_rounded), label: const Text('Registrar este vehículo')),
          ],
          for (final h in _hits ?? const <VehicleHit>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.directions_car_rounded),
                  title: Text('${h.plate} · ${h.name}'),
                  subtitle: Text(h.clientName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => pushPremium(context, ClientProfileScreen(clientId: h.clientId)),
                ),
              ),
            ),
        ]),
      );
}

// ═════════════════════════ Mayorista: crédito con límite ═════════════════════════
class CreditScreen extends StatefulWidget {
  const CreditScreen({super.key});
  @override
  State<CreditScreen> createState() => _CreditScreenState();
}

class _CreditRow {
  _CreditRow(this.client, this.used);
  final ClientProfile client;
  final double used;
  double get limit => client.creditLimit ?? 0;
  double get left => round2(limit - used);
  bool get over => limit > 0 && used > limit + 0.004;
}

class _CreditScreenState extends State<CreditScreen> {
  List<_CreditRow>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final clients = await V2Repo.clients();
      final rec = await ProRepo.listReceivables();
      final used = <String, double>{};
      for (final i in rec.where((i) => i.currency == _cur)) {
        final k = i.clientName.trim().toLowerCase();
        used[k] = round2((used[k] ?? 0) + i.balance);
      }
      final rows = [
        for (final c in clients)
          if ((c.creditLimit ?? 0) > 0 || (used[c.name.trim().toLowerCase()] ?? 0) > 0) _CreditRow(c, used[c.name.trim().toLowerCase()] ?? 0),
      ]..sort((a, b) {
          final o = (b.over ? 1 : 0) - (a.over ? 1 : 0); // primero los que pasaron su límite
          return o != 0 ? o : b.used.compareTo(a.used);
        });
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _setLimit(_CreditRow r) async {
    final ctl = TextEditingController(text: r.limit > 0 ? r.limit.toStringAsFixed(0) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Límite de crédito · ${r.client.name}'),
        content: TextField(controller: ctl, keyboardType: TextInputType.number, decoration: InputDecoration(prefixText: '${currencySymbols[_cur] ?? _cur} ', helperText: '0 = sin crédito')),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Guardar'))],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctl.text.replaceAll(',', '.'));
    r.client.creditLimit = v == null || v <= 0 ? null : v;
    await V2Repo.saveClient(r.client);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? const <_CreditRow>[];
    final over = rows.where((r) => r.over).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Crédito por cliente')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _rows == null
              ? const SkeletonList()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                    if (over > 0)
                      SoftCard(color: Brand.bad.withValues(alpha: 0.08), child: Text('$over cliente(s) ya pasaron su límite. Cobra antes de venderles más al crédito.')),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      _empty(context, Icons.credit_score_rounded, 'Nadie tiene crédito todavía', 'Fija un límite en la ficha de cada cliente o aquí mismo cuando le vendas al crédito.')
                    else
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SoftCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(r.client.name, style: Theme.of(context).textTheme.titleMedium)),
                                if (r.over) const StatusPill('Pasó el límite', tone: PillTone.bad),
                              ]),
                              const SizedBox(height: 6),
                              if (r.limit > 0) LinearProgressIndicator(value: (r.used / r.limit).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(Radii.sm), color: r.over ? Brand.bad : null),
                              const SizedBox(height: 6),
                              Text(r.limit > 0
                                  ? 'Debe ${money(r.used, _cur)} de ${money(r.limit, _cur)} · ${r.left >= 0 ? 'le queda ${money(r.left, _cur)}' : 'pasó por ${money(-r.left, _cur)}'}'
                                  : 'Debe ${money(r.used, _cur)} · sin límite fijado'),
                              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _setLimit(r), child: Text(r.limit > 0 ? 'Cambiar límite' : 'Fijar límite'))),
                            ]),
                          ),
                        ),
                  ]),
                ),
    );
  }
}

// ═════════════════════════ Academia: morosidad por grupo ═════════════════════════
class MorosityScreen extends StatefulWidget {
  const MorosityScreen({super.key});
  @override
  State<MorosityScreen> createState() => _MorosityScreenState();
}

class _MorosityScreenState extends State<MorosityScreen> {
  Map<String, List<(ClientProfile?, String, double)>>? _groups;
  final Map<String, int> _days = {}; // apoderado -> días de atraso de su deuda más vieja
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final clients = await V2Repo.clients();
      final byName = {for (final c in clients) c.name.trim().toLowerCase(): c};
      final rec = await ProRepo.listReceivables();
      final debt = <String, double>{};
      final today = todayIso();
      _days.clear();
      for (final i in rec.where((i) => i.currency == _cur)) {
        debt[i.clientName] = round2((debt[i.clientName] ?? 0) + i.balance);
        final late = i.dueDate == null ? 0 : daysBetween(i.dueDate!, today);
        if (late > (_days[i.clientName] ?? 0)) _days[i.clientName] = late;
      }
      final g = <String, List<(ClientProfile?, String, double)>>{};
      for (final e in debt.entries) {
        final c = byName[e.key.trim().toLowerCase()];
        final group = ((c?.extra['grupo'] ?? '') as Object).toString().trim();
        g.putIfAbsent(group.isEmpty ? 'Sin grupo' : group, () => []).add((c, e.key, e.value));
      }
      for (final l in g.values) {
        l.sort((a, b) => (_days[b.$2] ?? 0).compareTo(_days[a.$2] ?? 0)); // primero los más atrasados
      }
      if (mounted) setState(() => _groups = g);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  Future<void> _warn(ClientProfile c, String name, double amount) async {
    await openWhatsApp(context, c.phone,
        'Hola, le escribe $_biz. Tiene una pensión pendiente de ${money(amount, _cur)}${(c.extra['alumno'] ?? '').toString().isEmpty ? '' : ' de ${c.extra['alumno']}'}. ¿Le ayudamos con el pago? Gracias.');
    await RubroRepo.setNoticeDate(c.id, c.extra, pensionNoticeKey);
    c.extra[pensionNoticeKey] = todayIso();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = _groups ?? const {};
    final keys = g.keys.toList()..sort((a, b) => g[b]!.length.compareTo(g[a]!.length));
    return Scaffold(
      appBar: AppBar(title: const Text('Pensiones pendientes')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _groups == null
              ? const SkeletonList()
              : keys.isEmpty
                  ? _empty(context, Icons.school_rounded, 'Nadie debe pensiones', 'Cuando una pensión venza sin pagarse, aparecerá aquí agrupada por grupo u horario.')
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                      for (final k in keys) ...[
                        SectionTitle('$k · ${g[k]!.length} con deuda · ${money(g[k]!.fold(0.0, (a, x) => a + x.$3), _cur)}'),
                        SoftCard(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(children: [
                            for (final (c, name, amount) in g[k]!)
                              ListTile(
                                title: Text(name),
                                subtitle: Text([
                                  if ((c?.extra['alumno'] ?? '').toString().isNotEmpty) 'Alumno: ${c!.extra['alumno']}',
                                  'Debe ${money(amount, _cur)}',
                                  if ((_days[name] ?? 0) > 0) '${_days[name]} días de atraso',
                                  if (c != null && lastNoticeText(c.extra, pensionNoticeKey, todayIso()).isNotEmpty) lastNoticeText(c.extra, pensionNoticeKey, todayIso()),
                                ].join(' · ')),
                                trailing: IconButton(
                                  icon: const Icon(Icons.chat_rounded),
                                  tooltip: 'Avisar al apoderado',
                                  onPressed: c == null || c.phone.isEmpty ? null : () => _warn(c, name, amount),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ]),
    );
  }
}

// ═════════════════════════ Construcción: margen por obra ═════════════════════════
class JobMarginScreen extends StatefulWidget {
  const JobMarginScreen({super.key});
  @override
  State<JobMarginScreen> createState() => _JobMarginScreenState();
}

class _Obra {
  _Obra(this.job);
  final Job job;
  double agreed = 0; // suma de hitos (valorizaciones)
  double invoiced = 0; // hitos facturados
  double spent = 0; // gastos asignados a la obra
  double? get margin => invoiced <= 0 ? null : (invoiced - spent) / invoiced;
  double get progress => agreed <= 0 ? 0 : invoiced / agreed;
}

class _JobMarginScreenState extends State<JobMarginScreen> {
  List<_Obra>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final jobs = await V2Repo.jobs(limit: 500);
      final ms = await RubroRepo.allMilestones();
      final spent = await RubroRepo.expensesByJob();
      final by = {for (final j in jobs) if (j.id != null) j.id!: _Obra(j)};
      for (final m in ms) {
        final o = by[m['job_id']];
        if (o == null) continue;
        final a = (m['amount'] as num).toDouble();
        o.agreed += a;
        if (m['status'] == 'facturado') o.invoiced += a;
      }
      spent.forEach((k, v) => by[k]?.spent = v);
      final rows = by.values.where((o) => o.agreed > 0 || o.spent > 0).toList()..sort((a, b) => (a.margin ?? 9).compareTo(b.margin ?? 9));
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  /// Asignar gastos ya registrados (materiales, subcontratistas) a esta obra.
  Future<void> _assign(_Obra o) async {
    final list = await RubroRepo.unassignedExpenses();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.6,
        child: list.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No hay gastos sin obra en los últimos 120 días. Regístralos en Gastos.')))
            : ListView(children: [
                Padding(padding: const EdgeInsets.all(16), child: Text('Gastos para "${o.job.title}"', style: Theme.of(c).textTheme.titleMedium)),
                for (final e in list)
                  ListTile(
                    title: Text((e['description'] ?? '') as String),
                    subtitle: Text('${displayDate(e['spent_on'] as String)}${(e['supplier_name'] ?? '').toString().isEmpty ? '' : ' · ${e['supplier_name']}'}'),
                    trailing: Text(money((e['total'] as num).toDouble(), (e['currency'] ?? _cur) as String)),
                    onTap: () => Navigator.pop(c, e['id'] as String),
                  ),
              ]),
      ),
    );
    if (picked == null || o.job.id == null) return;
    try {
      await RubroRepo.setExpenseJob(picked, o.job.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Margen por obra')),
        body: _error != null
            ? Center(child: Text(_error!))
            : _rows == null
                ? const SkeletonList()
                : _rows!.isEmpty
                    ? _empty(context, Icons.engineering_rounded, 'Aún no hay obras con hitos o gastos',
                        'Divide cada obra en hitos (adelanto, avance, entrega) y asigna tus gastos y subcontratistas a la obra desde Gastos.')
                    : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                        Text('Facturado = hitos ya facturados. Gastado = gastos y subcontratistas asignados a la obra (con IGV).', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        for (final o in _rows!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SoftCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(o.job.title, style: Theme.of(context).textTheme.titleMedium),
                                if (o.job.clientName.isNotEmpty) Text(o.job.clientName, style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(value: o.progress.clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(Radii.sm)),
                                const SizedBox(height: 6),
                                DataRow2('Contratado (hitos)', money(o.agreed, _cur)),
                                DataRow2('Facturado', money(o.invoiced, _cur)),
                                DataRow2('Gastado', money(o.spent, _cur)),
                                DataRow2('Te queda', money(round2(o.invoiced - o.spent), _cur), strong: true),
                                Builder(builder: (context) {
                                  final sg = obraSignal(agreed: o.agreed, invoiced: o.invoiced, spent: o.spent);
                                  if (sg.alert == ObraAlert.none) return const SizedBox.shrink();
                                  final over = sg.alert == ObraAlert.over;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: Gap.sm),
                                    child: Text(
                                      over
                                          ? 'Ya gastaste ${(sg.spentShare * 100).round()} % del contrato: revisa antes de seguir comprando.'
                                          : 'Llevas gastado ${(sg.spentShare * 100).round()} % del contrato pero facturado solo ${(sg.invoicedShare * 100).round()} %. Revisa si falta facturar un hito o si el gasto se pasó.',
                                      style: TextStyle(fontWeight: FontWeight.w700, color: over ? Brand.bad : Brand.warn),
                                    ),
                                  );
                                }),
                                if (o.margin != null)
                                  Text('Margen ${(o.margin! * 100).round()} %', style: TextStyle(fontWeight: FontWeight.w800, color: o.margin! < 0.1 ? Brand.bad : o.margin! < 0.25 ? Brand.warn : Brand.ok)),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(onPressed: () => _assign(o), icon: const Icon(Icons.add_link_rounded), label: const Text('Asignar gasto o subcontratista')),
                                ),
                              ]),
                            ),
                          ),
                      ]),
      );
}
