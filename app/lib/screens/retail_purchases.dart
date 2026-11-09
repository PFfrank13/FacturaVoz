import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../services/retail_purchase.dart';
import '../ui/widgets.dart';
import '../ui/retail_visual.dart';
import 'pos_payment_logic.dart';
import 'products.dart';
import 'retail_settlements.dart';

/// Plan Básico: supplier -> product ID -> atomic stock receipt -> expense/cash.
/// This is deliberately online-only until an audited offline ledger exists.
class RetailPurchasesScreen extends StatefulWidget {
  const RetailPurchasesScreen({super.key});

  @override
  State<RetailPurchasesScreen> createState() => _RetailPurchasesScreenState();
}

class _RetailPurchasesScreenState extends State<RetailPurchasesScreen> {
  final _supplier = TextEditingController();
  final _reference = TextEditingController();
  List<Product>? _products;
  List<Map<String, dynamic>> _history = const [];
  final Map<String, RetailPurchaseLine> _lines = {};
  PendingRetailPurchase? _pending;
  String? _error;
  String? _recoveryError;
  bool _recovering = true;
  bool _saving = false;
  String _search = '';
  String _method = 'pendiente';
  String? _activeOrg;
  String? _activeUser;
  int _loadGeneration = 0;
  int _restoreGeneration = 0;

  void _onCompanyChange() {
    final org = Repo.activeOrgId;
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (!mounted || (org == _activeOrg && user == _activeUser)) return;
    _activeOrg = org;
    _activeUser = user;
    _loadGeneration++;
    _restoreGeneration++;
    _supplier.clear();
    _reference.clear();
    setState(() {
      _products = null;
      _history = const [];
      _lines.clear();
      _pending = null;
      _error = null;
      _recoveryError = null;
      _recovering = true;
      _saving = false;
      _search = '';
      _method = 'pendiente';
    });
    _restore();
    _load();
  }

  bool get _allowed => Access.instance.has('stock') && Access.instance.isAdmin;
  String get _currency => AppState.instance.profile?.currency.isNotEmpty == true
      ? AppState.instance.profile!.currency : 'PEN';
  int get _total => _lines.values.fold<int>(0, (sum, item) => sum + item.lineTotalCents);

