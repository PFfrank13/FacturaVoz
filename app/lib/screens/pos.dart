// Venta rápida / caja (POS): toca productos o escanea su código de barras, aplica el mejor precio vigente
// (por mayor, promociones) y un cupón, y pasa a la boleta/factura para emitir e imprimir el ticket.
import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../logic/pricing.dart';
import '../logic/sample_catalog.dart';
import '../models.dart';
import '../services/live.dart';
import '../services/print/kitchen_print.dart';
import '../services/print/ticket_printer.dart' show TicketLine;
import '../services/repo.dart';
import '../services/v2_repo.dart';
import '../ui/barcode_scanner.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show StorageImage;
import 'invoice_detail.dart';
import 'new_invoice.dart';
import 'team.dart' show dbMessage;

class PosScreen extends StatefulWidget {
  /// `embedded`: va dentro de la pestaña Vender (sin barra propia, deja espacio para el dock).
  /// `tableMode`: restaurante: pide la mesa e imprime comanda y precuenta.
  const PosScreen({super.key, this.embedded = false, this.tableMode = false});
  final bool embedded;
  final bool tableMode;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Product>? _products;
  Map<String, Map<String, dynamic>> _extra = const {};
  List<Promo> _promos = const [];
  final Map<String, double> _cart = {};
  final _q = TextEditingController();
  final _focus = FocusNode();
  String _cat = '';
  String? _error;
  ({String code, String kind, double value})? _coupon;
  int _shake = 0;
  final Map<String, String> _notes = {}; // nota por producto ("sin cebolla")
  final _table = TextEditingController();
  bool _charging = false;
  bool _seeding = false;

  String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';
  double get _rate => AppState.instance.profile?.taxRate ?? 18;

