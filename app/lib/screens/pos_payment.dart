import 'package:flutter/material.dart';

import '../models.dart';
import '../models_pro.dart';
import '../services/pro_repo.dart';
import 'pos_payment_logic.dart';

/// Manual cashier confirmation only. A transfer/QR shown here does NOT
/// represent a bank webhook or an independently verified payment.
class PosPaymentApproval {
  const PosPaymentApproval(this.method, this.note);
  final String method;
  final String note;
}

Future<PosPaymentApproval?> confirmPosPayment(
  BuildContext context, {
  required String method,
  required String currency,
  required double total,
}) async {
  if (!const {'efectivo', 'yape', 'plin', 'tarjeta', 'transferencia'}.contains(method)) {
    return null;
  }
  PaySettings? merchant;
  if (method == 'yape' || method == 'plin' || method == 'transferencia') {
    try {
      merchant = await ProRepo.loadPaySettings();
    } catch (_) {
      // Fail closed: a cashier cannot confirm a payment to an unknown account.
      merchant = null;
    }
  }
  if (!context.mounted) return null;
  final amountCents = posMoneyToCents(total);
  final amount = money(total, currency);
  final account = switch (method) {
    'yape' => merchant?.yape ?? '',
    'plin' => merchant?.plin ?? '',
    'transferencia' => merchant?.bankAccount ?? '',
    _ => '',
  };
  final requiresAccount = method == 'yape' || method == 'plin' || method == 'transferencia';
  final label = switch (method) {
    'efectivo' => 'Efectivo',
    'yape' => 'Yape',
    'plin' => 'Plin',
    'tarjeta' => 'Tarjeta',
    _ => 'Transferencia',
  };
  final moneyInput = TextEditingController(text: total.toStringAsFixed(2));
  var manuallyVerified = false;
  PosPaymentApproval? approved;
  try {
    approved = await showDialog<PosPaymentApproval>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          final tenderCents = parsePosCents(moneyInput.text);
          final sufficient = tenderCents != null && tenderCents >= amountCents;
          final changeCents = sufficient
              ? posChangeDue(chargeCents: amountCents, tenderedCents: tenderCents)
              : 0;
          final ready = method == 'efectivo'
              ? sufficient
              : manuallyVerified && (!requiresAccount || account.trim().isNotEmpty);
          return AlertDialog(
            title: Text('Cobrar con $label'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Total: $amount', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  if (method == 'efectivo') ...[
                    TextField(
                      controller: moneyInput,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Efectivo recibido',
                        helperText: sufficient ? 'Vuelto: ${money(changeCents / 100, currency)}' : 'Ingresa al menos el total.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final value in <int>[
                        amountCents,
                        ((amountCents + 999) ~/ 1000) * 1000,
                        ((amountCents + 4999) ~/ 5000) * 5000,
                      ].toSet().where((value) => value >= amountCents))
                        ActionChip(
                          label: Text(money(value / 100, currency)),
                          onPressed: () {
                            moneyInput.text = (value / 100).toStringAsFixed(2);
                            setState(() {});
                          },
                        ),
                    ]),
                  ] else ...[
                    if (requiresAccount) ...[
                      Text(account.isEmpty ? 'No has configurado una cuenta $label.' : 'Cuenta del negocio: $account'),
                      if (merchant?.holder.isNotEmpty == true)
                        Text('Titular: ${merchant!.holder}'),
                      if (method == 'transferencia' && merchant?.bankName.isNotEmpty == true)
                        Text('Banco: ${merchant!.bankName}'),
                      if (account.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Configura la cuenta en Ajustes → Medios de cobro antes de registrar este pago.'),
                        ),
                    ],
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: manuallyVerified,
                      contentPadding: EdgeInsets.zero,
                      onChanged: account.isEmpty && requiresAccount
                          ? null
                          : (value) => setState(() => manuallyVerified = value ?? false),
                      title: Text(method == 'tarjeta' ? 'El POS confirmó el pago' : 'Comprobé el pago recibido'),
                      subtitle: const Text('Confirmación manual del cajero. No se verifica automáticamente en el banco.'),
                    ),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: ready ? () {
                  final note = method == 'efectivo'
                      ? 'Recibido ${money(tenderCents! / 100, currency)} · Vuelto ${money(changeCents / 100, currency)}'
                      : 'Pago $label confirmado manualmente por el cajero';
                  Navigator.pop(ctx, PosPaymentApproval(method, note));
                } : null,
                child: const Text('Confirmar cobro'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    moneyInput.dispose();
  }
  return approved;
}
