// Del cuaderno a la factura (Fase 8 · módulo 1): foto del cuaderno de ventas, una nota escrita a mano o una captura
// de un pedido por WhatsApp → la IA propone la venta → la revisas y la emites. Nunca se emite nada sin tu revisión.
// (No toca el escáner de comprobantes de proveedores: es otra pantalla y otro servicio.)
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../models_v2.dart';
import '../services/v2_api.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  bool _busy = false;
  String _error = '';
  NotebookSale? _sale;

  Future<void> _pick(ImageSource src) async {
    setState(() {
      _error = '';
      _sale = null;
    });
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1800, imageQuality: 78);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _busy = true);
      final sale = await V2Api.notebook(bytes);
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _sale = sale;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      setState(() {
        _busy = false;
        _error = friendly(e);
      });
    }
  }

  Future<void> _use() async {
    final s = _sale;
    final p = AppState.instance.profile;
    if (s == null || p == null) return;
    final rate = p.taxRate ?? 18;
    final draft = InvoiceDraft(
      clientName: s.clientName,
      clientTaxId: s.clientDoc,
      taxRate: rate,
      currency: p.currency.isEmpty ? 'PEN' : p.currency,
      notes: s.notes,
      transcript: 'Leído de una foto',
      items: [
        for (final it in s.items)
          // Si el cuaderno anota precios CON IGV (lo normal en bodegas), se pasa a precio sin IGV para que el total coincida.
          LineItem(description: it.description, quantity: it.quantity, unitPrice: s.pricesIncludeTax && rate > 0 ? round2(it.unitPrice / (1 + rate / 100)) : it.unitPrice),
      ],
    );
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewInvoiceScreen(initial: draft)));
    AppState.instance.bump();
    if (id != null && mounted) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id, sendCopy: true)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = _sale;
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final total = s == null ? 0.0 : s.items.fold(0.0, (a, i) => a + i.quantity * i.unitPrice);
    return Scaffold(
      appBar: AppBar(title: const Text('Del cuaderno a la factura')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Reveal(
          child: SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.menu_book_rounded, size: 44, color: Brand.goldDeep),
              const SizedBox(height: 8),
              Text('Toma una foto de tu cuaderno, una nota o un pedido de WhatsApp', textAlign: TextAlign.center, style: t.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Que se vea una sola venta, con buena luz. Revisarás todo antes de emitir.', textAlign: TextAlign.center, style: t.textTheme.bodySmall),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: const Text('Cámara'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded), label: const Text('Galería'))),
              ]),
            ]),
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 24),
          const Center(child: AiOrb(size: 110, thinking: true)),
          const SizedBox(height: 8),
          Center(child: Text('Leyendo la foto…', style: t.textTheme.titleSmall)),
        ],
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Brand.bad))),
        if (s != null) ...[
          const SizedBox(height: 16),
          Reveal(
            child: SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.clientName.isEmpty ? 'Cliente: (sin nombre)' : s.clientName, style: t.textTheme.titleMedium)),
                  TagChip('${(s.confidence * 100).round()}% seguro', color: s.confidence >= 0.8 ? Brand.ok : Brand.warn, icon: Icons.auto_awesome_rounded),
                ]),
                if (s.clientDoc.isNotEmpty) Text('Doc.: ${s.clientDoc}', style: t.textTheme.bodySmall),
                if (s.handwritten)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(Icons.edit_note_rounded, color: Brand.warn),
                      SizedBox(width: 6),
                      Expanded(child: Text('Escrito a mano: revisa bien cantidades y precios.', style: TextStyle(color: Brand.warn, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                const Divider(height: 22),
                if (s.items.isEmpty) const Text('No encontré productos con precio. Prueba con otra foto o escríbela por voz.'),
                for (final it in s.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${qtyText(it.quantity)} × ${it.description}')),
                      Money(money(it.quantity * it.unitPrice, cur)),
                    ]),
                  ),
                const Divider(height: 22),
                Row(children: [
                  Expanded(child: Text(s.pricesIncludeTax ? 'Total (precios con IGV)' : 'Subtotal (sin IGV)', style: t.textTheme.titleSmall)),
                  Money(money(total, cur), size: 18, weight: FontWeight.w800),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          if (s.items.isNotEmpty) GradientButton(label: 'Revisar y emitir', icon: Icons.arrow_forward_rounded, onPressed: _use),
        ],
      ]),
    );
  }
}
