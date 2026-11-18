import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';
import 'design_tokens.dart';

/// Usa el espacio realmente disponible (no la resolución física del dispositivo).
/// El panel se muestra solamente en Bodega/Tienda integrada al MainShell.
bool retailPosUseSideCart(double availableWidth) =>
    availableWidth.isFinite && availableWidth >= 900;

/// Vista del carrito con edición opcional del borrador. No crea pagos,
/// no cambia inventario ni altera identificadores idempotentes.
class RetailPosCartPane extends StatelessWidget {
  const RetailPosCartPane({
    super.key,
    required this.lines,
    required this.totals,
    required this.currency,
    required this.onReview,
    this.onQuantityChange,
  });

  final List<LineItem> lines;
  final Totals totals;
  final String currency;
  final VoidCallback? onReview;
  /// El padre aplica las mismas defensas de stock y cobro para cada cambio.
  final void Function(String productId, double delta)? onQuantityChange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ds = DsColors.of(context);
    final quantity = lines.fold<double>(0, (sum, line) => sum + line.quantity);
    return Container(
      key: const ValueKey('retail-pos-desktop-cart'),
      width: FvTokens.desktopCartWidth,
      margin: const EdgeInsets.fromLTRB(0, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(FvTokens.cardRadius),
        boxShadow: FvTokens.shadow(Theme.of(context).brightness),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 15),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.shopping_bag_outlined, color: ds.primaryText, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ticket actual', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(lines.isEmpty
                  ? 'Sin productos'
                  : '${qtyText(quantity)} ${quantity == 1 ? 'unidad' : 'unidades'} · ${lines.length} ${lines.length == 1 ? 'producto' : 'productos'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ])),
          ]),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: lines.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_shopping_cart_outlined, size: 42, color: cs.onSurfaceVariant),
                  const SizedBox(height: 13),
                  Text('Tu venta comienza aquí', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('Selecciona productos del catálogo o escanea su código.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                itemCount: lines.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final line = lines[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(line.description, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                        if (onQuantityChange != null && line.productId != null)
                          IconButton(
                            key: ValueKey('retail-pos-qty-remove-${line.productId}'),
                            onPressed: () => onQuantityChange!(line.productId!, -line.quantity),
                            tooltip: 'Quitar ${line.description} del carrito',
                            icon: const Icon(Icons.delete_outline_rounded),
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          ),
                      ]),
                      const SizedBox(height: 7),
                      Row(children: [
                        Expanded(child: Text('${qtyText(line.quantity)} × ${money(line.unitPrice, currency)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(money(line.amount, currency),
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ]),
                      if (onQuantityChange != null && line.productId != null) ...[
                        const SizedBox(height: 7),
                        Row(children: [
                          Expanded(child: Text('Cantidad',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
                          IconButton.filledTonal(
                            key: ValueKey('retail-pos-qty-minus-${line.productId}'),
                            tooltip: 'Reducir ${line.description}',
                            onPressed: () => onQuantityChange!(line.productId!,
                              line.quantity < 1 ? -line.quantity : -1.0),
                            icon: const Icon(Icons.remove_rounded),
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(qtyText(line.quantity),
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          IconButton.filledTonal(
                            key: ValueKey('retail-pos-qty-plus-${line.productId}'),
                            tooltip: 'Aumentar ${line.description}',
                            onPressed: () => onQuantityChange!(line.productId!, 1.0),
                            icon: const Icon(Icons.add_rounded),
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          ),
                        ]),
                      ],
                    ]),
                  );
                },
              ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _summary(context, 'Subtotal', totals.subtotal),
            const SizedBox(height: 7),
            _summary(context, 'IGV', totals.tax),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('Total', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              Flexible(child: Text(money(totals.total, currency),
                textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()]))),
            ]),
            const SizedBox(height: 15),
            FilledButton.icon(
              key: const ValueKey('retail-pos-desktop-charge'),
              onPressed: lines.isEmpty ? null : onReview,
              icon: const Icon(Icons.shopping_cart_checkout_rounded),
              label: const Text('Revisar y cobrar'),
              style: FilledButton.styleFrom(
                backgroundColor: FvTokens.emerald,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 54),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 7),
            Text('El pago se confirma en el siguiente paso.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  Widget _summary(BuildContext context, String title, double amount) {
    final t = Theme.of(context);
    return Row(children: [
      Expanded(child: Text(title, style: t.textTheme.bodySmall)),
      Text(money(amount, currency), style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}
