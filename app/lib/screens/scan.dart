import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../errors.dart';
import '../finance.dart';
import '../models.dart';
import '../models_pro.dart';
import '../services/pro_api.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'expenses.dart';
import 'new_invoice.dart';

/// Elige cámara o galería y devuelve la foto comprimida (~1600 px, JPG) o null.
Future<Uint8List?> pickPhoto(BuildContext context, {bool preferGallery = false}) async {
  final source = kIsWeb
      ? ImageSource.gallery
      : await showModalBottomSheet<ImageSource>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Tomar foto'),
                subtitle: preferGallery ? null : const Text('De frente, con buena luz y sin cortes'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Elegir de la galería'),
                subtitle: preferGallery ? const Text('Ideal para capturas de pantalla de Yape o Plin') : null,
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ]),
          ),
        );
  if (source == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (x == null) return null;
    return await x.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Escáner de comprobantes: foto de una factura o boleta de papel → la IA extrae todo → gasto o venta.
/// Devuelve true (pop) si se guardó algo.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Uint8List? _photo;
  DocScan? _doc;
  String? _error;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final bytes = await pickPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() {
      _photo = bytes;
      _doc = null;
      _error = null;
      _reading = true;
    });
    try {
      final d = await ScanApi.document(bytes);
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _doc = d;
        _reading = false;
      });
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      setState(() {
        _error = friendly(e);
        _reading = false;
      });
    }
  }

  Future<void> _asExpense() async {
    final d = _doc!;
    final saved = await showExpenseSheet(
      context,
      prefill: Expense(
        spentOn: d.issueDate.isEmpty ? todayIso() : d.issueDate,
        category: d.category,
        description: d.items.isNotEmpty ? d.items.first.description + (d.items.length > 1 ? ' y ${d.items.length - 1} más' : '') : (d.supplierName.isEmpty ? 'Compra' : 'Compra a ${d.supplierName}'),
        total: d.total,
        tax: d.tax ?? 0,
        currency: d.currency,
        supplierName: d.supplierName,
        supplierTaxId: d.supplierTaxId,
        docNumber: d.docNumber,
        source: 'scan',
      ),
    );
    if (saved && mounted) {
      showSuccess(context, 'Gasto guardado');
      Navigator.of(context).pop(true);
    }
  }

  /// Comprobante de VENTA hecho a mano (talonario): se digitaliza como factura nueva.
  Future<void> _asSale() async {
    final d = _doc!;
    final p = AppState.instance.profile;
    if (p == null) return;
    // Los precios del papel suelen incluir IGV: si el total coincide con subtotal + IGV, se usan los valores sin IGV.
    final rate = p.taxRate ?? 18;
    final items = d.items.isNotEmpty
        ? d.items.map((i) => LineItem(description: i.description, quantity: i.quantity, unitPrice: i.unitPrice)).toList()
        : [LineItem(description: 'Venta según comprobante ${d.docNumber}'.trim(), quantity: 1, unitPrice: round2((d.subtotal ?? d.total / (1 + rate / 100))))];
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => NewInvoiceScreen(
        initial: InvoiceDraft(
          clientName: d.clientName,
          clientTaxId: d.clientTaxId,
          taxRate: (d.tax ?? 0) > 0 ? rate : 0,
          currency: d.currency,
          notes: d.docNumber.isEmpty ? 'Digitalizada desde foto' : 'Digitalizada desde foto (${d.docNumber})',
          items: items,
        ),
      ),
    ));
    if (id != null && mounted) {
      AppState.instance.bump();
      showSuccess(context, 'Venta digitalizada');
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear comprobante')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_photo == null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(children: [
                const AiOrb(size: 140),
                const SizedBox(height: 12),
                Text('Toma una foto de la factura o boleta', textAlign: TextAlign.center, style: t.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('La IA lee proveedor, RUC, fecha, montos e IGV. Tú solo revisas.', textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 22),
                GradientButton(label: 'Tomar o elegir foto', icon: Icons.photo_camera_rounded, onPressed: _pick),
              ]),
            )
          else ...[
            Reveal(child: _ScanPreview(bytes: _photo!, scanning: _reading)),
            const SizedBox(height: 16),
            if (_reading)
              Center(child: Text('Leyendo con IA…', style: t.textTheme.titleMedium))
            else if (_error != null) ...[
              SoftCard(color: Brand.bad.withValues(alpha: 0.08), child: Text(_error!, style: const TextStyle(color: Brand.bad))),
              const SizedBox(height: 12),
              GradientButton(label: 'Intentar con otra foto', icon: Icons.refresh_rounded, onPressed: _pick),
            ] else if (d != null) ...[
              Reveal(index: 1, child: _result(context, d)),
              const SizedBox(height: 16),
              Reveal(index: 2, child: GradientButton(label: 'Guardar como gasto', icon: Icons.shopping_bag_rounded, onPressed: _asExpense)),
              const SizedBox(height: 10),
              Reveal(
                index: 3,
                child: OutlinedButton.icon(onPressed: _asSale, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Es una venta mía: digitalizarla')),
              ),
              TextButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_camera_rounded), label: const Text('Tomar otra foto')),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _result(BuildContext context, DocScan d) {
    final t = Theme.of(context);
    final conf = (d.confidence * 100).round();
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(d.supplierName.isEmpty ? 'Proveedor no legible' : d.supplierName, style: t.textTheme.titleMedium)),
          StatusPill('Lectura $conf %', tone: conf >= 75 ? PillTone.ok : (conf >= 50 ? PillTone.warn : PillTone.bad)),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            if (d.docType.isNotEmpty && d.docType != 'otro') d.docType[0].toUpperCase() + d.docType.substring(1),
            if (d.docNumber.isNotEmpty) d.docNumber,
            if (d.supplierTaxId.isNotEmpty) 'RUC ${d.supplierTaxId}',
            if (d.issueDate.isNotEmpty) displayDate(d.issueDate),
          ].join(' · '),
          style: t.textTheme.bodySmall,
        ),
        if (d.clientName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Cliente: ${d.clientName}', style: t.textTheme.bodySmall)),
        const SizedBox(height: 12),
        for (final i in d.items.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text('${qtyText(i.quantity)} × ${i.description}', maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium)),
              Money(money(i.amount, d.currency), size: 14),
            ]),
          ),
        if (d.items.length > 8) Text('y ${d.items.length - 8} líneas más', style: t.textTheme.bodySmall),
        const Divider(height: 22),
        if (d.subtotal != null) DataRow2('Subtotal', money(d.subtotal!, d.currency)),
        if (d.tax != null) DataRow2('IGV', money(d.tax!, d.currency)),
        DataRow2('Total', money(d.total, d.currency), strong: true),
        const SizedBox(height: 6),
        Text('Categoría sugerida: ${expenseCategories[d.category] ?? d.category}', style: t.textTheme.bodySmall),
      ]),
    );
  }
}

