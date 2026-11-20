import 'package:flutter/material.dart';

import '../models.dart';
import '../ui/retail_visual.dart';
import '../ui/glass_widgets.dart';
import '../ui/design_tokens.dart';
import 'client_profile.dart' show StorageImage;

enum RetailCartAction { collect, credit }

/// Second screen of the physical-store POS: products -> editable cart -> pay.
/// Every item comes from the active tenant's catalog. Never simulates sales.
class PosCartReviewScreen extends StatefulWidget {
  const PosCartReviewScreen({
    super.key,
    required this.lines,
    required this.onChangeQuantity,
    required this.currency,
    required this.taxRate,
    required this.productImages,
    this.fixtureAssetPhotos = const {},
    this.canSellOnCredit = false,
    this.sheetScrollController,
  });

  final List<LineItem> Function() lines;
  final void Function(String productId, int delta) onChangeQuantity;
  final String currency;
  final double taxRate;
  final Map<String, String> productImages;
  /// Fotos de activos locales solo para previsualizaciones y pruebas.
  final Map<String, String> fixtureAssetPhotos;
  final bool canSellOnCredit;
  /// El mismo carrito puede ser pantalla completa o sheet draggable.
  final ScrollController? sheetScrollController;

  @override
  State<PosCartReviewScreen> createState() => _PosCartReviewScreenState();
}

class _PosCartReviewScreenState extends State<PosCartReviewScreen> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = widget.lines();
    final total = computeTotals(items, widget.taxRate);
    final count = items.fold<double>(0, (sum, item) => sum + item.quantity);
    return Scaffold(
        appBar: AppBar(
          flexibleSpace: const FvGlassTopBar(),
          title: const Text('Carrito de venta'),
          actions: [
            IconButton(
              tooltip: 'Limpiar carrito',
              onPressed: items.isEmpty ? null : () async {
                final remove = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Vaciar carrito'),
                    content: const Text('Se eliminarán todos los productos de esta venta, sin afectar el inventario.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Vaciar'),
                      ),
                    ],
                  ),
                );
                if (remove != true || !context.mounted) return;
                for (final item in items) {
                  final id = item.productId;
                  if (id != null) widget.onChangeQuantity(id, -item.quantity.ceil());
                }
                setState(() {});
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    RetailVisual.journey(step: 2, label: 'Revisar productos'),
                    const SizedBox(height: 13),
                    const Text('Revisa productos y cantidades',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
                ),
                Expanded(
                  child: items.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.remove_shopping_cart_outlined, size: 54,
                            color: t.colorScheme.primary),
                          const SizedBox(height: 14),
                          const Text('El carrito está vacío.'),
                        ],
                      ))
                    : ListView.separated(
                        controller: widget.sheetScrollController,
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final id = item.productId;
                          final imagePath = widget.productImages[id] ?? '';
                          final fixtureAsset = widget.fixtureAssetPhotos[id] ?? '';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: t.colorScheme.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: t.colorScheme.outlineVariant, width: .65),
                              boxShadow: FvTokens.shadow(t.brightness),
                            ),
                            child: Row(children: [
                              SizedBox(
                                width: 56, height: 65,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: imagePath.isNotEmpty
                                    ? StorageImage(path: imagePath, fit: BoxFit.contain,
                                        placeholder: FvProductPhotoFallback(name: item.description))
                                    : fixtureAsset.isNotEmpty
                                        ? Image.asset(fixtureAsset,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.medium)
                                        : FvProductPhotoFallback(name: item.description),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(flex: 3, child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  Text(money(item.unitPrice, widget.currency),
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: t.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 7),
                                  Wrap(spacing: 4, runSpacing: 5,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      SizedBox.square(dimension: 44,
                                        child: IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: t.brightness == Brightness.dark
                                                ? t.colorScheme.surfaceContainerHighest
                                                : FvLuxe.jadeSoft,
                                            foregroundColor: t.colorScheme.primary,
                                          ),
                                          tooltip: 'Quitar uno',
                                          onPressed: id == null ? null : () {
                                            widget.onChangeQuantity(id, -1);
                                            setState(() {});
                                          },
                                          icon: const Icon(Icons.remove_rounded, size: 19),
                                          padding: EdgeInsets.zero,
                                        )),
                                      AnimatedSwitcher(
                                        duration: MediaQuery.disableAnimationsOf(context)
                                            ? Duration.zero : FvTokens.micro,
                                        child: Padding(
                                          key: ValueKey('qty-${item.productId}-${item.quantity}'),
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: Text(qtyText(item.quantity),
                                            style: const TextStyle(fontWeight: FontWeight.w800)),
                                        ),
                                      ),
                                      SizedBox.square(dimension: 44,
                                        child: IconButton.filledTonal(
                                          style: IconButton.styleFrom(
                                            backgroundColor: t.brightness == Brightness.dark
                                                ? t.colorScheme.surfaceContainerHighest
                                                : FvLuxe.jadeSoft,
                                            foregroundColor: t.colorScheme.primary,
                                          ),
                                          tooltip: 'Agregar uno',
                                          onPressed: id == null ? null : () {
                                            widget.onChangeQuantity(id, 1);
                                            setState(() {});
                                          },
                                          icon: const Icon(Icons.add_rounded, size: 19),
                                          padding: EdgeInsets.zero,
                                        )),
                                    ]),
                                ],
                              )),
                              const SizedBox(width: 6),
                              Flexible(flex: 2, child: Text(money(item.amount, widget.currency),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontWeight: FontWeight.w800))),
                            ]),
                          );
                        },
                      ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    border: Border(top: BorderSide(color: t.colorScheme.outline)),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
                  child: Column(children: [
                    _totalLine('Subtotal (${qtyText(count)})', total.subtotal, widget.currency),
                    const SizedBox(height: 7),
                    _totalLine('IGV (${qtyText(widget.taxRate)}%)', total.tax, widget.currency),
                    const Divider(height: 26),
                    _totalLine('Total a cobrar', total.total, widget.currency, bold: true),
                    const SizedBox(height: 14),
                    if (widget.canSellOnCredit && items.isNotEmpty) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey('retail-credit-sale'),
                          onPressed: () => Navigator.of(context).pop(RetailCartAction.credit),
                          icon: const Icon(Icons.person_outline_rounded),
                          label: const Text('Registrar venta a fiado (cliente requerido)'),
                        ),
                      ),
                      const SizedBox(height: 7),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        key: const ValueKey('retail-continue-payment'),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.colorScheme.primary,
                          foregroundColor: t.colorScheme.onPrimary,
                        ),
                        onPressed: items.isEmpty ? null : () => Navigator.of(context).pop(RetailCartAction.collect),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Continuar al pago',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
    );
  }

  Widget _totalLine(String label, double value, String currency, {bool bold = false}) {
    return Row(children: [
      Expanded(child: Text(label,
        style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          fontSize: bold ? 16 : 13))),
      Text(money(value, currency),
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: bold ? 19 : 13)),
    ]);
  }
}
