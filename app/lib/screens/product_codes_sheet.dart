// Códigos de barras de un producto (v3.9): el principal y los adicionales. Para el mismo producto con códigos
// distintos de fábrica (presentaciones o lotes), se escanean uno tras otro sin escribir el nombre.
import 'package:flutter/material.dart';

import '../errors.dart';
import '../models.dart';
import '../services/product_codes.dart';
import '../ui/barcode_scanner.dart';

Future<void> showProductCodes(BuildContext context, {required Product product, String? mainCode}) => showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _ProductCodesSheet(product: product, mainCode: mainCode),
    );

class _ProductCodesSheet extends StatefulWidget {
  const _ProductCodesSheet({required this.product, this.mainCode});
  final Product product;
  final String? mainCode;

  @override
  State<_ProductCodesSheet> createState() => _ProductCodesSheetState();
}

class _ProductCodesSheetState extends State<_ProductCodesSheet> {
  final _manual = TextEditingController();
  List<({String id, String code})>? _codes;
  String? _msg;
  bool _ok = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await ProductCodes.codesOf(widget.product.id);
      if (mounted) setState(() => _codes = c);
    } catch (e) {
      if (mounted) setState(() { _codes = const []; _msg = friendly(e); });
    }
  }

  Future<void> _add(String code) async {
    if (_busy || code.trim().isEmpty) return;
    setState(() { _busy = true; _msg = null; });
    try {
      await ProductCodes.add(widget.product.id, code);
      _manual.clear();
      _ok = true;
      _msg = 'Código ${code.trim()} agregado. Escanea el siguiente o cierra.';
      await _load();
    } catch (e) {
      _ok = false;
      _msg = friendly(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanLoop() async {
    // Escanea, agrega y vuelve a abrir la cámara hasta que la persona la cierre: miles de códigos sin escribir.
    while (mounted) {
      if (!mounted) return;
      final code = await scanBarcode(context);
      if (code == null || !mounted) return;
      await _add(code);
      if (!_ok) return; // si el código ya era de otro producto, se muestra el aviso y se detiene
    }
  }

  Future<void> _remove(String id) async {
    try {
      await ProductCodes.remove(id);
      await _load();
    } catch (e) {
      if (mounted) setState(() { _ok = false; _msg = friendly(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final codes = _codes;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Códigos de ${widget.product.name}', style: t.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Todos venden este mismo producto con su precio. Agrega los códigos de otras presentaciones o lotes.',
          style: t.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (widget.mainCode != null && widget.mainCode!.isNotEmpty)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.qr_code_2_rounded),
            title: Text(widget.mainCode!), subtitle: const Text('Código principal')),
        if (codes == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else for (final c in codes)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.qr_code_rounded), title: Text(c.code),
            trailing: IconButton(tooltip: 'Quitar código', icon: const Icon(Icons.delete_outline_rounded), onPressed: _busy ? null : () => _remove(c.id))),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _scanLoop,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Escanear códigos (uno tras otro)'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _manual, decoration: const InputDecoration(labelText: 'O escribe el código', isDense: true),
            onSubmitted: _add)),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _busy ? null : () => _add(_manual.text), child: const Text('Agregar')),
        ]),
        if (_msg != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_msg!, style: TextStyle(color: _ok ? t.colorScheme.primary : t.colorScheme.error, fontWeight: FontWeight.w600)),
        ),
      ])),
    );
  }
}
