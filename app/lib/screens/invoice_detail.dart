import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/pdf_builder.dart';
import 'emit_sunat.dart';
import 'fiscal_setup.dart';
import '../services/api.dart';
import '../services/repo.dart';
import '../ui/widgets.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  InvoiceRecord? _inv;
  FiscalDoc? _fiscal;
  FiscalDoc? _note;
  FiscalCompany? _company;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Repo.getInvoice(widget.invoiceId);
      final f = await Repo.getFiscalDoc(widget.invoiceId);
      final c = await Repo.loadFiscalCompany();
      final n = f == null ? null : await Repo.getCreditNote(widget.invoiceId, f.legend);
      if (mounted) {
        setState(() {
          _inv = r;
          _fiscal = f;
          _note = n;
          _company = c;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _setStatus(String status, String title, String body) async {
    if (!await _confirm(title, body, 'Confirmar')) return;
    setState(() => _busy = true);
    try {
      await Repo.setStatus(widget.invoiceId, status);
      await _load();
    } catch (_) {
      _snack('No se pudo actualizar el estado.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emitSunat() async {
    final inv = _inv!;
    var company = _company;
    if (company == null) {
      final go = await _confirm('Configura la facturación electrónica',
          'Para emitir facturas y boletas válidas necesitas conectar tu RUC, usuario SOL y certificado digital.', 'Configurar');
      if (!go || !mounted) return;
      final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const FiscalSetupScreen()));
      if (done != true) return;
      await _load();
      company = _company;
      if (company == null || !mounted) return;
    }
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => EmitSunatScreen(invoice: inv, company: company!)));
    if (changed == true) await _load();
  }

  Future<void> _anular() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Anular con nota de crédito', style: Theme.of(c).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Se emite una nota de crédito por el importe total. El comprobante original queda registrado en SUNAT.',
                style: Theme.of(c).textTheme.bodySmall),
          ),
          ListTile(
            title: const Text('Anulación de la operación'),
            subtitle: const Text('La venta no se concretó'),
            onTap: () => Navigator.pop(c, '01'),
          ),
          ListTile(
            title: const Text('Devolución total'),
            subtitle: const Text('El cliente devolvió todo'),
            onTap: () => Navigator.pop(c, '06'),
          ),
        ]),
      ),
    );
    if (reason == null || !mounted) return;
    if (!await _confirm('¿Emitir la nota de crédito?', 'Esta acción se envía a SUNAT y no se puede deshacer.', 'Emitir nota')) return;
    setState(() => _busy = true);
    try {
      final r = await FiscalApi.creditNote(invoiceId: widget.invoiceId, reasonCode: reason);
      _snack(r.status == 'accepted'
          ? 'Nota de crédito ${r.number} aceptada por SUNAT.'
          : r.status == 'rejected'
              ? 'SUNAT rechazó la nota: ${r.message}'
              : 'SUNAT no respondió. Toca “Reintentar nota” para volver a enviarla.');
      await _load();
    } catch (e) {
      _snack(friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryNote() async {
    final code = (_note?.payload['codMotivo'] ?? '01') as String;
    setState(() => _busy = true);
    try {
      final r = await FiscalApi.creditNote(invoiceId: widget.invoiceId, reasonCode: code);
      _snack(r.status == 'accepted' ? 'Nota de crédito ${r.number} aceptada por SUNAT.' : 'SUNAT aún no la acepta: ${r.message}');
      await _load();
    } catch (e) {
      _snack(friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareNote() async {
    final inv = _inv!;
    final n = _note!;
    setState(() => _busy = true);
    try {
      final bytes = await buildInvoicePdf(inv, AppState.instance.profile!, fiscal: n);
      await Printing.sharePdf(bytes: bytes, filename: '${n.number}.pdf');
    } catch (_) {
      _snack('No se pudo generar el PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm('Eliminar borrador', 'Se eliminará esta factura. No se puede deshacer.', 'Eliminar')) return;
    setState(() => _busy = true);
    try {
      await Repo.deleteDraft(widget.invoiceId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _snack('No se pudo eliminar.');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final bytes = await buildInvoicePdf(inv, AppState.instance.profile!, fiscal: _fiscal);
      await Printing.sharePdf(bytes: bytes, filename: '${inv.number}.pdf');
    } catch (_) {
      _snack('No se pudo generar el PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final bytes = await buildInvoicePdf(inv, AppState.instance.profile!, fiscal: _fiscal);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(inv.number)),
          body: PdfPreview(
            build: (_) => bytes,
            pdfFileName: '${inv.number}.pdf',
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      ));
    } catch (_) {
      _snack('No se pudo generar el PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inv;
    return Scaffold(
      appBar: AppBar(title: Text(_fiscal?.number ?? inv?.number ?? 'Factura')),
      body: SafeArea(
        child: inv == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ticket(inv),
                  const SizedBox(height: 20),
                  // La vista previa embebida usa pdf.js en web (CDN de terceros); en web solo se descarga.
                  if (!kIsWeb) ...[
                    FilledButton.icon(onPressed: _busy ? null : _preview, icon: const Icon(Icons.picture_as_pdf), label: const Text('Ver PDF')),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: Icon(kIsWeb ? Icons.download : Icons.ios_share),
                    label: Text(kIsWeb ? 'Descargar PDF' : 'Compartir PDF'),
                  ),
                  const SizedBox(height: 8),
                  if (_fiscal == null || _fiscal!.status != 'accepted')
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _emitSunat,
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(_fiscal == null ? 'Emitir factura / boleta a SUNAT' : 'Reintentar envío a SUNAT'),
                    ),
                  if (_fiscal != null && _fiscal!.status == 'accepted' && (_note == null || _note!.status != 'accepted'))
                    OutlinedButton.icon(
                      onPressed: _busy ? null : (_note == null ? _anular : () => _retryNote()),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(_note == null ? 'Anular con nota de crédito' : 'Reintentar nota de crédito'),
                    ),
                  if (_note != null)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _shareNote,
                      icon: Icon(kIsWeb ? Icons.download : Icons.ios_share),
                      label: Text('PDF de la nota ${_note!.number}'),
                    ),
                  if (inv.status == 'draft' && _fiscal == null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _setStatus('sent', 'Marcar como enviada', 'Una nota de venta enviada ya no se puede editar ni eliminar.'),
                      child: const Text('Marcar como enviada (sin comprobante SUNAT)'),
                    ),
                  if (inv.status == 'sent' && _fiscal == null)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _setStatus('paid', 'Marcar como pagada', 'Se registrará la factura como pagada.'),
                      child: const Text('Marcar como pagada'),
                    ),
                  if (inv.status == 'draft' && _fiscal == null)
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      child: Text('Eliminar borrador', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _ticket(InvoiceRecord inv) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final f = _fiscal;
    final pillLabel = f == null ? statusLabel(inv.status) : '${fiscalStatusLabel(f.status)}${f.env == 'beta' ? ' · prueba' : ''}';
    final tone = f == null ? (inv.status == 'paid' ? PillTone.ok : PillTone.neutral) : StatusPill.toneForFiscal(f.status);
    return TicketPaper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f == null ? 'Nota de venta' : (f.docType == '01' ? 'Factura electrónica' : 'Boleta de venta electrónica'), style: t.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(f?.number ?? inv.number, style: t.textTheme.headlineMedium),
        const SizedBox(height: 10),
        StatusPill(pillLabel, tone: tone),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: StatusPill(
              _note!.status == 'accepted' ? 'Anulada · nota de crédito ${_note!.number}' : 'Nota de crédito ${_note!.number}: ${fiscalStatusLabel(_note!.status).toLowerCase()}',
              tone: _note!.status == 'accepted' ? PillTone.info : StatusPill.toneForFiscal(_note!.status),
            ),
          ),
        if (f != null && f.status != 'accepted' && f.sunatMessage.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(f.sunatMessage, style: t.textTheme.bodySmall)),
        const SizedBox(height: 20),
        Text(inv.clientName, style: t.textTheme.titleMedium),
        if (inv.clientTaxId.isNotEmpty) Text(inv.clientTaxId, style: t.textTheme.bodySmall),
        Text(displayDate(inv.issueDate), style: t.textTheme.bodySmall),
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 8),
        for (final i in inv.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.description, style: t.textTheme.bodyMedium),
                  Text('${qtyText(i.quantity)} × ${money(round2(i.unitPrice), inv.currency)}',
                      style: t.textTheme.bodySmall?.copyWith(color: muted)),
                ]),
              ),
              const SizedBox(width: 12),
              Money(money(i.amount, inv.currency), size: 14.5),
            ]),
          ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        DataRow2('Subtotal', money(inv.totals.subtotal, inv.currency)),
        DataRow2('${AppState.instance.profile?.taxLabel ?? 'Impuesto'} (${qtyText(inv.taxRate)}%)', money(inv.totals.tax, inv.currency)),
        const SizedBox(height: 4),
        DataRow2('Total', money(inv.totals.total, inv.currency), strong: true),
        if (inv.notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(inv.notes, style: t.textTheme.bodySmall),
        ],
      ]),
    );
  }
}
