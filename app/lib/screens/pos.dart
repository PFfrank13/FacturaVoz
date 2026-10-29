// Venta rápida / caja (POS): toca productos o escanea su código de barras, aplica el mejor precio vigente
// (por mayor, promociones) y un cupón, y pasa a la boleta/factura para emitir e imprimir el ticket.
import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../logic/pricing.dart';
import '../models.dart';
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
  const PosScreen({super.key});

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

  String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';
  double get _rate => AppState.instance.profile?.taxRate ?? 18;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Repo.listProducts(activeOnly: true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Venta rápida'), actions: [
        IconButton(tooltip: 'Escanear código', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
        if (Access.instance.has('precios')) IconButton(tooltip: 'Cupón', onPressed: _applyCoupon, icon: Icon(Icons.local_offer_rounded, color: _coupon != null ? Brand.ok : null)),
      ]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _products == null
              ? const SkeletonList()
              : Column(children: [
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
                        ? const EmptyState(title: 'Sin productos', body: 'Agrega tus productos (con precio y, si quieres, código de barras y foto) en Productos.')
                        : LayoutBuilder(builder: (context, c) {
                            final cols = (c.maxWidth / 150).floor().clamp(2, 6);
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final p = list[i];
                                final n = _cart[p.id] ?? 0;
                                final img = _extra[p.id]?['image_path'] as String?;
                                final pr = _price(p, n == 0 ? 1 : n);
                                return Pressable(
                                  onTap: () => _add(p),
                                  onLongPress: n > 0 ? () => _add(p, -1) : null,
                                  child: AnimatedContainer(
                                    duration: Motion.d(context, Motion.fast),
                                    decoration: BoxDecoration(
                                      color: t.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: n > 0 ? t.colorScheme.primary : t.colorScheme.outline, width: n > 0 ? 2 : 1),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                      Expanded(
                                        child: Stack(children: [
                                          Positioned.fill(
                                            child: img == null || img.isEmpty
                                                ? Container(
                                                    decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(17))),
                                                    child: Icon(p.isService ? Icons.handyman_rounded : Icons.shopping_basket_rounded, color: t.colorScheme.primary, size: 34),
                                                  )
                                                : ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(17)), child: StorageImage(path: img)),
                                          ),
                                          if (n > 0)
                                            Positioned(
                                              right: 6,
                                              top: 6,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(99)),
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${qtyText(count)} ${count == 1 ? 'producto' : 'productos'}${_coupon != null ? ' · cupón ${_coupon!.code}' : ''}', style: t.textTheme.bodySmall),
                        Money(money(totals.total, _cur), size: 22, weight: FontWeight.w800),
                      ]),
                    ),
                    TextButton(onPressed: () => setState(() => _cart.clear()), child: const Text('Vaciar')),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: _checkout,
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
