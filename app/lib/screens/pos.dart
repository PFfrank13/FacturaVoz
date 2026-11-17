// Venta rápida / caja (POS): toca productos o escanea su código de barras, aplica el mejor precio vigente
// (por mayor, promociones) y un cupón, y pasa a la boleta/factura para emitir e imprimir el ticket.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../logic/pricing.dart';
import '../logic/pos_kitchen.dart';
import '../logic/sample_catalog.dart';
import '../models.dart';
import '../services/live.dart';
import '../services/print/kitchen_print.dart';
import '../services/print/ticket_printer.dart' show TicketLine;
import '../services/repo.dart';
import '../services/pending_checkout.dart';
import '../services/pos_cart_draft.dart';
import '../services/v2_repo.dart';
import '../ui/barcode_scanner.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ui/retail_visual.dart';
import 'client_profile.dart' show StorageImage;
import 'invoice_detail.dart';
import 'pos_payment.dart';
import 'pos_payment_success.dart';
import 'pos_cart_review.dart';
import 'new_invoice.dart';
import 'products.dart';
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
  String? _chargeRequestId; // Preserve across timeout/retry to avoid duplicate invoice/payment.
  String? _chargeMethod;
  PendingCheckout? _pendingCheckout;
  bool _recoveringCheckout = true;
  String? _checkoutRecoveryError;
  String? _sessionOrg;
  String? _sessionUser;
  bool _restoringCart = true;
  String? _cartStorageError;
  Future<void> _cartWrite = Future<void>.value();

  Future<void> _restoreCart() async {
    final org = Repo.activeOrgId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (mounted) {
      setState(() {
        _restoringCart = true;
        _cartStorageError = null;
      });
    }
    try {
      if (org == null || uid == null) {
        throw const FormatException('Selecciona la empresa e inicia sesión.');
      }
      await _cartWrite.catchError((Object _) {});
      final draft = await PosCartStore.load(uid, org);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != uid) {
        return;
      }
      setState(() {
        _cart..clear()..addAll(draft?.quantities ?? const <String, double>{});
        _notes..clear()..addAll(draft?.notes ?? const <String, String>{});
        _table.text = draft?.table ?? '';
        _coupon = draft?.couponCode != null && draft?.couponKind != null &&
                draft?.couponValue != null
            ? (code: draft!.couponCode!, kind: draft.couponKind!, value: draft.couponValue!)
            : null;
        _cartStorageError = null;
      });
    } catch (e) {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == uid) {
        setState(() => _cartStorageError =
            'No se pudo recuperar el carrito. No se sobrescribirá el respaldo: $e');
      }
    } finally {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == uid) {
        setState(() => _restoringCart = false);
      }
    }
  }

  Future<void> _queueCartSave() {
    if (_restoringCart || _cartStorageError != null) return Future<void>.value();
    final org = Repo.activeOrgId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (org == null || uid == null) return Future<void>.value();
    final coupon = _coupon;
    final draft = PosCartDraft(
      orgId: org, userId: uid,
      quantities: Map<String, double>.of(_cart),
      notes: Map<String, String>.of(_notes),
      table: _table.text,
      couponCode: coupon?.code,
      couponKind: coupon?.kind,
      couponValue: coupon?.value,
    );
    // Ordered snapshots ensure a slow earlier storage write cannot win.
    _cartWrite = _cartWrite.catchError((Object _) {}).then((_) => PosCartStore.save(draft));
    _cartWrite.catchError((Object e) {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == uid) {
        setState(() => _cartStorageError =
            'Error guardando el ticket abierto. No cobres sin revisar el almacenamiento: $e');
      }
    });
    return _cartWrite;
  }

  void _onTableChanged() { _queueCartSave(); }

  Future<void> _clearStoredCart(String uid, String org) async {
    await _cartWrite.catchError((Object _) {});
    await PosCartStore.clear(userId: uid, orgId: org);
  }

  void _onSessionContext() {
    final nextOrg = Repo.activeOrgId;
    final nextUser = Supabase.instance.client.auth.currentUser?.id;
    if (_sessionOrg == nextOrg && _sessionUser == nextUser) return;
    _sessionOrg = nextOrg;
    _sessionUser = nextUser;
    // A retained tab must not show company A's products/checkout under company B.
    // The original encrypted pending request is kept under its own user/org key.
    setState(() {
      // Suppress table-field listeners before clearing the old tenant's UI.
      _restoringCart = true;
      _cart.clear();
      _notes.clear();
      _coupon = null;
      _q.clear();
      _table.clear();
      _products = null;
      _extra = const {};
      _promos = const [];
      _error = null;
      _chargeRequestId = null;
      _chargeMethod = null;
      _pendingCheckout = null;
      _recoveringCheckout = true;
      _checkoutRecoveryError = null;
      _cartStorageError = null;
      _restoringCart = true;
      _kitchenRequestId = null;
      _savedOrderId = null;
      _savedOrderNumber = null;
    });
    _restoreCheckout();
    _restoreCart();
    _load();
  }
  bool _seeding = false;
  bool _savingOrder = false;
  String? _kitchenRequestId; // Se conserva si la red falla para no duplicar pedidos.
  String? _savedOrderId;
  String? _savedOrderNumber;

  String get _cur => AppState.instance.profile?.currency.isNotEmpty == true ? AppState.instance.profile!.currency : 'PEN';
  double get _rate => AppState.instance.profile?.taxRate ?? 18;

  @override
  void initState() {
    super.initState();
    _sessionOrg = Repo.activeOrgId;
    _sessionUser = Supabase.instance.client.auth.currentUser?.id;
    AppState.instance.addListener(_onSessionContext);
    _table.addListener(_onTableChanged);
    _products = LiveCache.get<List<Product>>('pos.products.${Repo.activeOrgId}') ?? _products;
    _load();
    _restoreCheckout();
    _restoreCart();
  }

  Future<void> _restoreCheckout() async {
    final org = Repo.activeOrgId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      if (org == null || uid == null) throw const FormatException('Selecciona una empresa e inicia sesión.');
      final pending = await PendingCheckoutStore.load(userId: uid, orgId: org);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != uid) {
        return;
      }
      setState(() {
        _pendingCheckout = pending;
        _chargeRequestId = pending?.requestId;
        _chargeMethod = pending?.method;
        _checkoutRecoveryError = null;
      });
    } catch (e) {
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != uid) {
        return;
      }
      setState(() => _checkoutRecoveryError = 'No se pudo verificar si existe un cobro pendiente: $e');
    } finally {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == uid) {
        setState(() => _recoveringCheckout = false);
      }
    }
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onSessionContext);
    _table.removeListener(_onTableChanged);
    _q.dispose();
    _focus.dispose();
    _table.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final org = Repo.activeOrgId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      final p = await Repo.listProducts(activeOnly: true);
      if (org == Repo.activeOrgId && uid == Supabase.instance.client.auth.currentUser?.id) {
        LiveCache.put('pos.products.$org', p);
      }
      final e = await V2Repo.productExtras();
      List<Promo> promos = const [];
      if (Access.instance.has('precios')) {
        try {
          promos = await V2Repo.promotions();
        } catch (_) {}
      }
      if (mounted && org == Repo.activeOrgId &&
          uid == Supabase.instance.client.auth.currentUser?.id) {
        setState(() {
          _products = p;
          _extra = e;
          _promos = promos;
        });
      }
    } catch (e) {
      if (mounted && org == Repo.activeOrgId &&
          uid == Supabase.instance.client.auth.currentUser?.id) {
        setState(() => _error = friendly(e));
      }
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
    if (_recoveringCheckout || _restoringCart || _cartStorageError != null ||
        _checkoutRecoveryError != null || _chargeRequestId != null || _charging) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirma el cobro pendiente antes de modificar el carrito.')));
      return;
    }
    if (_restaurant && (_kitchenRequestId != null || _savingOrder)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este pedido ya se guardó en Comandas. Pulsa Nuevo pedido para agregar más platos.')));
      return;
    }
    Haptics.tap();
    setState(() {
      final q = (_cart[p.id] ?? 0) + n;
      if (q <= 0) {
        _cart.remove(p.id);
        _notes.remove(p.id);
      } else {
        _cart[p.id] = q;
      }
    });
    _queueCartSave();
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
    if (_recoveringCheckout || _checkoutRecoveryError != null || _chargeRequestId != null || _charging) return; // No changes while a checkout may have committed.
    if (_restaurant && (_kitchenRequestId != null || _savingOrder)) return;
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
      _queueCartSave();
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
      out.add(LineItem(description: pr.reason.isEmpty ? p.name : '${p.name} (${pr.reason})', quantity: e.value, unitPrice: pr.unitPrice, productId: p.id));
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

  /// Guardado real en Supabase ANTES de imprimir. La misma requestId se reusa
  /// en reintentos para que una caída de red no duplique la comanda.
  Future<bool> _persistKitchenOrder() async {
    if (!_restaurant || _cart.isEmpty || _chargeRequestId != null || _charging || _recoveringCheckout || _checkoutRecoveryError != null) return false;
    if (_savedOrderId != null) return true;
    if (_savingOrder) return false;
    setState(() => _savingOrder = true);
    try {
      final lines = _lines();
      final items = <KitchenDraftItem>[];
      var index = 0;
      for (final e in _cart.entries) {
        final p = _products?.where((x) => x.id == e.key).firstOrNull;
        if (p == null) continue;
        final line = lines[index++];
        items.add(KitchenDraftItem(
          description: line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          note: _notes[p.id] ?? '',
        ));
      }
      if (items.isEmpty) throw AppException('No hay productos para guardar.');
      final requestId = _kitchenRequestId ??= newKitchenRequestId();
      final saved = await V2Repo.createPosKitchenOrder(
        requestId: requestId,
        table: _table.text,
        taxRate: _rate,
        currency: _cur,
        items: items.map((it) => it.toJson()).toList(),
      );
      if (!mounted) return false;
      setState(() {
        _savedOrderId = saved.id;
        _savedOrderNumber = saved.number;
      });
      AppState.instance.bump();
      showSuccess(context, 'Pedido ${saved.number} guardado en Comandas', icon: Icons.check_circle_rounded);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          V2Repo.missing(e) ? 'Falta ejecutar 20261122_v31_comandas_caja_persistentes.sql en Supabase.' : 'No se guardó el pedido: ${friendly(e)}',
        )));
      }
      return false;
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  void _newKitchenOrder() {
    if (_savingOrder || _charging || _chargeRequestId != null || _recoveringCheckout || _checkoutRecoveryError != null) return;
    // Si hubo timeout, el servidor pudo guardar la comanda aunque no llegara
    // la respuesta. Obliga a reintentar la MISMA requestId antes de empezar otra.
    if (_kitchenRequestId != null && _savedOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirma este pedido reintentando Comanda. No crees otro pedido: podría duplicarse.')));
      return;
    }
    setState(() {
      _cart.clear();
      _notes.clear();
      _coupon = null;
      _table.clear();
      _kitchenRequestId = null;
      _savedOrderId = null;
      _savedOrderNumber = null;
    });
    _queueCartSave();
  }

  Future<void> _printComanda() async {
    if (!await _persistKitchenOrder()) return;
    try {
      await printComanda(ComandaData(
        table: _table.text,
        waiter: Access.instance.displayName,
        date: nowText(),
        order: _savedOrderNumber ?? '',
        lines: _comandaLines(),
      ));
      if (mounted) showSuccess(context, 'Comanda impresa · ${_savedOrderNumber ?? ''}', icon: Icons.restaurant_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pedido guardado en Comandas; impresión fallida: ${friendly(e)}')));
    }
  }

  Future<void> _printPrecuenta() async {
    if (!await _persistKitchenOrder()) return;
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
      if (mounted) showSuccess(context, 'Precuenta impresa · ${_savedOrderNumber ?? ''}', icon: Icons.receipt_long_rounded);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pedido guardado en Comandas; precuenta no impresa: ${friendly(e)}')));
    }
  }

  /// Detalle del pedido: cantidades, nota por producto y (restaurante) comanda y precuenta.
  Future<void> _cartSheet() async {
    if (_recoveringCheckout || _checkoutRecoveryError != null || _chargeRequestId != null || _charging) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cobro pendiente de confirmación. Reintenta antes de editar el pedido.')));
      return;
    }
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
            if (_restaurant && _savedOrderId != null)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Guardado en Comandas: ${_savedOrderNumber ?? ''}. Para agregar platos, inicia un pedido nuevo.', style: t.textTheme.bodySmall)),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final e in _cart.entries)
                  if (_products?.where((x) => x.id == e.key).firstOrNull case final p?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(p.name, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                          IconButton(tooltip: 'Quitar uno', onPressed: _kitchenRequestId != null || _savingOrder ? null : () { _add(p, -1); setS(() {}); if (_cart.isEmpty) Navigator.pop(ctx); }, icon: const Icon(Icons.remove_circle_outline_rounded)),
                          Text(qtyText(e.value), style: t.textTheme.titleMedium),
                          IconButton(tooltip: 'Agregar uno', onPressed: _kitchenRequestId != null || _savingOrder ? null : () { _add(p); setS(() {}); }, icon: const Icon(Icons.add_circle_outline_rounded)),
                        ]),
                        TextFormField(
                          initialValue: _notes[p.id] ?? '',
                          enabled: _kitchenRequestId == null && !_savingOrder,
                          maxLength: 200,
                          onChanged: (v) { _notes[p.id] = v; _queueCartSave(); },
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
                Expanded(child: OutlinedButton.icon(onPressed: _savingOrder ? null : () async { await _printComanda(); if (ctx.mounted) setS(() {}); }, icon: const Icon(Icons.restaurant_rounded), label: Text(_savedOrderId == null ? 'Comanda' : 'Reimprimir'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: _savingOrder ? null : () async { await _printPrecuenta(); if (ctx.mounted) setS(() {}); }, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Precuenta'))),
              ]),
            if (_restaurant) const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: _savingOrder ? null : () {
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

  /// Review the complete cart as a separate screen before choosing payment.
  /// Changes use the existing guarded, persisted cart methods.
  Future<void> _reviewRetailCart() async {
    final org = Repo.activeOrgId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (_recoveringCheckout || _restoringCart || _cartStorageError != null ||
        _checkoutRecoveryError != null || _chargeRequestId != null || _charging) {
      return;
    }
    if (_lines().isEmpty) return;
    final approved = await Navigator.of(context).push<RetailCartAction>(
      MaterialPageRoute<RetailCartAction>(
        builder: (_) => PosCartReviewScreen(
          lines: _lines,
          productImages: _extra.map((id, value) =>
              MapEntry(id, (value['image_path'] ?? '').toString())),
          currency: _cur,
          taxRate: _rate,
          canSellOnCredit: Access.instance.has('fiados') && Access.instance.can('sell'),
          onChangeQuantity: (id, amount) {
            final p = _products?.where((x) => x.id == id).firstOrNull;
            if (p != null) _add(p, amount.toDouble());
          },
        ),
      ),
    );
    if (!mounted || Repo.activeOrgId != org ||
        Supabase.instance.client.auth.currentUser?.id != uid) {
      return;
    }
    if (approved == RetailCartAction.collect) {
      await _chargeSheet();
    } else if (approved == RetailCartAction.credit) {
      await _checkout(credit: true);
    }
  }

  /// Four-stage mobile POS: basket → method → verified payment → receipt.
  Future<void> _chargeSheet() async {
    if (_recoveringCheckout || _restoringCart || _cartStorageError != null ||
        _checkoutRecoveryError != null || _chargeRequestId != null || _charging) { return; }
    final org = Repo.activeOrgId;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final currency = _cur;
    final taxRate = _rate;
    final lines = _lines();
    if (lines.isEmpty) { return; }
    final total = computeTotals(lines, taxRate).total;
    final approval = await choosePosPayment(context, currency: currency, total: total, items: lines);
    if (!mounted || approval == null || Repo.activeOrgId != org ||
        Supabase.instance.client.auth.currentUser?.id != uid) {
      return;
    }
    final current = _lines();
    final unchanged = current.length == lines.length &&
        _cur == currency && _rate == taxRate &&
        List.generate(lines.length, (i) => i).every((i) =>
          lines[i].productId == current[i].productId &&
          lines[i].quantity == current[i].quantity &&
          lines[i].unitPrice == current[i].unitPrice &&
          lines[i].description == current[i].description);
    if (!unchanged) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El carrito o la moneda cambió durante el cobro. Revisa el importe antes de confirmar.'),
      ));
      return;
    }
    await _fastCharge(approval.method, paymentEvidence: approval.note);
  }

  Future<void> _fastCharge(String method, {String? paymentEvidence}) async {
    // An immutable pending charge must be recoverable even if its unrelated
    // editable cart backup is damaged. Never allow a NEW charge in that case.
    if (_charging || _recoveringCheckout || _restoringCart ||
        (_cartStorageError != null && _pendingCheckout == null) ||
        _checkoutRecoveryError != null) {
      return;
    }
    if (_chargeMethod != null && _chargeMethod != method) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reintenta con el mismo método del primer cobro para evitar diferencias.')));
      return;
    }
    // A recovered checkout is immutable. Its payload, method and request ID
    // must be reused exactly even when the current catalog or cart changed.
    final recovering = _pendingCheckout != null;
    if (!recovering && _restaurant && !await _persistKitchenOrder()) return;
    if (!mounted) return;
    final pending = _pendingCheckout;
    final lines = recovering ? pending!.items : _lines();
    if (lines.isEmpty) return;
    setState(() => _charging = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final org = Repo.activeOrgId;
      if (uid == null || org == null) throw AppException('Sesión o empresa no válida.');
      final checkout = pending ?? PendingCheckout(
        orgId: org,
        userId: uid,
        requestId: Repo.newRequestId(),
        method: method,
        taxRate: _rate,
        currency: _cur,
        notes: [
          if (_table.text.trim().isNotEmpty) 'Mesa ${_table.text.trim()}',
          if (_coupon != null) 'Cupón ${_coupon!.code}',
          if (paymentEvidence != null) paymentEvidence,
        ].join(' · '),
        items: lines,
      );
      if (checkout.orgId != org || checkout.userId != uid || checkout.method != method) {
        throw AppException('El cobro pertenece a otra empresa, cuenta o método.');
      }
      // Commit the immutable local snapshot BEFORE any remote money mutation.
      if (!recovering) {
        await PendingCheckoutStore.save(checkout);
      }
      if (!mounted) return;
      setState(() {
        _pendingCheckout = checkout;
        _chargeRequestId = checkout.requestId;
        _chargeMethod = checkout.method;
      });
      final id = await Repo.fastCheckoutAtomic(
        draft: checkout.toDraft(), method: checkout.method, requestId: checkout.requestId,
      );
      // PostgreSQL confirmed the transaction. Never clear a pending key before this response.
      String? kitchenLinkError;
      if (_restaurant && _savedOrderId != null) {
        try {
          await V2Repo.linkPosKitchenInvoice(_savedOrderId!, id);
        } catch (e) {
          kitchenLinkError = friendly(e);
        }
      }
      // Remove editable draft before the immutable checkout recovery key.
      // A crash between these deletes can only replay the same idempotent sale.
      await _clearStoredCart(checkout.userId, checkout.orgId);
      await PendingCheckoutStore.clear(checkout);
      AppState.instance.bump();
      if (!mounted || Repo.activeOrgId != checkout.orgId ||
          Supabase.instance.client.auth.currentUser?.id != checkout.userId) {
        return;
      }
      setState(() {
        _cart.clear();
        _notes.clear();
        _coupon = null;
        _pendingCheckout = null;
        _chargeRequestId = null;
        _chargeMethod = null;
        if (_restaurant) {
          _table.clear();
          _savedOrderId = null;
          _savedOrderNumber = null;
          _kitchenRequestId = null;
        }
      });
      if (kitchenLinkError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Venta cobrada, pero no se pudo vincular a la comanda: $kitchenLinkError')));
      }
      if (Access.instance.rubro == 'bodega') {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PosPaymentSuccessScreen(
            invoiceId: id, method: checkout.method, currency: checkout.currency,
            total: computeTotals(checkout.items, checkout.taxRate).total,
          ),
        ));
      } else {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true, autoPrint: true),
        ));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : 'Cobro sin confirmar. Reintenta con el mismo método; si el servidor ya lo registró no creará una venta duplicada. ${friendly(e)}')));
    } finally {
      if (mounted) setState(() => _charging = false);
    }
  }

  Future<void> _checkout({bool credit = false}) async {
    if (_recoveringCheckout || _restoringCart || _cartStorageError != null ||
        _checkoutRecoveryError != null || _chargeRequestId != null || _charging) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primero confirma o recupera el cobro rápido pendiente.')));
      return;
    }
    if (_restaurant && !await _persistKitchenOrder()) return;
    if (!mounted) return;
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
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewInvoiceScreen(initial: draft, startAsCredit: credit)));
    AppState.instance.bump();
    if (id != null && mounted) {
      if (_restaurant && _savedOrderId != null) {
        try {
          await V2Repo.linkPosKitchenInvoice(_savedOrderId!, id);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Venta creada; fallo al vincular la comanda: ${friendly(e)}')));
        }
      }
      if (!mounted) return;
      await _clearStoredCart(
        Supabase.instance.client.auth.currentUser?.id ?? '',
        Repo.activeOrgId ?? '',
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _coupon = null;
        _notes.clear();
        if (_restaurant) {
          _table.clear();
          _savedOrderId = null;
          _savedOrderNumber = null;
          _kitchenRequestId = null;
        }
      });
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final retail = Access.instance.rubro == 'bodega';
    // El POS no redefine el tema del usuario: se integra al unico shell.
    final t = Theme.of(context);
    final all = _products ?? const <Product>[];
    final cats = {for (final x in _extra.values) if ((x['category'] ?? '').toString().isNotEmpty) x['category'].toString()}.toList()..sort();
    final q = _q.text.trim().toLowerCase();
    final list = all.where((p) => (q.isEmpty || p.name.toLowerCase().contains(q) || (_extra[p.id]?['barcode'] ?? '').toString().contains(q)) && (_cat.isEmpty || _extra[p.id]?['category'] == _cat)).toList();
    final lines = _lines();
    final totals = computeTotals(lines, _rate);
    final count = _cart.values.fold(0.0, (a, b) => a + b);
    final actions = <Widget>[
      if (retail) IconButton(tooltip: 'Venta con cliente, factura o crédito', onPressed: _checkout, icon: const Icon(Icons.receipt_long_rounded)),
      if (retail && Access.instance.has('stock') && Access.instance.can('products_edit'))
        IconButton(
          tooltip: 'Editar catálogo y fotos de productos',
          icon: const Icon(Icons.add_photo_alternate_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ProductsScreen(),
          )),
        ),
      IconButton(tooltip: 'Escanear código', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
      if (Access.instance.has('precios')) IconButton(tooltip: 'Cupón', onPressed: _applyCoupon, icon: Icon(Icons.local_offer_rounded, color: _coupon != null ? Brand.ok : null)),
    ];
    return Theme(data: t, child: Scaffold(
      appBar: widget.embedded ? null : AppBar(
        title: Text(_restaurant ? 'Tomar pedido' : 'Venta rápida'),
        actions: actions,
      ),
      body: (_recoveringCheckout || _restoringCart || _cartStorageError != null ||
              _checkoutRecoveryError != null || _pendingCheckout != null)
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_recoveringCheckout || _restoringCart) const CircularProgressIndicator(),
                if (_recoveringCheckout || _restoringCart) const SizedBox(height: 16),
                Text(_recoveringCheckout || _restoringCart
                    ? 'Recuperando ticket y cobros pendientes…'
                    : _cartStorageError ?? _checkoutRecoveryError ?? 'Hay un cobro pendiente de confirmación.',
                    textAlign: TextAlign.center),
                if (_pendingCheckout case final pending?) ...[
                  const SizedBox(height: 12),
                  Text('Importe y productos conservados del cobro original. No cambies el método de pago.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _charging ? null : () => _fastCharge(pending.method),
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(_charging ? 'Verificando…' : 'Recuperar cobro (${paymentMethods[pending.method] ?? pending.method})'),
                  ),
                ],
                if (_checkoutRecoveryError != null || _cartStorageError != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () { _restoreCheckout(); _restoreCart(); },
                    child: const Text('Reintentar recuperación')),
                ],
              ]),
            ))
          : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _products == null
              ? const SkeletonList()
              : Column(children: [
                  if (retail)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                      child: RetailVisual.journey(step: 1, label: 'Elegir productos'),
                    ),

                  if (widget.embedded && actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                      ),
                    ),
                  if (_restaurant)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(controller: _table, enabled: _kitchenRequestId == null && !_savingOrder, decoration: const InputDecoration(isDense: true, labelText: 'Mesa (vacío = para llevar)', prefixIcon: Icon(Icons.table_restaurant_rounded))),
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
                        ? ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 36), children: [
                            SectorPhotoBanner(
                              rubro: Access.instance.rubro,
                              title: _restaurant ? 'Tu carta, con personalidad' : 'Tu catálogo, con identidad',
                              subtitle: _restaurant ? 'Agrega platos y fotos de tu propia cocina.' : 'Añade productos con fotos reales y precios de tu negocio.',
                            ),
                            const EmptyState(title: 'Tu catálogo empieza aquí', body: 'Agrega tus productos con sus precios y fotos auténticas. Así tus clientes podrán reconocerlos fácilmente.'),
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
                              padding: EdgeInsets.fromLTRB(12, 8, 12, retail && widget.embedded ? 8 : widget.embedded ? 210 : 120),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: MediaQuery.textScalerOf(context).scale(200)),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final p = list[i];
                                final n = _cart[p.id] ?? 0;
                                final img = _extra[p.id]?['image_path'] as String?;
                                final em = tileEmoji(p.name, _extra[p.id]?['category'] as String?);
                                final category = '${p.name} ${_extra[p.id]?['category'] ?? ''}'.toLowerCase();
                                final placeholderIcon =
                                    category.contains('agua') || category.contains('bebida')
                                        ? Icons.water_drop_rounded
                                        : category.contains('arroz') || category.contains('cereal')
                                            ? Icons.grain_rounded
                                            : category.contains('aceite') || category.contains('leche')
                                                ? Icons.local_drink_rounded
                                                : category.contains('limpieza')
                                                    ? Icons.cleaning_services_rounded
                                                    : Icons.inventory_2_rounded;
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
                                                    child: retail
                                                        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                            Icon(placeholderIcon, size: 42, color: const Color(0xFFB49BFF)),
                                                            const SizedBox(height: 7),
                                                            const Text('Foto por añadir', style: TextStyle(
                                                              fontSize: 10, color: Color(0xFFB7B1CE))),
                                                          ])
                                                        : em == null
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
                  if (retail && widget.embedded && lines.isNotEmpty)
                    Container(
                      key: const ValueKey('retail-pos-checkout-bar'),
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 94),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1B214A),
                        border: Border(top: BorderSide(color: Color(0xFF57418E))),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: InkWell(
                            onTap: _reviewRetailCart,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${qtyText(count)} productos · Ver carrito',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFE3D6FF))),
                                Text(money(totals.total, _cur),
                                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.icon(
                          key: const ValueKey('retail-pos-charge'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            backgroundColor: const Color(0xFF9658FA),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _charging || _savingOrder || _chargeRequestId != null
                              ? null : _reviewRetailCart,
                          icon: const Icon(Icons.shopping_cart_checkout_rounded),
                          label: const Text('Cobrar', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                ]),
      bottomNavigationBar: retail && widget.embedded ? null : AnimatedSize(
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
                        onTap: retail ? _reviewRetailCart : _cartSheet,
                         child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${qtyText(count)} ${count == 1 ? 'producto' : 'productos'}${_coupon != null ? ' · cupón ${_coupon!.code}' : ''} · ver detalle', style: t.textTheme.bodySmall),
                          Money(money(totals.total, _cur), size: 22, weight: FontWeight.w800),
                        ]),
                      ),
                    ),
                    TextButton(
                      onPressed: _savingOrder || _charging || _recoveringCheckout ||
                          _restoringCart || _cartStorageError != null ||
                          _checkoutRecoveryError != null || _chargeRequestId != null
                          ? null : (_restaurant ? _newKitchenOrder : () {
                              setState(() {
                                _cart.clear(); _notes.clear(); _coupon = null;
                              });
                              _queueCartSave();
                            }),
                      child: Text(_restaurant && _savedOrderId != null ? 'Nuevo pedido' : (_restaurant && _kitchenRequestId != null ? 'Pendiente' : 'Vaciar')),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: _charging || _savingOrder || _recoveringCheckout ||
                          _restoringCart || _cartStorageError != null ||
                          _checkoutRecoveryError != null || _chargeRequestId != null
                          ? null : (retail ? _reviewRetailCart : _chargeSheet),
                       icon: Icon(retail ? Icons.shopping_cart_checkout_rounded : Icons.point_of_sale_rounded),
                       label: Text(retail ? 'Revisar' : 'Cobrar'),
                    ),
                  ]),
                ),
              ),
      ),
    ));
  }
}

