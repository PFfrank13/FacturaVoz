import 'package:flutter/material.dart';

import '../models.dart';
import '../ui/retail_visual.dart';
import '../ui/glass_widgets.dart';
import '../ui/design_tokens.dart';
import '../ui/motion.dart';
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
    return FvAurora(child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
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
              child: LayoutBuilder(builder: (context, area) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: RetailVisual.journey(step: 2, label: 'Revisar productos'),
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
                        itemCount: items.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, row) {
                          if (row == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                              child: Text('Revisa productos y cantidades',
                                style: t.textTheme.headlineSmall?.copyWith(fontSize: 23)),
                            );
                          }
                          final i = row - 1;
                          final item = items[i];
                          final id = item.productId;
                          final imagePath = widget.productImages[id] ?? '';
                          final fixtureAsset = widget.fixtureAssetPhotos[id] ?? '';
                          final dark = t.brightness == Brightness.dark;
                          final accent = dark ? FvTokens.emeraldDark : FvLuxe.jade;
                          Widget stepButton(int delta, IconData icon, String tooltip) =>
                            SizedBox.square(
                              dimension: 44,
                              child: FvTactileScale(
                                enabled: id != null,
                                pressedScale: .9,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: delta > 0 ? accent : Colors.transparent,
                                    foregroundColor: delta > 0
                                        ? (dark ? FvTokens.canvasDark : Colors.white)
                                        : t.colorScheme.onSurface,
                                  ),
                                  tooltip: tooltip,
                                  onPressed: id == null ? null : () {
                                    widget.onChangeQuantity(id, delta);
                                    setState(() {});
                                  },
                                  icon: Icon(icon, size: 20),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            );
                          return FvLiquidGlass(
                            key: id == null ? null : ValueKey(id),
                            radius: 26,
                            blur: 0,
                            strength: dark ? 1.5 : 1.4,
                            padding: const EdgeInsets.all(10),
                            child: Row(children: [
                              SizedBox(
                                width: 72, height: 80,
                                child: FvProductStudio(
                                  radius: 18,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
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
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 15)),
                                  const SizedBox(height: 3),
                                  Text('${money(round2(item.unitPrice * (1 + widget.taxRate / 100)), widget.currency)} c/u',
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: t.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                  DecoratedBox(
                                    decoration: ShapeDecoration(
                                      shape: StadiumBorder(side: BorderSide(
                                        color: dark ? const Color(0x33FFFFFF) : Colors.white, width: 1.1)),
                                      color: dark ? const Color(0x6615243A) : const Color(0xB3FFFFFF),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      stepButton(-1, Icons.remove_rounded, 'Quitar uno'),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(minWidth: 30),
                                        child: Center(child: FvQuantityText(qtyText(item.quantity),
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                                      ),
                                      stepButton(1, Icons.add_rounded, 'Agregar uno'),
                                    ]),
                                  ),
                                  const SizedBox(width: 8),
                                  // The line total shares the stepper row and
                                  // shrinks before the 44 pt controls do.
                                  Expanded(child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerEnd,
                                    // Lo que se cobra por esta línea: valor + su IGV (mismo redondeo que el total).
                                    child: Text(money(round2(item.amount + round2(item.amount * widget.taxRate / 100)), widget.currency),
                                      maxLines: 1,
                                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                                        fontFamily: 'Inter', letterSpacing: -.4,
                                        fontFeatures: const [FontFeature.tabularFigures()])),
                                  )),
                                  ]),
                                ],
                              )),
                            ]),
                          );
                        },
                      ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: area.maxHeight * .62),
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: FvLiquidGlass(
                  radius: 30,
                  tone: Brightness.dark,
                  strength: 2.2,
                  blur: 24,
                  tint: const Color(0xFF19D3A2),
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                  child: Theme(
                    data: t.copyWith(
                      textTheme: t.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
                      colorScheme: t.colorScheme.copyWith(onSurface: Colors.white)),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(color: Colors.white),
                      child: Column(children: [
                    _totalLine('Valor de venta (${qtyText(count)})', total.subtotal, widget.currency),
                    const SizedBox(height: 7),
                    _totalLine('IGV ${qtyText(widget.taxRate)}% (ya incluido)', total.tax, widget.currency),
                    const Divider(height: 26, color: Color(0x2EFFFFFF)),
                    _totalLine('Total a cobrar', total.total, widget.currency, bold: true),
                    const SizedBox(height: 16),
                    if (widget.canSellOnCredit && items.isNotEmpty) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey('retail-credit-sale'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0x14FFFFFF),
                            side: const BorderSide(color: Color(0x40FFFFFF)),
                          ),
                          onPressed: () => Navigator.of(context).pop(RetailCartAction.credit),
                          icon: const Icon(Icons.person_outline_rounded),
                          label: const Text('Registrar venta a fiado (cliente requerido)'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FvTactileScale(
                        enabled: items.isNotEmpty,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(FvTokens.fieldRadius),
                            boxShadow: items.isEmpty ? null : const [
                              BoxShadow(color: Color(0x7319D3A2), blurRadius: 22, offset: Offset(0, 8)),
                            ],
                          ),
                          child: FilledButton.icon(
                            key: const ValueKey('retail-continue-payment'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3EE6B0),
                              foregroundColor: const Color(0xFF04201A),
                            ),
                            onPressed: items.isEmpty ? null : () => Navigator.of(context).pop(RetailCartAction.collect),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('Continuar al pago',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ),
                  ]))),
                  ),
                ),
                ),
              ])),
            ),
          ),
        ),
    ));
  }

  Widget _totalLine(String label, double value, String currency, {bool bold = false}) {
    return Row(children: [
      Expanded(child: Text(label,
        style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          fontSize: bold ? 16 : 13.5,
          color: bold ? Colors.white : const Color(0xFFC3CFDF)))),
      const SizedBox(width: 10),
      Flexible(child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: Text(money(value, currency),
          style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            fontSize: bold ? 28 : 14, fontFamily: 'Inter',
            letterSpacing: bold ? -1.1 : 0, color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()])),
      ))),
    ]);
  }
}
