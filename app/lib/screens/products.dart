import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access.dart';
import '../errors.dart';
import '../models.dart';
import '../growth.dart';
import '../services/growth_repo.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../services/live.dart';
import '../ui/motion.dart';
import '../ui/widgets.dart';
import 'package:image_picker/image_picker.dart';
import '../services/v2_repo.dart';
import '../ui/barcode_scanner.dart';
import 'client_profile.dart' show StorageImage;

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
  const ProductsScreen({super.key, this.loadProducts});
  final Future<List<Product>> Function()? loadProducts;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with LiveReload<ProductsScreen> {
  List<Product>? _all;
  String? _error;
  String _q = '';

  @override
  List<String> get liveTables => const ['products'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _all = LiveCache.get<List<Product>>('products.all');
    _load();
    startLive(); // tiempo real
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await (widget.loadProducts?.call() ?? Repo.listProducts());
      LiveCache.put('products.all', r);
      if (mounted) setState(() => _all = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _edit([Product? p]) async {
    if (!Access.instance.has('facturar') || !Access.instance.can('products_edit')) return;
    final stockAllowed = Access.instance.has('stock');
    final storeAllowed = Access.instance.has('tienda');
    final name = TextEditingController(text: p?.name ?? '');
    final price = TextEditingController(text: p == null || p.unitPrice == 0 ? '' : qtyText(p.unitPrice));
    var unit = p?.unit ?? 'ZZ';
    var track = p?.tracksStock ?? false;
    final stock = TextEditingController(text: p?.stock == null ? '' : qtyText(p!.stock!));
    final reorder = TextEditingController(text: p?.reorderPoint == null ? '' : qtyText(p!.reorderPoint!));
    final cost = TextEditingController(text: p?.unitCost == null ? '' : qtyText(p!.unitCost!));
    var inStore = p?.inStore ?? false;
    var err = '';
    // v2.0: código de barras, foto, categoría, descripción y precio por mayor.
    final extra = p == null ? null : await V2Repo.productExtra(p.id);
    if (!mounted) return;
    final barcode = TextEditingController(text: (extra?['barcode'] ?? '') as String);
    final category = TextEditingController(text: (extra?['category'] ?? '') as String);
    final description = TextEditingController(text: (extra?['description'] ?? '') as String);
    final wholesale = TextEditingController(text: extra?['wholesale_price'] == null ? '' : qtyText((extra!['wholesale_price'] as num).toDouble()));
    final wholesaleMin = TextEditingController(text: extra?['wholesale_min_qty'] == null ? '' : qtyText((extra!['wholesale_min_qty'] as num).toDouble()));
    final oldImage = extra?['image_path'] as String?;
    Uint8List? newImage;
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
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) => setS(() {}),
                decoration: const InputDecoration(labelText: 'Costo unitario (opcional)', helperText: 'Lo que te cuesta a ti. Calculo tu margen real.', prefixIcon: Icon(Icons.price_change_outlined)),
              ),
              Builder(builder: (_) {
                final c = parseDecimal(cost.text);
                final pr = parseDecimal(price.text) ?? 0;
                final m = marginOf(price: pr, cost: c);
                if (c == null || c <= 0) return const SizedBox.shrink();
                final color = m == null ? Colors.grey : (m < 0.15 ? const Color(0xFFD94A5E) : (m < 0.3 ? const Color(0xFFC57A12) : const Color(0xFF23956F)));
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m != null)
                      Text(
                        m < 0 ? 'Estás vendiendo a pérdida (${(m * 100).round()} %).' : 'Margen: ${(m * 100).round()} % · ganas ${(pr - c).toStringAsFixed(2)} por unidad',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: color),
                      ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final target in const [0.3, 0.4, 0.5])
                        ActionChip(
                          label: Text('Precio para ${(target * 100).round()} %: ${priceForMargin(cost: c, margin: target).toStringAsFixed(2)}'),
                          onPressed: () => setS(() => price.text = qtyText(priceForMargin(cost: c, margin: target))),
                        ),
                    ]),
                  ]),
                );
              }),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ZZ', label: Text('Servicio'), icon: Icon(Icons.handyman_rounded)),
                  ButtonSegment(value: 'NIU', label: Text('Producto'), icon: Icon(Icons.inventory_2_rounded)),
                ],
                selected: {unit},
                onSelectionChanged: (s) => setS(() => unit = s.first),
              ),
              if (storeAllowed) SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: inStore,
                onChanged: (v) => setS(() => inStore = v),
                title: const Text('Mostrar en mi tienda en línea'),
                subtitle: inStore ? Text(unit == 'NIU' ? 'Para publicarlo necesita foto y código de barras.' : 'Para publicarlo necesita una foto.') : null,
              ),
              // ── Foto (se comprime en el teléfono antes de subirla; se guarda en Storage privado) ──
              Row(children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: newImage != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(newImage!, fit: BoxFit.cover))
                      : (oldImage != null && oldImage.isNotEmpty
                          ? StorageImage(path: oldImage)
                          : Container(
                              decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.add_a_photo_rounded),
                            )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final src in const [ImageSource.camera, ImageSource.gallery])
                      OutlinedButton.icon(
                        onPressed: () async {
                          final x = await ImagePicker().pickImage(source: src, maxWidth: 1200, imageQuality: 75);
                          if (x == null) return;
                          final b = await x.readAsBytes();
                          setS(() => newImage = b);
                        },
                        icon: Icon(src == ImageSource.camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded, size: 18),
                        label: Text(src == ImageSource.camera ? 'Foto' : 'Galería'),
                      ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: barcode,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Código de barras',
                  helperText: 'Escanéalo o usa tu lector (pistola) con el cursor aquí.',
                  suffixIcon: IconButton(
                    tooltip: 'Escanear con la cámara',
                    onPressed: () async {
                      final c = await scanBarcode(ctx);
                      if (c != null) setS(() => barcode.text = c);
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: category, decoration: const InputDecoration(labelText: 'Categoría (ej.: Bebidas)'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: description, maxLines: 2, maxLength: 400, decoration: const InputDecoration(labelText: 'Descripción para la tienda (opcional)', counterText: '')),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: wholesale,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio por mayor (opcional)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: wholesaleMin,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Desde (unidades)'),
                  ),
                ),
              ]),
              if (unit == 'NIU' && stockAllowed) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: track,
                  onChanged: (v) => setS(() => track = v),
                  title: const Text('Controlar stock'),
                  subtitle: const Text('Se descuenta al emitir cada venta y te aviso días antes de que se acabe.'),
                ),
                if (track)
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: stock,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
                        decoration: const InputDecoration(labelText: 'Stock actual'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: reorder,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: const InputDecoration(labelText: 'Avisar al llegar a'),
                      ),
                    ),
                  ]),
              ],
              if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: const TextStyle(color: Color(0xFFD94A5E)))),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Guardar',
                icon: Icons.check_rounded,
                onPressed: () {
                  final v = price.text.trim().isEmpty ? 0.0 : parseDecimal(price.text);
                  final hasImage = newImage != null || (oldImage != null && oldImage.isNotEmpty);
                  if (name.text.trim().isEmpty) {
                    setS(() => err = 'El nombre es obligatorio');
                  } else if (v == null || v < 0 || v > 10000000) {
                    setS(() => err = 'Escribe un precio válido');
                  } else if (storeAllowed && inStore && !hasImage) {
                    setS(() => err = 'Para mostrarlo en la tienda agrega una foto (o apaga "Mostrar en mi tienda").');
                  } else if (storeAllowed && inStore && unit == 'NIU' && barcode.text.trim().isEmpty) {
                    setS(() => err = 'Para mostrarlo en la tienda agrega su código de barras (o apaga "Mostrar en mi tienda").');
                  } else if (wholesale.text.trim().isNotEmpty && (parseDecimal(wholesale.text) == null || parseDecimal(wholesaleMin.text) == null)) {
                    setS(() => err = 'Para el precio por mayor indica también desde cuántas unidades.');
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
    final stockValue = track && unit == 'NIU' ? (parseDecimal(stock.text) ?? 0.0) : null;
    final reorderValue = track && unit == 'NIU' ? parseDecimal(reorder.text) : null;
    final stockChanged = stockValue != p?.stock || reorderValue != p?.reorderPoint;
    final costValue = parseDecimal(cost.text);
    final growthChanged = costValue != p?.unitCost || inStore != (p?.inStore ?? true);
    final extraFields = <String, dynamic>{
      'barcode': barcode.text.trim().isEmpty ? null : barcode.text.trim(),
      'category': category.text.trim().isEmpty ? null : category.text.trim(),
      'description': description.text.trim().isEmpty ? null : description.text.trim(),
      'wholesale_price': parseDecimal(wholesale.text),
      'wholesale_min_qty': parseDecimal(wholesale.text) == null ? null : parseDecimal(wholesaleMin.text),
    };
    final imageToUpload = newImage;
    disposeAfterClose([name, price, stock, reorder, cost, barcode, category, description, wholesale, wholesaleMin]);
    if (ok != true) return;
    try {
      final id = await Repo.saveProduct(id: p?.id, name: values.$1, unitPrice: values.$2, unit: values.$3);
      try {
        if (imageToUpload != null) extraFields['image_path'] = await V2Repo.upload('productos', imageToUpload);
        await V2Repo.saveProductExtra(id, extraFields);
      } catch (e) {
        _snack(e.toString().contains('23505') ? 'Guardado, pero ese código de barras ya lo tiene otro producto.' : 'Guardado. ${V2Repo.missingHint(e)}');
      }
      if (stockAllowed && stockChanged && Access.instance.has('stock')) {
        try {
          await ProRepo.setStockConfig(id, stock: stockValue, reorderPoint: reorderValue);
        } catch (e) {
          if (ProRepo.isMissingMigration(e) || e.toString().contains('stock')) {
            _snack('Guardado. Para controlar stock ejecuta la migración 20261101_negocio_pro.sql.');
            _load();
            return;
          }
          rethrow;
        }
      }
      if (growthChanged) {
        try {
          await GrowthRepo.setCostAndStore(id, unitCost: costValue, inStore: inStore);
        } catch (e) {
          if (ProRepo.isMissingMigration(e) || e.toString().contains('unit_cost') || e.toString().contains('in_store')) {
            _snack('Guardado. Para costo y tienda ejecuta la migración 20261102_revolucion.sql.');
            _load();
            return;
          }
          rethrow;
        }
      }
      _snack('Guardado');
      _load();
    } catch (e) {
      _snack('No se pudo guardar. ${friendly(e)}');
    }
  }

  Future<void> _more(Product p) async {
    if (!Access.instance.has('facturar') || !Access.instance.can('products_edit')) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar'), onTap: () => Navigator.pop(ctx, 'edit')),
          if (p.tracksStock && Access.instance.has('stock'))
            ListTile(
              leading: const Icon(Icons.move_down_rounded),
              title: const Text('Registrar entrada o salida de stock'),
              subtitle: Text('Stock actual: ${qtyText(p.stock ?? 0)}'),
              onTap: () => Navigator.pop(ctx, 'stock'),
            ),
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
        case 'stock':
          await _adjust(p);
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

  /// Entrada (compra) o salida (merma, uso interno) de stock. Atómico en la base de datos.
  Future<void> _adjust(Product p) async {
    if (!Access.instance.has('stock') || !Access.instance.can('products_edit')) return;
    final qty = TextEditingController();
    var inbound = true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(p.name, style: Theme.of(ctx).textTheme.titleLarge),
            Text('Stock actual: ${qtyText(p.stock ?? 0)}', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Entrada'), icon: Icon(Icons.add_box_outlined)),
                ButtonSegment(value: false, label: Text('Salida'), icon: Icon(Icons.indeterminate_check_box_outlined)),
              ],
              selected: {inbound},
              onSelectionChanged: (s) => setS(() => inbound = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
            const SizedBox(height: 14),
            GradientButton(label: 'Registrar', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    final v = parseDecimal(qty.text);
    disposeAfterClose([qty]);
    if (ok != true || v == null || v <= 0) return;
    try {
      final now = await ProRepo.stockAdjust(p.id, inbound ? v : -v);
      Haptics.success();
      _snack('Stock actualizado: ${qtyText(now ?? 0)}');
      _load();
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
      floatingActionButton: Access.instance.can('products_edit') ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Nuevo')) : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            SectorPhotoBanner(rubro: Access.instance.rubro,
              title: 'Tu catálogo, con identidad', subtitle: 'Organiza productos, servicios, precios y fotos reales.', height: 136),
            const SizedBox(height: 16),
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
                        onTap: Access.instance.can('products_edit') ? () => _more(p) : null,
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
                                if (p.tracksStock || p.margin != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                                      if (p.tracksStock && Access.instance.has('stock')) StatusPill('Stock ${qtyText(p.stock ?? 0)}', tone: p.lowStock ? PillTone.warn : PillTone.ok),
                                      if (p.margin != null)
                                        StatusPill('Margen ${(p.margin! * 100).round()} %', tone: p.margin! < 0.15 ? PillTone.bad : (p.margin! < 0.3 ? PillTone.warn : PillTone.ok)),
                                    ]),
                                  ),
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
