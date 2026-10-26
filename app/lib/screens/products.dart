import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/widgets.dart';

/// Elige un producto del catálogo (solo activos). Devuelve null si se cierra sin elegir.
Future<Product?> pickProduct(BuildContext context, String currency) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ProductPicker(currency: currency),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.currency});
  final String currency;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  List<Product>? _all;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    Repo.listProducts(activeOnly: true).then((r) {
      if (mounted) setState(() => _all = r);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendly(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final q = _q.trim().toLowerCase();
    final list = (_all ?? const <Product>[]).where((p) => q.isEmpty || p.name.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * .7,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Del catálogo', style: t.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'Buscar producto o servicio', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : _all == null
                    ? const SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, child: SkeletonList(count: 4))
                    : _all!.isEmpty
                        ? const EmptyState(title: 'Tu catálogo está vacío', body: 'Agrega productos y servicios en Ajustes → Productos y servicios.')
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final p = list[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: t.colorScheme.primary.withValues(alpha: .12),
                                  child: Icon(p.isService ? Icons.handyman_rounded : Icons.inventory_2_rounded, size: 20, color: t.colorScheme.primary),
                                ),
                                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Money(money(p.unitPrice, widget.currency), size: 14),
                                onTap: () => Navigator.pop(context, p),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}

/// Catálogo de la empresa activa: crear, editar, archivar y borrar.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product>? _all;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Repo.listProducts();
      if (mounted) setState(() => _all = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _edit([Product? p]) async {
    final name = TextEditingController(text: p?.name ?? '');
    final price = TextEditingController(text: p == null || p.unitPrice == 0 ? '' : qtyText(p.unitPrice));
    var unit = p?.unit ?? 'ZZ';
    var err = '';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(p == null ? 'Nuevo producto o servicio' : 'Editar', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: name, autofocus: p == null, maxLength: 200, decoration: const InputDecoration(labelText: 'Nombre', counterText: '')),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Precio unitario (sin impuesto)', prefixIcon: Icon(Icons.payments_outlined)),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ZZ', label: Text('Servicio'), icon: Icon(Icons.handyman_rounded)),
                  ButtonSegment(value: 'NIU', label: Text('Producto'), icon: Icon(Icons.inventory_2_rounded)),
                ],
                selected: {unit},
                onSelectionChanged: (s) => setS(() => unit = s.first),
              ),
              if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: Color(0xFFD94A5E)))),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Guardar',
                icon: Icons.check_rounded,
                onPressed: () {
                  final v = price.text.trim().isEmpty ? 0.0 : parseDecimal(price.text);
                  if (name.text.trim().isEmpty) {
                    setS(() => err = 'El nombre es obligatorio');
                  } else if (v == null || v < 0 || v > 10000000) {
                    setS(() => err = 'Escribe un precio válido');
                  } else {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
    final values = (name.text, price.text.trim().isEmpty ? 0.0 : (parseDecimal(price.text) ?? 0.0), unit);
    disposeAfterClose([name, price]);
    if (ok != true) return;
    try {
      await Repo.saveProduct(id: p?.id, name: values.$1, unitPrice: values.$2, unit: values.$3);
      _snack('Guardado');
      _load();
    } catch (e) {
      _snack('No se pudo guardar. ${friendly(e)}');
    }
  }

  Future<void> _more(Product p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            leading: Icon(p.active ? Icons.archive_outlined : Icons.unarchive_outlined),
            title: Text(p.active ? 'Archivar (ocultar al facturar)' : 'Reactivar'),
            onTap: () => Navigator.pop(ctx, 'toggle'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD94A5E)),
            title: const Text('Borrar', style: TextStyle(color: Color(0xFFD94A5E))),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    try {
      switch (action) {
        case 'edit':
          await _edit(p);
        case 'toggle':
          await Repo.setProductActive(p.id, !p.active);
          _load();
        case 'delete':
          await Repo.deleteProduct(p.id);
          _snack('Producto borrado');
          _load();
      }
    } catch (e) {
      _snack(friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = _all;
    final q = _q.trim().toLowerCase();
    final list = (all ?? const <Product>[]).where((p) => q.isEmpty || p.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Productos y servicios')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Nuevo')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              SoftCard(
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
                ]),
              )
            else if (all == null)
              const SkeletonList()
            else if (all.isEmpty)
              const EmptyState(title: 'Tu catálogo está vacío', body: 'Guarda tus productos y servicios con su precio y elígelos al facturar, sin dictar el precio cada vez.')
            else if (list.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 40), child: Text('Nada coincide con tu búsqueda.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium))
            else
              for (final (i, p) in list.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Reveal(
                    key: ValueKey(p.id),
                    index: i < 8 ? i : 8,
                    child: Opacity(
                      opacity: p.active ? 1 : .5,
                      child: Pressable(
                        onTap: () => _more(p),
                        child: SoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            CircleAvatar(
                              backgroundColor: t.colorScheme.primary.withValues(alpha: .12),
                              child: Icon(p.isService ? Icons.handyman_rounded : Icons.inventory_2_rounded, size: 20, color: t.colorScheme.primary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(p.active ? (p.isService ? 'Servicio' : 'Producto') : 'Archivado', style: t.textTheme.bodySmall),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            Text(p.unitPrice.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
