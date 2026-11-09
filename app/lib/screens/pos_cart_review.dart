import 'package:flutter/material.dart';

import '../models.dart';
import 'client_profile.dart' show StorageImage;

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
  });

  final List<LineItem> Function() lines;
  final void Function(String productId, int delta) onChangeQuantity;
  final String currency;
  final double taxRate;
  final Map<String, String> productImages;

  @override
  State<PosCartReviewScreen> createState() => _PosCartReviewScreenState();
}

class _PosCartReviewScreenState extends State<PosCartReviewScreen> {
  static const _background = Color(0xFF0B1030);
  static const _surface = Color(0xFF1B214A);
  static const _purple = Color(0xFF9658FA);

  @override
  Widget build(BuildContext context) {
    final items = widget.lines();
    final total = computeTotals(items, widget.taxRate);
    final count = items.fold<double>(0, (sum, item) => sum + item.quantity);
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _purple,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _background,
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Revisa los productos y cantidades',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                    ? const Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.remove_shopping_cart_outlined, size: 54, color: Color(0xFFC0A6FF)),
                          SizedBox(height: 14),
                          Text('El carrito está vacío.'),
                        ],
                      ))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final id = item.productId;
                          final imagePath = widget.productImages[id] ?? '';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(color: const Color(0xFF655B98)),
                            ),
                            child: Row(children: [
                              SizedBox(
                                width: 56, height: 65,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: imagePath.isEmpty
                                    ? const ColoredBox(
                                        color: Color(0xFF343066),
                                        child: Icon(Icons.inventory_2_outlined, color: Color(0xFFC9B9FF)),
                                      )
                                    : StorageImage(path: imagePath),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  Text(money(item.unitPrice, widget.currency),
                                    style: const TextStyle(fontSize: 12, color: Color(0xFFBAB6D7))),
                                  const SizedBox(height: 7),
                                  Row(children: [
                                    SizedBox(
                                      width: 33, height: 33,
                                      child: IconButton.filledTonal(
                                        tooltip: 'Quitar uno',
                                        onPressed: id == null ? null : () {
                                          widget.onChangeQuantity(id, -1);
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.remove_rounded, size: 18),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(qtyText(item.quantity),
                                        style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                    SizedBox(
                                      width: 33, height: 33,
                                      child: IconButton.filledTonal(
                                        tooltip: 'Agregar uno',
                                        onPressed: id == null ? null : () {
                                          widget.onChangeQuantity(id, 1);
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ]),
                                ],
                              )),
                              const SizedBox(width: 6),
                              Text(money(item.amount, widget.currency),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            ]),
                          );
                        },
                      ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
                  child: Column(children: [
                    _totalLine('Subtotal (${qtyText(count)})', total.subtotal, widget.currency),
                    const SizedBox(height: 7),
                    _totalLine('IGV (${qtyText(widget.taxRate)}%)', total.tax, widget.currency),
                    const Divider(height: 26),
                    _totalLine('Total a cobrar', total.total, widget.currency, bold: true),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        key: const ValueKey('retail-continue-payment'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _purple,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: items.isEmpty ? null : () => Navigator.of(context).pop(true),
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
