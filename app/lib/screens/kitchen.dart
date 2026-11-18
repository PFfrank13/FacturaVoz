// Carta QR y comandas (Fase 8 · módulo 12): los pedidos de la carta digital (por mesa, recojo o delivery) llegan
// EN VIVO a esta pantalla; cocina los mueve Nuevo → Preparando → Listo → Entregado. Incluye la hoja de QR por mesa.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models_v2.dart';
import '../services/live.dart';
import '../services/growth_repo.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/design_tokens.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show shortDateTime;
import '../logic/tables.dart';
import '../services/print/kitchen_print.dart';
import 'pos.dart';
import 'quotes.dart';

const _flow = ['nuevo', 'preparando', 'listo', 'entregado'];
const _labels = {'nuevo': 'Nuevos', 'preparando': 'Preparando', 'listo': 'Listos', 'entregado': 'Entregado'};
const _colors = {'nuevo': Brand.bad, 'preparando': Brand.warn, 'listo': Brand.ok};

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  List<KitchenOrder>? _orders;
  String? _error;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _debounce;
  int _known = 0;
  String _view = 'comandas'; // comandas | mesas

  @override
  void initState() {
    super.initState();
    _orders = LiveCache.get<List<KitchenOrder>>('kitchen.orders');
    _known = _orders?.where((o) => o.status == 'nuevo').length ?? 0;
    _load();
    try {
      _sub = V2Repo.watchQuotes().listen((_) => _soon(), onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    try {
      final r = await V2Repo.kitchen();
      LiveCache.put('kitchen.orders', r);
      if (!mounted) return;
      final nuevos = r.where((o) => o.status == 'nuevo').length;
      if (_orders != null && nuevos > _known) Haptics.heavy(); // pedido nuevo: vibra
      _known = nuevos;
      setState(() {
        _orders = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  Future<void> _advance(KitchenOrder o) async {
    final i = _flow.indexOf(o.status);
    if (i < 0 || i + 1 >= _flow.length) return;
    Haptics.soft();
    try {
      await V2Repo.setKitchenStatus(o.id, _flow[i + 1]);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(V2Repo.missingHint(e))));
    }
  }

  Future<void> _qrSheet() async {
    final count = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR para las mesas'),
        content: TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '¿Cuántas mesas?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear PDF')),
        ],
      ),
    );
    final n = (int.tryParse(count.text.trim()) ?? 0).clamp(1, 60);
    disposeAfterClose([count]);
    if (ok != true) return;
    final store = await GrowthRepo.loadStore();
    if (!mounted) return;
    if (store.slug.isEmpty || !store.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primero activa tu tienda/carta en Tienda en línea (modo "Carta").')));
      return;
    }
    final name = AppState.instance.activeOrg?.name ?? 'Nuestra carta';
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Wrap(spacing: 18, runSpacing: 18, children: [
          for (var m = 1; m <= n; m++)
            pw.Container(
              width: 160,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
              child: pw.Column(children: [
                pw.Text(name, maxLines: 1, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.SizedBox(height: 6),
                pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: '${GrowthRepo.storeUrl(store.slug)}?mesa=$m', width: 120, height: 120),
                pw.SizedBox(height: 6),
                pw.Text('MESA $m', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                pw.Text('Escanea, mira la carta y pide', style: const pw.TextStyle(fontSize: 8)),
              ]),
            ),
        ]),
      ],
    ));
    await Printing.layoutPdf(name: 'qr-mesas.pdf', onLayout: (_) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final orders = _orders ?? const <KitchenOrder>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cocina y mesas'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(55),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'comandas', label: Text('Comandas')),
                ButtonSegment(value: 'mesas', label: Text('Mesas')),
              ],
              selected: {_view},
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
          ),
        ),
        actions: [
        IconButton(tooltip: 'QR de mesas', onPressed: _qrSheet, icon: const Icon(Icons.qr_code_2_rounded)),
        IconButton(tooltip: 'Todos los pedidos', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuotesScreen())), icon: const Icon(Icons.list_alt_rounded)),
      ]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _orders == null
              ? const SkeletonList()
              : orders.isEmpty
                  ? const EmptyState(title: 'Cocina libre', body: 'Los pedidos de caja y carta QR aparecerán aquí al instante.')
                  : _view == 'mesas'
                      ? _tablesView(context, orders)
                      : LayoutBuilder(builder: (context, c) {
                      final wide = c.maxWidth > 700;
                      final cols = [
                        for (final st in const ['nuevo', 'preparando', 'listo'])
                          _column(context, st, orders.where((o) => o.status == st).toList(), wide ? (c.maxWidth - 32) / 3 : 290),
                      ];
                      return wide
                          ? Padding(padding: const EdgeInsets.all(8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: cols))
                          : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: cols);
                    }),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PosScreen(tableMode: true)));
            if (mounted) _load();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tomar pedido'),
        ),
      ),
      bottomNavigationBar: _orders == null ? null : Padding(padding: const EdgeInsets.all(10), child: Text('En vivo · toca un pedido para pasarlo al siguiente paso', textAlign: TextAlign.center, style: t.textTheme.bodySmall)),
    );
  }

  /// Imprime la comanda de un pedido que llegó (carta QR) para pegarla o pasarla a la cocina.
  Future<void> _printOrder(KitchenOrder o) async {
    try {
      await printComanda(ComandaData(
        table: o.table,
        waiter: Access.instance.displayName,
        order: o.number,
        date: o.createdAt == null ? nowText() : nowText(o.createdAt),
        note: o.notes,
        lines: [for (final it in o.items) ComandaLine(it.quantity, it.description, it.note)],
      ));
      if (mounted) showSuccess(context, 'Comanda impresa', icon: Icons.print_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is StateError ? e.message : 'No se pudo imprimir. ${friendly(e)}')));
    }
  }

  Widget _tablesView(BuildContext context, List<KitchenOrder> orders) {
    final t = Theme.of(context);
    final tables = summarizeTables(orders);
    final sin = openWithoutTable(orders);
    if (tables.isEmpty) {
      return EmptyState(title: 'Sin mesas ocupadas', body: sin > 0 ? 'Hay $sin pedido(s) para llevar o delivery en Comandas.' : 'Cuando un cliente pida desde el QR de su mesa, la verás aquí.');
    }
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return ListView(padding: const EdgeInsets.all(Gap.lg), children: [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: Gap.md, crossAxisSpacing: Gap.md, mainAxisExtent: 128 * scale.clamp(1.0, 1.6)),
        itemCount: tables.length,
        itemBuilder: (_, i) {
          final m = tables[i];
          final c = _colors[m.stage] ?? Brand.indigo;
          final atrasada = m.wait.inMinutes >= 20 && m.stage != 'listo';
          return SoftCard(
            padding: const EdgeInsets.all(Gap.md),
            radius: Radii.lg,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                PulseDot(color: c),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text('Mesa ${m.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: Gap.xs),
              Text('${m.items} plato${m.items == 1 ? '' : 's'} · ${m.orders} pedido${m.orders == 1 ? '' : 's'}', style: t.textTheme.bodySmall),
              const Spacer(),
              Row(children: [
                Expanded(child: Text(waitText(m.wait), style: t.textTheme.labelMedium?.copyWith(color: atrasada ? Brand.bad : null, fontWeight: atrasada ? FontWeight.w800 : null))),
                TagChip(_labels[m.stage] ?? m.stage, color: c),
              ]),
            ]),
          );
        },
      ),
      if (sin > 0) Padding(padding: const EdgeInsets.only(top: Gap.lg), child: Text('Además hay $sin pedido(s) para llevar o delivery en Comandas.', style: t.textTheme.bodySmall)),
    ]);
  }

  Widget _column(BuildContext context, String st, List<KitchenOrder> list, double width) {
    final t = Theme.of(context);
    final c = _colors[st] ?? Brand.indigo;
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(FvTokens.cardRadius),
        border: Border.all(color: c.withValues(alpha: .28)),
        boxShadow: FvTokens.shadow(t.brightness),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            PulseDot(color: c),
            const SizedBox(width: 8),
            Text('${_labels[st]} (${list.length})', style: t.textTheme.titleSmall),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final o in list)
              Reveal(
                key: ValueKey('${o.id}-${o.status}'),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: () => _advance(o),
                    child: SoftCard(
                      padding: const EdgeInsets.all(12),
                      radius: 18,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              o.table.isNotEmpty ? 'Mesa ${o.table}' : (o.fulfillment == 'delivery' ? 'Delivery' : 'Para llevar'),
                              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (o.createdAt != null) Text(shortDateTime(o.createdAt!).split(' ').last, style: t.textTheme.labelSmall),
                          IconButton(tooltip: 'Imprimir comanda', visualDensity: VisualDensity.compact, onPressed: () => _printOrder(o), icon: const Icon(Icons.print_rounded, size: 20)),
                        ]),
                        if (o.client.isNotEmpty) Text(o.client, style: t.textTheme.bodySmall),
                        const Divider(),
                        for (final it in o.items) Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${it.quantity == it.quantity.roundToDouble() ? it.quantity.toInt() : it.quantity} × ${it.description}', style: t.textTheme.bodyLarge),
                            if (it.note.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12, bottom: 4), child: Text('Nota: ${it.note}', style: t.textTheme.bodySmall)),
                          ],
                        ),
                        if (o.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('📝 ${o.notes}', style: t.textTheme.bodySmall)),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TagChip('→ ${_labels[_flow[_flow.indexOf(o.status) + 1]]}', color: c),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
