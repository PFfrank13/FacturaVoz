import 'package:flutter/material.dart';

import '../models.dart';
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
    const bg = Color(0xFF0B1030);
    const panel = Color(0xFF1E244F);
    const accent = Color(0xFF9960FC);
    Widget action(IconData icon, String name, VoidCallback onTap, {Color? color}) {
      return Material(
        color: panel,
        borderRadius: BorderRadius.circular(15),
        child: ListTile(
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF55518C)),
            borderRadius: BorderRadius.circular(15),
          ),
          leading: Icon(icon, color: color ?? const Color(0xFFBE9DFF)),
          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFBEBADD)),
          onTap: onTap,
        ),
      );
    }

    return Theme(
      data: ThemeData.dark().copyWith(scaffoldBackgroundColor: bg),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pago confirmado'),
          backgroundColor: bg,
        ),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C3C3F), Color(0xFF2F226D), Color(0xFF5132AD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(children: [
                Container(
                  width: 86, height: 86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF24EFC5), width: 3),
                    boxShadow: [BoxShadow(color: const Color(0xFF24EFC5).withValues(alpha: .35), blurRadius: 28)],
                  ),
                  child: const Icon(Icons.check_rounded, color: Color(0xFF68FFE0), size: 56),
                ),
                const SizedBox(height: 18),
                const Text('Venta registrada y cobrada', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 6),
                Text(money(total, currency), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 36)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: accent.withValues(alpha: .2), borderRadius: BorderRadius.circular(50)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PosPaymentBrand(method, size: 30),
                    const SizedBox(width: 8),
                    Text('Cobrado con ${posMethodLabel(method)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
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
              () => _openDetail(context, share: true), color: const Color(0xFF45D78E)),
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
            const Text(
              'El pago registrado no equivale a la emisión SUNAT. '
              'Para emitir boleta o factura electrónica se necesitan RUC, SOL, '
              'certificado y configuración tributaria. Si falta alguno, se abrirá la configuración.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB5B8D7), fontSize: 12),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Nueva venta'),
            ),
          ]),
        ))),
      ),
    );
  }
}