  @override
  void initState() {
    super.initState();
    _activeOrg = Repo.activeOrgId;
    _activeUser = Supabase.instance.client.auth.currentUser?.id;
    AppState.instance.addListener(_onCompanyChange);
    _restore();
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onCompanyChange);
    _supplier.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    final org = Repo.activeOrgId;
    final generation = ++_restoreGeneration;
    try {
      if (user == null || org == null) throw const FormatException('Inicia sesión y elige una empresa');
      final pending = await RetailPurchaseStore.load(user, org);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != user ||
          generation != _restoreGeneration) return;
      setState(() {
        _pending = pending;
        _recoveryError = null;
      });
    } catch (e) {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == user && generation == _restoreGeneration) {
        setState(() => _recoveryError = 'No se pudo comprobar la compra pendiente: $e');
      }
    } finally {
      if (mounted && Repo.activeOrgId == org &&
          Supabase.instance.client.auth.currentUser?.id == user && generation == _restoreGeneration) {
        setState(() => _recovering = false);
      }
    }
  }

  Future<void> _load() async {
    final org = Repo.activeOrgId;
    final generation = ++_loadGeneration;
    if (!_allowed) return;
    try {
      if (org == null) throw AppException('Selecciona una empresa.');
      final products = await Repo.listProducts(activeOnly: true);
      // A missing receipt table is a missing migration, not an empty history.
      final rows = await Supabase.instance.client
          .from('retail_receipts')
          .select('id, supplier_name, document_ref, payment_method, currency, total_cents, created_at')
          .eq('org_id', org)
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted || Repo.activeOrgId != org || generation != _loadGeneration) return;
      setState(() {
        _products = products.where((p) => !p.isService).toList();
        _history = [for (final row in rows) Map<String, dynamic>.from(row)];
        _error = null;
      });
    } catch (e) {
      if (mounted && Repo.activeOrgId == org && generation == _loadGeneration) {
        setState(() => _error =
          'No se pudo cargar compras. Revisa la migración de recepción en staging. ${friendly(e)}');
      }
    }
  }

  Future<void> _editLine(Product product) async {
    final org = Repo.activeOrgId;
    if (_saving || _recovering || _pending != null || _recoveryError != null) return;
    final existing = _lines[product.id];
    final qty = TextEditingController(text: existing?.quantity.toStringAsFixed(2) ?? '1');
    final cost = TextEditingController(
      text: existing != null
          ? (existing.unitCostCents / 100).toStringAsFixed(2)
          : (product.unitCost ?? 0).toStringAsFixed(2),
    );
    final item = await showDialog<RetailPurchaseLine>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recibir: ${product.name}'),
        content: SizedBox(
          width: 350,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cantidad recibida'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Costo unitario ($_currency)',
                helperText: 'Costo de compra, no precio de venta',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final quantity = parseDecimal(qty.text);
              final costCents = parsePosCents(cost.text);
              if (quantity == null || quantity <= 0 || quantity > 100000 ||
                  quantity != double.parse(quantity.toStringAsFixed(2)) ||
                  costCents == null || costCents > 1000000000) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Indica cantidad válida y costo con máximo 2 decimales')),
                );
                return;
              }
              Navigator.pop(ctx, RetailPurchaseLine(
                productId: product.id, quantity: quantity, unitCostCents: costCents,
              ));
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    disposeAfterClose([qty, cost]);
    if (item != null && mounted && Repo.activeOrgId == org && _allowed) {
      setState(() => _lines[product.id] = item);
    }
  }

  Future<void> _submit({PendingRetailPurchase? retry}) async {
    final originOrg = Repo.activeOrgId;
    final originUser = Supabase.instance.client.auth.currentUser?.id;
    if (!_allowed || _saving || _recovering || _recoveryError != null) return;
    if (retry == null && (_lines.isEmpty || _supplier.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica el proveedor y al menos un producto.')),
      );
      return;
    }
    final paid = (retry?.paymentMethod ?? _method) != 'pendiente';
    if (retry == null && paid) {
      final confirmation = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar pago al proveedor'),
          content: Text('El pago se registrará como gasto del negocio. '
              '${_method == 'efectivo' ? 'También se registrará una salida de caja.' : 'Comprueba el pago en el medio indicado.'} '
              '¿Ya se efectuó este pago?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pago realizado')),
          ],
        ),
      );
      if (confirmation != true || !mounted || Repo.activeOrgId != originOrg ||
          Supabase.instance.client.auth.currentUser?.id != originUser) return;
    }
    setState(() => _saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser?.id;
      final org = Repo.activeOrgId;
      if (user == null || org == null || org != originOrg || user != originUser) {
        throw AppException('Sesión o empresa no válida');
      }
      final purchase = retry ?? PendingRetailPurchase(
        orgId: org, userId: user, requestId: Repo.newRequestId(),
        supplier: _supplier.text.trim(), reference: _reference.text.trim(),
        paymentMethod: _method, lines: _lines.values.toList(),
      );
      if (purchase.orgId != org || purchase.userId != user) {
        throw AppException('No se puede reintentar una compra de otra cuenta.');
      }
      if (retry == null) await RetailPurchaseStore.save(purchase);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != user) return;
      setState(() => _pending = purchase);
      final receiptId = await RetailPurchaseRepo.receive(purchase);
      await RetailPurchaseStore.clear(purchase);
      if (!mounted || Repo.activeOrgId != org ||
          Supabase.instance.client.auth.currentUser?.id != user) return;
      setState(() {
        _pending = null;
        _lines.clear();
        _supplier.clear();
        _reference.clear();
        _method = 'pendiente';
      });
      LiveCache.clear();
      AppState.instance.bump();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compra recibida, inventario actualizado. Ref: ${receiptId.substring(0, 8)}')),
      );
      await _load();
    } catch (e) {
      if (mounted && Repo.activeOrgId == originOrg &&
          Supabase.instance.client.auth.currentUser?.id == originUser) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recepción sin confirmar. Reintenta con la misma solicitud. ${friendly(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSettlement([Map<String, dynamic>? receipt]) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RetailSettlementScreen(receipt: receipt)),
    );
    if (completed == true && mounted) {
      LiveCache.clear();
      AppState.instance.bump();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Scaffold(body: Center(
        child: Text('Tu licencia o tu rol no permite registrar compras de inventario.'),
      ));
    }
    final products = (_products ?? const <Product>[])
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: RetailVisual.navy,
        colorScheme: ColorScheme.fromSeed(seedColor: RetailVisual.violet, brightness: Brightness.dark),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: RetailVisual.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF4B4C80))),
        ),
      ),
      child: Scaffold(
      backgroundColor: RetailVisual.navy,
      appBar: AppBar(
        backgroundColor: RetailVisual.navy,
        title: const Text('Compras y recepción', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            onPressed: () => _openSettlement(),
            icon: const Icon(Icons.pending_actions_rounded),
            tooltip: 'Recuperar pago de proveedor',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualizar'),
        ],
      ),
      body: _recovering || _recoveryError != null || _pending != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_recovering) const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_recovering
                    ? 'Buscando compras pendientes…'
                    : _recoveryError ?? 'Una compra necesita confirmación.',
                    textAlign: TextAlign.center),
                if (_pending case final pending?) ...[
                  const SizedBox(height: 16),
                  Text('${pending.supplier} · ${money(pending.totalCents / 100, _currency)}'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _submit(retry: pending),
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Recuperar la misma compra'),
                  ),
                ],
                if (_recoveryError != null)
                  TextButton(onPressed: _restore, child: const Text('Volver a comprobar')),
              ]),
            ))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    RetailVisual.hero(
                       context: context,
                       eyebrow: 'Plan Básico · Compras',
                       title: 'Recibe mercadería',
                       subtitle: 'Registra proveedor, cantidades y costos reales. El stock se actualiza al confirmar.',
                       icon: Icons.local_shipping_rounded,
                       footer: Row(children: [
                         Expanded(child: RetailVisual.microStat('Productos', '${_lines.length} seleccionados')),
                         const SizedBox(width: 12),
                         Expanded(child: RetailVisual.microStat('Importe', money(_total / 100, _currency))),
                       ]),
                     ),
                     RetailVisual.section(number: 1, title: 'Proveedor',
                       subtitle: 'Identifica de quién recibiste mercadería', icon: Icons.storefront_rounded),
                    TextField(
                      controller: _supplier,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Proveedor', hintText: 'Nombre o razón social'),
                    ),
                    TextField(
                      controller: _reference,
                      maxLength: 40,
                      decoration: const InputDecoration(labelText: 'Documento del proveedor (opcional)'),
                    ),
                    const SizedBox(height: 12),
                    RetailVisual.section(number: 2, title: 'Productos recibidos',
                       subtitle: 'Busca un producto y registra las unidades que ingresan',
                       icon: Icons.inventory_2_rounded),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar producto por nombre',
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    if (products.isEmpty)
                      const Padding(padding: EdgeInsets.all(12), child: Text('No se encontraron productos. Agrégalos al catálogo.')),
                    for (final p in products.take(40))
                      Card(color: RetailVisual.surface,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15),
                          side: const BorderSide(color: Color(0xFF474777))),
                        child: ListTile(
                        title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('Stock: ${p.stock == null ? 'sin control' : qtyText(p.stock!)}'
                            ' · Costo anterior: ${money(p.unitCost ?? 0, _currency)}'),
                        trailing: IconButton(
                          tooltip: 'Agregar a recepción',
                          onPressed: () => _editLine(p),
                          icon: Icon(_lines.containsKey(p.id) ? Icons.check_circle_rounded : Icons.add_circle_outline,
                            color: const Color(0xFF61E3D0)),
                        ),
                        onTap: () => _editLine(p),
                      )),
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const ProductsScreen(),
                        ));
                        _load();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Abrir catálogo para crear un producto'),
                    ),
                    if (_lines.isNotEmpty) ...[
                      const Divider(),
                      RetailVisual.section(number: 3, title: 'Resumen de recepción',
                         subtitle: 'Confirma cantidades y costo', icon: Icons.fact_check_rounded),
                      for (final entry in _lines.entries)
                        ListTile(
                          title: Text((_products ?? []).where((p) => p.id == entry.key).firstOrNull?.name ?? entry.key),
                          subtitle: Text('${qtyText(entry.value.quantity)} × ${money(entry.value.unitCostCents / 100, _currency)}'),
                          trailing: IconButton(
                            tooltip: 'Quitar línea',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => _lines.remove(entry.key)),
                          ),
                        ),
                      RetailVisual.panel(context, child: Row(children: [
                         const Expanded(child: Text('TOTAL DE COMPRA', style: TextStyle(
                           color: Color(0xFFBDB3E0), fontWeight: FontWeight.w800, fontSize: 11))),
                         Flexible(child: Text(money(_total / 100, _currency),
                           textAlign: TextAlign.end, style: const TextStyle(
                             color: Color(0xFF6FEBD4), fontWeight: FontWeight.w900, fontSize: 19))),
                       ])),
                    ],
                    const SizedBox(height: 20),
                    RetailVisual.section(number: 4, title: '¿Ya pagaste al proveedor?',
                       subtitle: 'La deuda pendiente no es un egreso de caja',
                       icon: Icons.account_balance_wallet_rounded),
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      items: const [
                        DropdownMenuItem(value: 'pendiente', child: Text('Pendiente de pago')),
                        DropdownMenuItem(value: 'efectivo', child: Text('Efectivo (sale de caja)')),
                        DropdownMenuItem(value: 'yape', child: Text('Yape')),
                        DropdownMenuItem(value: 'plin', child: Text('Plin')),
                        DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                        DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                      ],
                      onChanged: (value) => setState(() => _method = value ?? 'pendiente'),
                    ),
                    const SizedBox(height: 8),
                    Text(_method == 'pendiente'
                        ? 'Se ingresa el stock. El pago pendiente no se contabiliza todavía como gasto de caja.'
                        : 'Se ingresa el stock y se registra el gasto; el efectivo también se descuenta del saldo de caja.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, height: 54, child: FilledButton.icon(
                       key: const ValueKey('purchase-confirm-receipt'),
                       style: FilledButton.styleFrom(
                         backgroundColor: RetailVisual.violet, foregroundColor: Colors.white,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                       onPressed: _saving || _lines.isEmpty || _total <= 0 ? null : _submit,
                       icon: Icon(_saving ? Icons.hourglass_top_rounded : Icons.inventory_rounded),
                       label: Text(_saving ? 'Registrando recepción…' : 'Confirmar recepción',
                         style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                     )),
                    const SizedBox(height: 24),
                    RetailVisual.section(number: 5, title: 'Recepciones recientes',
                       subtitle: 'Historial y pagos pendientes', icon: Icons.history_rounded),
                    for (final receipt in _history)
                      Card(color: RetailVisual.surface,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text((receipt['supplier_name'] ?? '') as String),
                        subtitle: Text('${(receipt['created_at'] ?? '').toString().split('T').first} · ${receipt['payment_method']}'),
                        trailing: receipt['payment_method'] == 'pendiente'
                            ? OutlinedButton(
                                onPressed: _saving ? null : () => _openSettlement(receipt),
                                child: const Text('Pagar'),
                              )
                            : Text(money(
                                ((receipt['total_cents'] as num?) ?? 0).toDouble() / 100,
                                (receipt['currency'] ?? _currency) as String,
                              )),
                        onTap: receipt['payment_method'] == 'pendiente'
                            ? () => _openSettlement(receipt) : null,
                      )),
                  ],
                ),
    ));
  }
}
