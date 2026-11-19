import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'glass_widgets.dart';
import 'pos_product_card.dart';

/// Display-only sample. Never saves products or invokes payment APIs.
class _DemoProduct {
  const _DemoProduct(this.name, this.category, this.price, this.photo);
  final String name, category, photo;
  final double price;
}
const _products = <_DemoProduct>[
  _DemoProduct('Agua mineral 625 ml', 'Bebidas', 1.80,
    'https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=420&fit=crop&q=80'),
  _DemoProduct('Leche fresca 1 L', 'Lácteos', 4.90,
    'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=420&fit=crop&q=80'),
  _DemoProduct('Arroz extra 1 kg', 'Abarrotes', 4.50,
    'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=420&fit=crop&q=80'),
  _DemoProduct('Aceite de oliva 500 ml', 'Abarrotes', 17.90,
    'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=420&fit=crop&q=80'),
  _DemoProduct('Pan artesanal', 'Panadería', 5.50,
    'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=420&fit=crop&q=80'),
  _DemoProduct('Galletas caseras', 'Snacks', 3.50,
    'https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=420&fit=crop&q=80'),
];

/// Shown only for an empty real catalog; no user data is changed.
class FvDemoPosGallery extends StatefulWidget {
  const FvDemoPosGallery({super.key, this.loadPhotos = true});
  final bool loadPhotos;
  @override
  State<FvDemoPosGallery> createState() => _FvDemoPosGalleryState();
}
class _FvDemoPosGalleryState extends State<FvDemoPosGallery> {
  final Map<String, int> _quantities = {};
  String _category = 'Todo';
  int get _count => _quantities.values.fold<int>(0, (n, qty) => n + qty);
  double get _total => _products.fold<double>(0,
      (n, p) => n + p.price * (_quantities[p.name] ?? 0));
  void _change(_DemoProduct p, int delta) => setState(() {
    final next = (_quantities[p.name] ?? 0) + delta;
    if (next <= 0) {
      _quantities.remove(p.name);
    } else {
      _quantities[p.name] = next;
    }
  });
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final visible = _products.where((p) =>
        _category == 'Todo' || p.category == _category).toList();
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 790 ? 4 :
          constraints.maxWidth >= 520 ? 3 : 2;
      return ListView(
        key: const ValueKey('demo-gallery-scroll'),
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        children: [
          FvGlassSurface(radius: 20, blur: 18,
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.visibility_outlined, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Vista de demostración',
                      style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Estos productos no están en tu inventario. '
                      'Puedes probar las tarjetas sin registrar ventas ni pagos.',
                      style: t.textTheme.bodySmall),
              ])),
            ]),
          ),
          const SizedBox(height: 22),
          Text('Productos de ejemplo', style: t.textTheme.headlineSmall),
          const SizedBox(height: 5),
          Text('Fotos ilustrativas · precios referenciales',
              style: t.textTheme.bodySmall),
          const SizedBox(height: 15),
          SizedBox(height: 47, child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              for (final c in const <String>[
                'Todo','Bebidas','Abarrotes','Lácteos','Panadería','Snacks'
              ]) Padding(padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(c), showCheckmark: false,
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c))),
            ],
          )),
          const SizedBox(height: 14),
          GridView.builder(
            key: const ValueKey('demo-product-grid'),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true, itemCount: visible.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns, crossAxisSpacing: 12,
              mainAxisSpacing: 12, childAspectRatio: .60),
            itemBuilder: (context, index) {
              final p = visible[index];
              final qty = _quantities[p.name] ?? 0;
              return FvPosProductCard(
                key: ValueKey('demo-${p.name}'),
                name: p.name,
                price: 'S/ ${p.price.toStringAsFixed(2)}',
                category: p.category, stockLabel: 'Muestra',
                quantity: qty > 0 ? '$qty' : null,
                icon: Icons.shopping_bag_outlined,
                photo: widget.loadPhotos
                    ? FvNetworkProductPhoto(
                        url: p.photo, name: p.name, category: p.category)
                    : FvProductPhotoFallback(
                        name: p.name, category: p.category),
                onAdd: () => _change(p, 1),
                onRemove: qty > 0 ? () => _change(p, -1) : null,
              );
            },
          ),
          const SizedBox(height: 20),
          FvGlassSurface(radius: 20, blur: 18,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.shopping_bag_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_count == 1
                      ? '1 artículo de muestra'
                      : '$_count artículos de muestra',
                    style: t.textTheme.titleSmall)),
                  Text('S/ ${_total.toStringAsFixed(2)}',
                    style: t.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                const SizedBox(height: 9),
                Text('Carrito visual: no se realiza ningún cobro.',
                    style: t.textTheme.bodySmall),
                if (_count > 0) Align(alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(_quantities.clear),
                    child: const Text('Vaciar demostración'))),
              ]),
          ),
        ],
      );
    });
  }
}