  @override
  void initState() {
    super.initState();
    _products = LiveCache.get<List<Product>>('pos.products') ?? _products;
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    _table.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Repo.listProducts(activeOnly: true);
      LiveCache.put('pos.products', p);
      final e = await V2Repo.productExtras();
      List<Promo> promos = const [];
      if (Access.instance.has('precios')) {
        try {
          promos = await V2Repo.promotions();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _products = p;
          _extra = e;
          _promos = promos;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  PricedLine _price(Product p, double qty) {
    final x = _extra[p.id];
    return bestPrice(
      productId: p.id,
      listPrice: p.unitPrice,
      qty: qty,
      wholesalePrice: (x?['wholesale_price'] as num?)?.toDouble(),
      wholesaleMinQty: (x?['wholesale_min_qty'] as num?)?.toDouble(),
      promos: _promos,
      today: todayIso(),
    );
  }

  void _add(Product p, [double n = 1]) {
    Haptics.tap();
    setState(() {
      final q = (_cart[p.id] ?? 0) + n;
      if (q <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = q;
      }
    });
  }

  /// Lo escrito en el buscador: si es un código de barras exacto, se agrega solo (sirve con pistola lectora).
  Future<void> _submit(String v) async {
    final code = v.trim();
    if (code.isEmpty) return;
    final byExtra = _extra.entries.where((e) => (e.value['barcode'] ?? '') == code).map((e) => e.key).firstOrNull;
    final p = byExtra == null ? null : _products?.where((x) => x.id == byExtra).firstOrNull;
    if (p != null) {
      _add(p);
      _q.clear();
      setState(() {});
      _focus.requestFocus();
    } else if (RegExp(r'^\d{6,14}$').hasMatch(code)) {
      setState(() => _shake++);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No hay producto con el código $code. Agrégalo en Productos.')));
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code != null) _submit(code);
  }

  Future<void> _applyCoupon() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cupón'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Código')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      ),
    );
    final code = c.text.trim().toUpperCase();
    disposeAfterClose([c]);
    if (ok != true || code.isEmpty) return;
    try {
      final r = await V2Repo.useCoupon(code);
      if (r['kind'] == null) throw AppException('Cupón no válido o vencido.');
      setState(() => _coupon = (code: code, kind: (r['kind'] ?? 'porcentaje') as String, value: ((r['value'] as num?) ?? 0).toDouble()));
      if (mounted) showSuccess(context, 'Cupón $code aplicado', icon: Icons.local_offer_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : dbMessage(e))));
    }
  }

  List<LineItem> _lines() {
    final out = <LineItem>[];
    for (final e in _cart.entries) {
      final p = _products?.where((x) => x.id == e.key).firstOrNull;
      if (p == null) continue;
      final pr = _price(p, e.value);
      out.add(LineItem(description: pr.reason.isEmpty ? p.name : '${p.name} (${pr.reason})', quantity: e.value, unitPrice: pr.unitPrice));
    }
    final c = _coupon;
    if (c != null && out.isNotEmpty) {
      final sub = out.fold(0.0, (s, l) => s + l.amount);
      final disc = couponDiscount(kind: c.kind, value: c.value, subtotal: sub);
      final f = sub <= 0 ? 1.0 : (sub - disc) / sub;
      for (final l in out) {
        l.unitPrice = round2(l.unitPrice * f);
      }
    }
    return out;
  }


  bool get _restaurant => widget.tableMode;

  /// Productos de ejemplo del rubro (solo si el usuario lo pide). Precios referenciales, editables en Productos.
  Future<void> _seedSample() async {
    final rubro = Access.instance.rubro;
    final items = sampleCatalog[rubro];
    if (items == null || _seeding) return;
    setState(() => _seeding = true);
    try {
      for (final it in items) {
        final id = await Repo.saveProduct(name: it.name, unitPrice: it.price, unit: 'NIU');
        await V2Repo.saveProductExtra(id, {'category': it.category}).catchError((_) {});
      }
      AppState.instance.bump();
      await _load();
      if (mounted) showSuccess(context, 'Productos de ejemplo cargados. Edita precios y sube tus fotos en Productos.', icon: Icons.inventory_2_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : dbMessage(e))));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  List<ComandaLine> _comandaLines() => [
        for (final e in _cart.entries)
          if (_products?.where((x) => x.id == e.key).firstOrNull case final p?) ComandaLine(e.value, p.name, _notes[p.id] ?? ''),
      ];

  Future<void> _printComanda() async {
    if (_cart.isEmpty) return;
    try {
      await printComanda(ComandaData(table: _table.text, waiter: Access.instance.displayName, date: nowText(), lines: _comandaLines()));
      if (mounted) showSuccess(context, 'Comanda enviada a cocina', icon: Icons.restaurant_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is StateError ? e.message : 'No se pudo imprimir la comanda. ${friendly(e)}')));
    }
  }

  Future<void> _printPrecuenta() async {
    final p = AppState.instance.profile;
    final lines = _lines();
    if (p == null || lines.isEmpty) return;
    final t = computeTotals(lines, _rate);
    try {
      await printPrecuenta(precuentaData(
        profile: p,
        table: _table.text,
        waiter: Access.instance.displayName,
        currency: _cur,
        lines: [for (final l in lines) TicketLine(l.quantity, l.description, l.unitPrice, l.amount)],
        totals: [('Subtotal', t.subtotal, false), (p.taxLabel.isEmpty ? 'IGV' : p.taxLabel, t.tax, false), ('TOTAL', t.total, true)],
      ));
      if (mounted) showSuccess(context, 'Precuenta impresa', icon: Icons.receipt_long_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is StateError ? e.message : 'No se pudo imprimir la precuenta. ${friendly(e)}')));
    }
  }

  /// Detalle del pedido: cantidades, nota por producto y (restaurante) comanda y precuenta.
  Future<void> _cartSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final t = Theme.of(ctx);
        final lines = _lines();
        final totals = computeTotals(lines, _rate);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_restaurant ? 'Pedido' : 'Venta', style: t.textTheme.titleLarge),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final e in _cart.entries)
                  if (_products?.where((x) => x.id == e.key).firstOrNull case final p?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(p.name, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                          IconButton(tooltip: 'Quitar uno', onPressed: () { _add(p, -1); setS(() {}); if (_cart.isEmpty) Navigator.pop(ctx); }, icon: const Icon(Icons.remove_circle_outline_rounded)),
                          Text(qtyText(e.value), style: t.textTheme.titleMedium),
                          IconButton(tooltip: 'Agregar uno', onPressed: () { _add(p); setS(() {}); }, icon: const Icon(Icons.add_circle_outline_rounded)),
                        ]),
                        TextFormField(
                          initialValue: _notes[p.id] ?? '',
                          onChanged: (v) => _notes[p.id] = v,
                          decoration: const InputDecoration(isDense: true, hintText: 'Nota (ej. sin cebolla, con arroz)', prefixIcon: Icon(Icons.edit_note_rounded)),
                        ),
                      ]),
                    ),
              ]),
            ),
            const Divider(),
            Row(children: [const Expanded(child: Text('Total')), Money(money(totals.total, _cur), size: 20, weight: FontWeight.w800)]),
            const SizedBox(height: 12),
            if (_restaurant)
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _printComanda, icon: const Icon(Icons.restaurant_rounded), label: const Text('Comanda'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: _printPrecuenta, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Precuenta'))),
              ]),
            if (_restaurant) const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: () {
                Navigator.pop(ctx);
                _chargeSheet();
              },
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text('Cobrar'),
            ),
          ]),
        );
      }),
    );
  }

  /// Cobro en un toque: elige cómo paga el cliente y listo (se registra la venta, el cobro y se imprime el ticket).
  Future<void> _chargeSheet() async {
    final lines = _lines();
    if (lines.isEmpty) return;
    final total = computeTotals(lines, _rate).total;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Cobrar', style: t.textTheme.titleLarge),
            const SizedBox(height: 4),
            Money(money(total, _cur), size: 30, weight: FontWeight.w800),
            const SizedBox(height: 12),
            Text('¿Cómo paga?', style: t.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in const ['efectivo', 'yape', 'plin', 'tarjeta', 'transferencia'])
                ActionChip(
                  label: Text(paymentMethods[k]!),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _fastCharge(k);
                  },
                ),
            ]),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _checkout();
              },
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Más opciones (cliente, factura, crédito)'),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _fastCharge(String method) async {
    if (_charging) return;
    final lines = _lines();
    if (lines.isEmpty) return;
    setState(() => _charging = true);
    try {
      final table = _table.text.trim();
      final draft = InvoiceDraft(
        taxRate: _rate,
        currency: _cur,
        items: lines,
        notes: [if (table.isNotEmpty) 'Mesa $table', if (_coupon != null) 'Cupón ${_coupon!.code}'].join(' · '),
        transcript: 'Venta rápida',
      );
      final id = await Repo.createInvoice(draft);
      final total = computeTotals(lines, _rate).total;
      // La base solo acepta cobros sobre una nota "enviada" y la marca "pagada" sola al saldarse.
      await Repo.setStatus(id, 'sent');
      await Repo.addPayment(invoiceId: id, amount: total, method: method);
      AppState.instance.bump();
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _notes.clear();
        _coupon = null;
      });
      // Se abre la venta con el ticket listo para imprimir (y desde ahí se emite la boleta o factura electrónica).
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true, autoPrint: true)));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : 'No se pudo cobrar. ${friendly(e)}')));
    } finally {
      if (mounted) setState(() => _charging = false);
    }
  }

  Future<void> _checkout() async {
    final lines = _lines();
    if (lines.isEmpty) return;
    final p = AppState.instance.profile;
    final draft = InvoiceDraft(
      taxRate: _rate,
      currency: _cur,
      items: lines,
      notes: _coupon == null ? '' : 'Cupón ${_coupon!.code}',
      transcript: p == null ? null : 'Venta rápida',
    );
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewInvoiceScreen(initial: draft)));
    AppState.instance.bump();
    if (id != null && mounted) {
      setState(() {
        _cart.clear();
        _coupon = null;
      });
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = _products ?? const <Product>[];
    final cats = {for (final x in _extra.values) if ((x['category'] ?? '').toString().isNotEmpty) x['category'].toString()}.toList()..sort();
    final q = _q.text.trim().toLowerCase();
    final list = all.where((p) => (q.isEmpty || p.name.toLowerCase().contains(q) || (_extra[p.id]?['barcode'] ?? '').toString().contains(q)) && (_cat.isEmpty || _extra[p.id]?['category'] == _cat)).toList();
    final lines = _lines();
    final totals = computeTotals(lines, _rate);
    final count = _cart.values.fold(0.0, (a, b) => a + b);
    final actions = <Widget>[
      IconButton(tooltip: 'Escanear código', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
      if (Access.instance.has('precios')) IconButton(tooltip: 'Cupón', onPressed: _applyCoupon, icon: Icon(Icons.local_offer_rounded, color: _coupon != null ? Brand.ok : null)),
    ];
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(_restaurant ? 'Tomar pedido' : 'Venta rápida'), actions: actions),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _products == null
              ? const SkeletonList()
              : Column(children: [
                  if (widget.embedded)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 8, 8, 0),
                      child: Row(children: [Expanded(child: Text(_restaurant ? 'Tomar pedido' : 'Vender', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))), ...actions]),
                    ),
                  if (_restaurant)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(controller: _table, decoration: const InputDecoration(isDense: true, labelText: 'Mesa (vacío = para llevar)', prefixIcon: Icon(Icons.table_restaurant_rounded))),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Shake(
                      trigger: _shake,
                      child: TextField(
                        controller: _q,
                        focusNode: _focus,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _submit,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(hintText: 'Busca o pasa el lector de código de barras', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                      ),
                    ),
                  ),
                  if (cats.isNotEmpty)
                    SizedBox(
                      height: 46,
                      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                        Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: const Text('Todo'), selected: _cat.isEmpty, onSelected: (_) => setState(() => _cat = ''))),
                        for (final c in cats) Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c))),
                      ]),
                    ),
                  Expanded(
                    child: all.isEmpty
                        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const EmptyState(title: 'Sin productos', body: 'Agrega tus productos (con precio y, si quieres, código de barras y foto) en Productos.'),
                            if (sampleCatalog.containsKey(Access.instance.rubro))
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: FilledButton.icon(
                                  onPressed: _seeding ? null : _seedSample,
                                  icon: _seeding ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
                                  label: const Text('Cargar productos de ejemplo'),
                                ),
                              ),
                          ])
                        : LayoutBuilder(builder: (context, c) {
                            final cols = (c.maxWidth / 150).floor().clamp(2, 6);
                            return GridView.builder(
                              padding: EdgeInsets.fromLTRB(12, 8, 12, widget.embedded ? 210 : 120),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: MediaQuery.textScalerOf(context).scale(200)),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final p = list[i];
                                final n = _cart[p.id] ?? 0;
                                final img = _extra[p.id]?['image_path'] as String?;
                                final em = tileEmoji(p.name, _extra[p.id]?['category'] as String?);
                                final pr = _price(p, n == 0 ? 1 : n);
                                return Pressable(
                                  onTap: () => _add(p),
                                  onLongPress: n > 0 ? () => _add(p, -1) : null,
                                  child: AnimatedContainer(
                                    duration: Motion.d(context, Motion.fast),
                                    decoration: BoxDecoration(
                                      color: t.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(Radii.lg),
                                      border: Border.all(color: n > 0 ? t.colorScheme.primary : t.colorScheme.outline, width: n > 0 ? 2 : 1),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                      Expanded(
                                        child: Stack(children: [
                                          Positioned.fill(
                                            child: img == null || img.isEmpty
                                                ? Container(
                                                    decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(17))),
                                                    alignment: Alignment.center,
                                                    child: em == null
                                                        ? Icon(p.isService ? Icons.handyman_rounded : Icons.shopping_basket_rounded, color: t.colorScheme.primary, size: 34)
                                                        : Text(em, style: const TextStyle(fontSize: 40)),
                                                  )
                                                : ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(17)), child: StorageImage(path: img)),
                                          ),
                                          if (n > 0)
                                            Positioned(
                                              right: 6,
                                              top: 6,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(Radii.pill)),
                                                child: Text(qtyText(n), style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w800)),
                                              ),
                                            ),
                                          if (p.tracksStock && (p.stock ?? 0) <= 0)
                                            const Positioned(left: 6, top: 6, child: TagChip('Sin stock', color: Brand.bad)),
                                        ]),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
                                          Row(children: [
                                            Money(money(pr.unitPrice, _cur), size: 13, weight: FontWeight.w800),
                                            if (pr.reason.isNotEmpty) ...[const SizedBox(width: 4), const Icon(Icons.local_offer_rounded, size: 14, color: Brand.ok)],
                                          ]),
                                        ]),
                                      ),
                                    ]),
                                  ),
                                );
                              },
                            );
                          }),
                  ),
                ]),
      bottomNavigationBar: AnimatedSize(
        duration: Motion.d(context, Motion.medium),
        curve: Motion.standard,
        child: lines.isEmpty
            ? const SizedBox(width: double.infinity)
            : SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: _cartSheet,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${qtyText(count)} ${count == 1 ? 'producto' : 'productos'}${_coupon != null ? ' · cupón ${_coupon!.code}' : ''} · ver detalle', style: t.textTheme.bodySmall),
                          Money(money(totals.total, _cur), size: 22, weight: FontWeight.w800),
                        ]),
                      ),
                    ),
                    TextButton(onPressed: () => setState(() {
                      _cart.clear();
                      _notes.clear();
                    }), child: const Text('Vaciar')),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: _charging ? null : _chargeSheet,
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: const Text('Cobrar'),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}
