import 'package:flutter/material.dart';

import '../models.dart';
import '../ui/retail_visual.dart';
import '../ui/theme.dart';
import '../ui/glass_widgets.dart';
import '../ui/design_tokens.dart';
import '../ui/motion.dart';
import 'invoice_detail.dart';
import 'pos_payment.dart';
import 'retail_receipts.dart';

/// Shown only AFTER fast_checkout_atomic has committed on Supabase.
/// This screen never represents a bank webhook or a SUNAT CDR.
class PosPaymentSuccessScreen extends StatelessWidget {
  const PosPaymentSuccessScreen({
    super.key,
    required this.invoiceId,
    required this.method,
    required this.currency,
    required this.total,
  });

  final String invoiceId;
  final String method;
  final String currency;
  final double total;

  Future<void> _openDetail(BuildContext context, {String? doc, bool share = false, bool printTicket = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => InvoiceDetailScreen(
        invoiceId: invoiceId,
        autoEmitDocType: doc,
        autoSharePdf: share,
        autoPrint: printTicket,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = DsColors.of(context);
    Widget action(IconData icon, String name, VoidCallback onTap, {Color? color}) {
      return Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        child: ListTile(
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.line),
            borderRadius: BorderRadius.circular(15),
          ),
          leading: Icon(icon, color: color ?? c.primaryText),
          title: Text(name, style: t.textTheme.titleSmall?.copyWith(
            color: c.ink, fontWeight: FontWeight.w700)),
          trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
          onTap: onTap,
        ),
      );
    }

    return Scaffold(
        appBar: AppBar(flexibleSpace: const FvGlassTopBar(),
          title: const Text('Cobro registrado')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            RetailVisual.journey(step: 4, label: 'Comprobante y ticket'),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(FvTokens.sheetRadius),
                border: Border.all(color: c.line),
                boxShadow: FvTokens.shadow(t.brightness),
              ),
              child: Column(children: [
                const FvReceiptCheck(),
                const SizedBox(height: 18),
                Text('Venta registrada y cobrada', textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(money(total, currency), style: t.textTheme.displaySmall?.copyWith(
                  color: c.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: c.elevated, borderRadius: BorderRadius.circular(Radii.md)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    PosPaymentBrand(method, size: 30),
                    const SizedBox(width: 10),
                    Expanded(child: Text(method == 'efectivo'
                      ? 'Cobrado con Efectivo'
                      : '${posMethodLabel(method)} · verificado por el cajero',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium?.copyWith(color: c.ink, fontWeight: FontWeight.w700))),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            action(Icons.receipt_long_rounded, 'Emitir boleta',
              () => _openDetail(context, doc: '03')),
            const SizedBox(height: 9),
            action(Icons.description_rounded, 'Emitir factura',
              () => _openDetail(context, doc: '01')),
            const SizedBox(height: 9),
            action(Icons.chat_rounded, 'Compartir PDF (WhatsApp u otra app)',
              () => _openDetail(context, share: true), color: c.ok),
            const SizedBox(height: 9),
            action(Icons.article_outlined, 'Ver comprobante',
              () => _openDetail(context)),
            const SizedBox(height: 9),
            action(Icons.print_rounded, 'Imprimir ticket',
              () => _openDetail(context, printTicket: true)),
            const SizedBox(height: 9),
            action(Icons.history_rounded, 'Historial de comprobantes',
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const RetailReceiptsScreen(),
              ))),
            const SizedBox(height: 24),
            Text(
              'El cobro se registró tras la verificación del cajero; no se comprueba automáticamente con el banco. '
              'El pago registrado no equivale a la emisión SUNAT. '
              'Para emitir boleta o factura electrónica se necesitan RUC, SOL, '
              'certificado y configuración tributaria. Si falta alguno, se abrirá la configuración.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Nueva venta'),
            ),
          ]),
        ))),
    );
  }
}
