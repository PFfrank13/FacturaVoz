import 'package:flutter/material.dart';
import '../models.dart';
import '../logic/retail_money.dart';

/// Explicit confirmation of a payment recorded by the cashier, not a gateway approval.
class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({super.key, required this.total, required this.currency,
    required this.onConfirm, required this.onMore, this.pendingMethod, this.canCollect = true});
  final double total;
  final String currency;
  final String? pendingMethod;
  final bool canCollect;
  final ValueChanged<String> onConfirm;
  final VoidCallback onMore;
  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final _received = TextEditingController();
  late String _method = widget.pendingMethod ?? 'efectivo';
  bool _confirmed = false;
  @override
  void dispose() { _received.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingMethod != null;
    final received = parseCents(_received.text);
    final totalCents = centsFromLegacy(widget.total);
    final valid = pending || _method != 'efectivo' ||
        (received != null && received >= totalCents);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(pending ? 'Recuperar cobro pendiente' : 'Completar venta', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(money(widget.total, widget.currency), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (pending) const Text('Se consultará la misma operación. El carrito y el método de pago permanecen sin cambios.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final method in const ['efectivo', 'yape', 'plin', 'tarjeta', 'transferencia'])
            ChoiceChip(label: Text(paymentMethods[method]!), selected: _method == method,
              onSelected: pending ? null : (_) => setState(() => _method = method)),
        ]),
        const SizedBox(height: 16),
        if (_method == 'efectivo' && !pending) ...[
          TextField(controller: _received, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Efectivo recibido', hintText: '0.00'),
            onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          Text(valid ? 'Vuelto: ${money((received! - totalCents) / 100, widget.currency)}' : 'Ingresa un importe igual o mayor al total.'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(label: const Text('Exacto'), onPressed: () => setState(() => _received.text = (totalCents / 100).toStringAsFixed(2))),
            for (final bill in [10, 20, 50, 100])
              if (widget.currency == 'PEN' && bill * 100 >= totalCents)
                ActionChip(label: Text('S/ $bill'), onPressed: () => setState(() => _received.text = '$bill')),
          ]),
        ] else if (!pending)
          const Text('Confirma que recibiste el pago antes de registrarlo. Esta acción no verifica el pago con el banco.'),
        const SizedBox(height: 20),
        if (!widget.canCollect) const Text('Tu rol no permite registrar cobros. Puedes continuar a las opciones de comprobante.'),
        if (widget.canCollect) FilledButton.icon(onPressed: !valid || _confirmed ? null : () {
          setState(() => _confirmed = true);
          widget.onConfirm(_method);
        }, icon: const Icon(Icons.check_circle_outline),
          label: Text(pending ? 'Reintentar mismo cobro' : 'Confirmar cobro')),
        if (!pending) TextButton(onPressed: widget.onMore, child: const Text('Más opciones: cliente, factura o crédito')),
      ]),
    );
  }
}
