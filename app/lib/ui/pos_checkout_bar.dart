import 'package:flutter/material.dart';
import '../models.dart';

/// The checkout action has its own row so it stays reachable with large text.
class PosCheckoutBar extends StatelessWidget {
  const PosCheckoutBar({super.key, required this.count, required this.total,
    required this.currency, required this.onDetails, required this.onCharge,
    required this.onClear, this.clearLabel = 'Vaciar', this.pending = false});
  final double count, total;
  final String currency, clearLabel;
  final VoidCallback? onCharge, onClear;
  final VoidCallback onDetails;
  final bool pending;
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: TextButton(onPressed: onDetails,
          child: Text('${qtyText(count)} productos · Ver carrito'))),
        TextButton(onPressed: onClear, child: Text(clearLabel)),
      ]),
      FilledButton.icon(onPressed: onCharge,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        icon: const Icon(Icons.point_of_sale_rounded),
        label: Text('${pending ? 'Recuperar cobro' : 'Cobrar'} · ${money(total, currency)}', textAlign: TextAlign.center)),
    ]),
  ));
}