/// Foto con un "láser" que la recorre mientras la IA lee.
class _ScanPreview extends StatefulWidget {
  const _ScanPreview({required this.bytes, required this.scanning});
  final Uint8List bytes;
  final bool scanning;

  @override
  State<_ScanPreview> createState() => _ScanPreviewState();
}

class _ScanPreviewState extends State<_ScanPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: Stack(children: [
          Positioned.fill(child: Image.memory(widget.bytes, fit: BoxFit.cover, gaplessPlayback: true)),
          if (widget.scanning) ...[
            Positioned.fill(child: ColoredBox(color: Brand.indigo.withValues(alpha: 0.18))),
            if (!reduceMotion(context))
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Align(
                  alignment: Alignment(0, -1 + 2 * Curves.easeInOut.transform(_c.value)),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Brand.gold,
                      boxShadow: [BoxShadow(color: Brand.gold.withValues(alpha: 0.8), blurRadius: 18, spreadRadius: 4)],
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 340, width: double.infinity),
        ]),
      ),
    );
  }
}

/// Conciliación por foto: captura de Yape/Plin/transferencia → la IA lee monto, pagador y operación →
/// se propone la factura que corresponde → un toque registra el cobro.
Future<bool> reconcileFromPhoto(BuildContext context, List<InvoiceRecord> receivables) async {
  final bytes = await pickPhoto(context, preferGallery: true);
  if (bytes == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  PaymentScan? p;
  String? error;
  final reading = ScanApi.payment(bytes);
  // Diálogo de espera (se cierra al terminar la lectura).
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AiOrb(size: 110, thinking: true),
            SizedBox(height: 10),
            Text('Leyendo la constancia…', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    },
  );
  try {
    p = await reading;
  } catch (e) {
    error = friendly(e);
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  final pay = p;
  if (!context.mounted) return false;
  if (pay == null || pay.amount <= 0) {
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'No pude leer el monto. Prueba con una captura más nítida.')));
    return false;
  }
  final today = todayIso();
  final candidates = matchPayment(pay, receivables, today);
  final picked = await showModalBottomSheet<MatchCandidate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
            Text('${money(pay.amount, pay.currency)} por ${paymentMethods[pay.app] ?? 'transferencia'}', style: t.textTheme.titleLarge),
            Text(
              [if (pay.payerName.isNotEmpty) 'De ${pay.payerName}', if (pay.operationCode.isNotEmpty) 'op. ${pay.operationCode}', if (pay.date.isNotEmpty) displayDate(pay.date)].join(' · '),
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (candidates.isEmpty)
              const Text('No encontré una factura por cobrar que coincida con este pago. Regístralo desde la factura correspondiente.')
            else ...[
              Text('¿A qué factura corresponde?', style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final (i, c) in candidates.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Pressable(
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: i == 0 ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Radii.lg),
                        border: i == 0 ? Border.all(color: t.colorScheme.primary, width: 1.5) : null,
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c.invoice.clientName, style: t.textTheme.titleSmall)),
                          Money(money(c.invoice.balance, c.invoice.currency), size: 15, weight: FontWeight.w700),
                        ]),
                        Text('${c.invoice.fiscalNumber ?? c.invoice.number} · ${c.reasons.join(' · ')}', style: t.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(value: c.score / 100, minHeight: 6),
                        ),
                        if (i == 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Coincidencia más probable', style: t.textTheme.labelSmall)),
                      ]),
                    ),
                  ),
                ),
            ],
          ]),
        ),
      );
    },
  );
  if (picked == null || !context.mounted) return false;
  final inv = picked.invoice;
  final amount = round2(pay.amount > inv.balance ? inv.balance : pay.amount);
  try {
    await Repo.addPayment(
      invoiceId: inv.id,
      amount: amount,
      method: const {'yape', 'plin', 'transferencia'}.contains(pay.app) ? pay.app : 'otro',
      note: pay.operationCode.isEmpty ? 'Conciliado por foto' : 'Conciliado por foto · op. ${pay.operationCode}',
    );
    if (inv.balance - amount <= 0.004) {
      try {
        await Repo.setStatus(inv.id, 'paid');
      } catch (_) {}
    }
    if (context.mounted) showSuccess(context, 'Cobro conciliado');
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo registrar. ${friendly(e)}')));
    return false;
  }
}
