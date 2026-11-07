import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../access.dart';
import '../services/live.dart';
import '../services/repo.dart';
import '../services/receiving_repo.dart';
import '../ui/widgets.dart';
import 'products.dart';

class ReceivingScreen extends StatefulWidget {
  const ReceivingScreen({super.key, this.loadData, this.receive});
  final Future<Map<String, dynamic>> Function()? loadData;
  final Future<String> Function(Map<String, dynamic>)? receive;
  @override
  State<ReceivingScreen> createState() => _ReceivingScreenState();
}

class _ReceivingScreenState extends State<ReceivingScreen>
    with LiveReload<ReceivingScreen> {
  final _form = GlobalKey<FormState>();
  final _supplier = TextEditingController(),
      _reference = TextEditingController(),
      _quantity = TextEditingController(),
      _cost = TextEditingController();
  List<Map<String, dynamic>>? _products;
  List<Map<String, dynamic>> _receipts = [];
  String? _product, _error, _receipt;
  Map<String, dynamic>? _attempt;
  final List<Map<String, dynamic>> _lines = [];
  bool _busy = false;
  @override
  List<String> get liveTables => [
    'products',
    'retail_receipts',
    'retail_suppliers',
  ];
  @override
  Future<void> reloadLive() => _load();
  @override
  void initState() {
    super.initState();
    _load();
    startLive();
  }

  @override
  void dispose() {
    stopLive();
    for (final c in [_supplier, _reference, _quantity, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await (widget.loadData?.call() ?? ReceivingRepo.load());
      if (!mounted) return;
      setState(() {
        _products = (data['products'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        _receipts = (data['receipts'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        if (_attempt == null && !_products!.any((p) => p['id'] == _product)) {
          _product = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No pudimos consultar compras y existencias. Reintenta; no se confirmó ninguna operación.',
        );
      }
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Completa este dato' : null;
  String? _amount(String? value, {bool positive = false}) {
    final text = (value ?? '').trim().replaceAll(',', '.');
    final number = double.tryParse(text);
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text) ||
        number == null ||
        !number.isFinite ||
        number < (positive ? 0.01 : 0) ||
        number > (positive ? 100000 : 10000000)) {
      return 'Importe válido, hasta dos decimales';
    }
    return null;
  }

  Future<void> _confirm() async {
    if (_busy ||
        _receipt != null ||
        !Access.instance.can('finance') ||
        !Access.instance.has('stock')) {
      return;
    }
    if (_attempt == null &&
        _lines.isEmpty &&
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (_attempt == null &&
        _lines.isNotEmpty &&
        (_product != null ||
            _quantity.text.isNotEmpty ||
            _cost.text.isNotEmpty)) {
      setState(
        () => _error =
            'Añade el producto que estás editando al documento antes de confirmar.',
      );
      return;
    }
    if (_required(_supplier.text) != null ||
        _required(_reference.text) != null) {
      _form.currentState?.validate();
      return;
    }
    _attempt ??= {
      'p_request': Repo.newRequestId(),
      'p_supplier': _supplier.text.trim(),
      'p_reference': _reference.text.trim(),
      'p_lines': _lines.isNotEmpty
          ? _lines
                .map(
                  (l) => {
                    'product_id': l['product_id'],
                    'quantity': l['quantity'],
                    'unit_cost': l['unit_cost'],
                  },
                )
                .toList()
          : [
              {
                'product_id': _product,
                'quantity': double.parse(_quantity.text.replaceAll(',', '.')),
                'unit_cost': double.parse(_cost.text.replaceAll(',', '.')),
              },
            ],
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id =
          await (widget.receive?.call(_attempt!) ??
              ReceivingRepo.receive(_attempt!));
      if (!mounted) return;
      setState(() => _receipt = id);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          if (['22023', '23505', '42501', '23514'].contains(e.code)) {
            _attempt = null;
            _error = e.code == '23505'
                ? 'El proveedor y documento ya están registrados. Consulta el historial antes de cambiar la referencia.'
                : 'El servidor rechazó la recepción sin aplicar cambios. Revisa productos, cantidades, costos y permisos.';
          } else {
            _error =
                'Sin confirmación del servidor. Reintenta la misma recepción.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Recepción sin confirmar. Reintenta la misma operación para evitar duplicar existencias. Revisa también si el documento ya está registrado.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addLine() {
    if (!(_form.currentState?.validate() ?? false) || _lines.length >= 50) {
      return;
    }
    if (_lines.any((l) => l['product_id'] == _product)) {
      setState(
        () => _error =
            'Este producto ya está en el documento. Quita su línea para corregir la cantidad.',
      );
      return;
    }
    setState(() {
      _lines.add({
        'product_id': _product,
        'name': _products!.firstWhere((p) => p['id'] == _product)['name'],
        'quantity': double.parse(_quantity.text.replaceAll(',', '.')),
        'unit_cost': double.parse(_cost.text.replaceAll(',', '.')),
      });
      _product = null;
      _error = null;
      _quantity.clear();
      _cost.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allowed =
        Access.instance.can('finance') && Access.instance.has('stock');
    final products = (_products ?? [])
        .where((p) => p['stock'] != null)
        .toList();
    final locked = _attempt != null || _busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras y recepción'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !allowed
          ? const Center(
              child: Text('Necesitas permisos de finanzas e inventario.'),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Del proveedor a tu tienda.',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Registra mercadería que ya recibiste. Documento, existencias y último costo se guardan juntos.',
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    SoftCard(
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Actualizar consultas'),
                          ),
                        ],
                      ),
                    ),
                  if (_products == null)
                    const SkeletonList(count: 3)
                  else if (_receipt != null)
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded),
                          Text(
                            'Recepción confirmada',
                            style: theme.textTheme.titleLarge,
                          ),
                          Text('Operación: $_receipt'),
                          const Text(
                            'Existencias y último costo actualizados. No se ha registrado un pago al proveedor.',
                          ),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _attempt = null;
                                _receipt = null;
                                _error = null;
                                _lines.clear();
                                _product = null;
                              });
                              _reference.clear();
                              _quantity.clear();
                              _cost.clear();
                            },
                            child: const Text('Registrar otra recepción'),
                          ),
                        ],
                      ),
                    )
                  else
                    SoftCard(
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Documento de recepción',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _supplier,
                              enabled: !locked,
                              maxLength: 120,
                              validator: _required,
                              decoration: const InputDecoration(
                                labelText: 'Proveedor',
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _reference,
                              enabled: !locked,
                              maxLength: 80,
                              validator: _required,
                              decoration: const InputDecoration(
                                labelText: 'Documento o referencia única',
                                hintText: 'F001-000123',
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: ValueKey(_product),
                              initialValue:
                                  products.any((p) => p['id'] == _product)
                                  ? _product
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Producto',
                              ),
                              items: [
                                for (final p in products)
                                  DropdownMenuItem(
                                    value: p['id'] as String,
                                    child: Text(
                                      '${p['name']} · ${p['stock']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: locked
                                  ? null
                                  : (v) => setState(() => _product = v),
                              validator: _required,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _quantity,
                              enabled: !locked,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (v) => _amount(v, positive: true),
                              decoration: const InputDecoration(
                                labelText: 'Cantidad recibida',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _cost,
                              enabled: !locked,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: _amount,
                              decoration: const InputDecoration(
                                labelText: 'Costo unitario de adquisición',
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: locked || _lines.length >= 50
                                  ? null
                                  : _addLine,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Añadir al documento'),
                            ),
                            for (final line in _lines)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${line['name']}'),
                                subtitle: Text(
                                  '${line['quantity']} × ${line['unit_cost']}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Quitar producto',
                                  onPressed: locked
                                      ? null
                                      : () =>
                                            setState(() => _lines.remove(line)),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                            FilledButton.icon(
                              onPressed: _busy || products.isEmpty
                                  ? null
                                  : _confirm,
                              icon: Icon(
                                locked
                                    ? Icons.sync_rounded
                                    : Icons.inventory_2_outlined,
                              ),
                              label: Text(
                                _busy
                                    ? 'Confirmando…'
                                    : locked
                                    ? 'Recuperar misma recepción'
                                    : 'Confirmar recepción',
                              ),
                            ),
                            const Text(
                              'En la moneda de la empresa. No genera pago ni crédito fiscal.',
                            ),
                            if (products.isEmpty)
                              TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const ProductsScreen(),
                                  ),
                                ),
                                child: const Text(
                                  'Configurar productos con stock',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Existencias disponibles',
                    style: theme.textTheme.titleLarge,
                  ),
                  for (final p in products)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${p['name']}'),
                      subtitle: Text(
                        'Último costo: ${p['unit_cost'] ?? 'Sin dato'}',
                      ),
                      trailing: Text(
                        '${p['stock']}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Recepciones confirmadas',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (_receipts.isEmpty)
                    const Text('Todavía no hay recepciones registradas.'),
                  for (final r in _receipts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['reference']} · ${r['supplier_name']}'),
                      subtitle: Text('${r['created_at']}'),
                      trailing: Text('${r['currency']} ${r['total']}'),
                    ),
                ],
              ),
            ),
    );
  }
}
