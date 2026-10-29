import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/pdf_builder.dart';
import 'emit_sunat.dart';
import 'fiscal_setup.dart';
import 'payments_card.dart';
import '../services/api.dart';
import '../services/pro_repo.dart';
import '../services/repo.dart';
import '../ui/motion.dart';
import 'recurring.dart';
import 'share_sheet.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../access.dart';
import '../config.dart';
import '../services/print/ticket_printer.dart';
import '../services/v2_repo.dart';
import 'owner_control.dart' show ensureOwnerPin;

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId, this.sendCopy = false});
  final String invoiceId;

  /// true al venir de crear la factura: envía una copia al correo de la cuenta.
  final bool sendCopy;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  InvoiceRecord? _inv;
  FiscalDoc? _fiscal;
  FiscalDoc? _note;
  FiscalCompany? _company;
  String? _error;
  bool _copySent = false;
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
        if (widget.sendCopy && !_copySent) {
          _copySent = true;
          _sendOwnCopy();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ───── v2.0: marca del emisor (logo, plantilla, color) para PDF y ticket ─────
  PdfBrand? _brand;
  Map<String, dynamic> _branding = const {};

  Future<PdfBrand> _loadBrand() async {
    if (_brand != null) return _brand!;
    _branding = await V2Repo.branding();
    final logo = await V2Repo.download(_branding['logo_path'] as String?);
    return _brand = PdfBrand(logo: logo, template: (_branding['pdf_template'] ?? 'clasico') as String, color: PdfBrand.parseHex(_branding['brand_color'] as String?));
  }

  Future<Uint8List> _pdf({FiscalDoc? fiscal}) async => buildInvoicePdf(_inv!, AppState.instance.profile!, fiscal: fiscal, brand: await _loadBrand());

  /// Ticket térmico 58/80 mm: Bluetooth o red (ESC/POS) o PDF de rollo. Si la impresora falla, ofrece el PDF.
  Future<void> _printTicket() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final brand = await _loadBrand();
      final cfg = await PrinterStore.load(orgWidth: (_branding['ticket_width'] as num?)?.toInt());
      final f = _fiscal;
      final data = f != null && f.status != 'rejected' ? ticketFromFiscal(f) : ticketFromInternal(inv, AppState.instance.profile!);
      if (cfg.kind == 'pdf') {
        final pdf = await buildTicketPdf(data, width: cfg.width, logo: brand.logo);
        await Printing.layoutPdf(name: 'ticket-${f?.number ?? inv.number}.pdf', onLayout: (_) => pdf);
      } else {
        final logo = await logoRaster(brand.logo, cfg.width == 58 ? 256 : 384);
        await sendEscPos(cfg, buildEscPosTicket(data, width: cfg.width, logo: logo, nativeQr: cfg.nativeQr, openDrawer: cfg.openDrawer));
        if (mounted) showSuccess(context, 'Ticket impreso', icon: Icons.print_rounded);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(e is StateError ? e.message : 'No se pudo imprimir. ${friendly(e)}'),
        action: SnackBarAction(
          label: 'Ticket PDF',
          onPressed: () async {
            final inv2 = _inv!;
            final f = _fiscal;
            final data = f != null && f.status != 'rejected' ? ticketFromFiscal(f) : ticketFromInternal(inv2, AppState.instance.profile!);
            final pdf = await buildTicketPdf(data, width: 80, logo: _brand?.logo);
            await Printing.layoutPdf(name: 'ticket.pdf', onLayout: (_) => pdf);
          },
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Portal del cliente: ve y descarga sus comprobantes (PDF, XML, CDR) y su historial con un enlace privado.
  Future<void> _portal() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final token = await V2Repo.portalToken(inv.id);
      if (!mounted) return;
      setState(() => _busy = false);
      final business = AppState.instance.activeOrg?.name ?? '';
      await shareLinkSheet(
        context,
        title: 'Comprobante para tu cliente',
        subtitle: 'Un enlace privado donde ve, imprime o descarga este comprobante (y su historial con tu negocio). Sin cuentas ni contraseñas.',
        url: '${Config.apiBase}/portal/$token',
        message: 'Hola ${inv.clientName == '—' ? '' : inv.clientName}, aquí tienes tu comprobante ${_fiscal?.number ?? inv.number} de $business:',
      );
    } catch (e) {
      _snack(V2Repo.missingHint(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _survey() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final token = await V2Repo.surveyToken(inv.id);
      if (!mounted) return;
      setState(() => _busy = false);
      await shareLinkSheet(
        context,
        title: 'Encuesta de satisfacción',
        subtitle: 'Tu cliente responde de 1 a 5 estrellas en 10 segundos. Si algo salió mal, te avisamos.',
        url: '${Config.apiBase}/encuesta/$token',
        message: '¡Gracias por tu compra en ${AppState.instance.activeOrg?.name ?? 'nuestro negocio'}! ¿Nos cuentas cómo te fue? Toma 10 segundos:',
      );
    } catch (e) {
      _snack(V2Repo.missingHint(e));
      if (mounted) setState(() => _busy = false);
    }
  }

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
    if (changed == true) {
      await _load();
      if (_fiscal?.status == 'accepted') _sendOwnCopy();
    }
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
    // Antifraude: si la empresa tiene PIN del dueño, se pide antes de anular (el servidor lo vuelve a exigir).
    if (!await ensureOwnerPin(context, reason: 'Para anular un comprobante se necesita el PIN del dueño.') || !mounted) return;
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
    final n = _note!;
    setState(() => _busy = true);
    try {
      final bytes = await _pdf(fiscal: n);
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
      final bytes = await _pdf(fiscal: _fiscal);
      await Printing.sharePdf(bytes: bytes, filename: '${inv.number}.pdf');
    } catch (_) {
      _snack('No se pudo generar el PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Copia silenciosa al correo con el que el usuario inició sesión (si el servidor tiene correo configurado).
  Future<void> _sendOwnCopy() async {
    final inv = _inv;
    if (inv == null) return;
    try {
      final bytes = await _pdf(fiscal: _fiscal);
      await EmailApi.send(invoiceId: inv.id, pdf: bytes);
      if (mounted) _snack('Te enviamos una copia a tu correo.');
    } catch (_) {
      // Best-effort: si el correo no está configurado no molestamos al usuario.
    }
  }

  Future<void> _email() async {
    final inv = _inv!;
    final ctrl = TextEditingController(text: inv.clientEmail);
    final to = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Enviar por correo', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('Se adjunta el PDF de ${_fiscal?.number ?? inv.number}. Tú también recibes una copia en el correo con el que entraste.', style: Theme.of(c).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo del cliente', prefixIcon: Icon(Icons.alternate_email_rounded)),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => Navigator.pop(c, ctrl.text), icon: const Icon(Icons.send_rounded), label: const Text('Enviar')),
        ]),
      ),
    );
    disposeAfterClose([ctrl]);
    if (to == null || to.trim().isEmpty) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(to.trim())) {
      _snack('Ese correo no parece válido.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _pdf(fiscal: _fiscal);
      await EmailApi.send(invoiceId: inv.id, to: to, pdf: bytes);
      _snack('Correo enviado a ${to.trim()} (y copia para ti)');
      if (to.trim().toLowerCase() != inv.clientEmail.toLowerCase()) Repo.setClientEmail(inv.id, to);
    } catch (e) {
      if (e is AppException && e.code == 'resend_domain' && mounted) {
        // El correo está en modo de prueba (sin dominio verificado): solo llega al dueño de la cuenta de Resend.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 10),
            content: const Text('El envío automático aún no puede escribir a tus clientes (falta verificar el dominio de correo). Mientras tanto envía el PDF tú mismo.'),
            action: SnackBarAction(label: 'Compartir PDF', onPressed: _share),
          ));
      } else {
        _snack(friendly(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Enlace de cobro: el cliente ve el saldo y paga con Yape, Plin, transferencia o tarjeta; o avisa "ya pagué".
  Future<void> _payLink() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final url = await ProRepo.payLinkUrl(inv.id);
      if (!mounted) return;
      setState(() => _busy = false);
      final business = AppState.instance.activeOrg?.name ?? AppState.instance.profile?.businessName ?? '';
      final shared = await shareLinkSheet(
        context,
        title: 'Enlace de cobro',
        subtitle: 'Tu cliente verá el saldo y cómo pagarte. Si paga con tarjeta el cobro se registra solo; si paga por Yape o Plin, te avisa y lo confirmas con un toque.',
        url: url,
        message: 'Hola ${inv.clientName == '—' ? '' : inv.clientName}, te comparto el comprobante ${_fiscal?.number ?? inv.number} de $business. Saldo: ${money(inv.balance, inv.currency)}. Puedes pagarlo aquí:',
      );
      if (shared) Haptics.success();
    } catch (e) {
      _snack(ProRepo.isMissingMigration(e) ? 'Falta ejecutar la migración 20261101_negocio_pro.sql en Supabase.' : friendly(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Crea una nota de venta nueva (borrador) con los mismos datos, para cobrar de nuevo al mismo cliente.
  Future<void> _duplicate() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final id = await Repo.duplicateInvoice(inv);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)));
    } catch (e) {
      _snack('No se pudo duplicar. ${friendly(e)}');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final bytes = await _pdf(fiscal: _fiscal);
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
            ? Center(
                child: _error == null
                    ? const SingleChildScrollView(padding: EdgeInsets.all(16), child: SkeletonList(count: 3))
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: SoftCard(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.cloud_off_rounded, color: Brand.bad, size: 34),
                            const SizedBox(height: 12),
                            Text('No pudimos abrir el comprobante', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () {
                                setState(() => _error = null);
                                _load();
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                          ]),
                        ),
                      ),
              )
            : ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
                padding: const EdgeInsets.all(16),
                children: [
                  Reveal(child: _ticket(inv)),
                  const SizedBox(height: 20),
                  // La vista previa embebida usa pdf.js en web (CDN de terceros); en web solo se descarga.
                  Reveal(
                    index: 2,
                    child: Row(children: [
                      if (!kIsWeb) Expanded(child: _quick(Icons.picture_as_pdf_rounded, 'Ver PDF', _preview)),
                      if (!kIsWeb) const SizedBox(width: 10),
                      Expanded(child: _quick(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, kIsWeb ? 'Descargar' : 'Compartir', _share)),
                      const SizedBox(width: 10),
                      Expanded(child: _quick(Icons.mail_outline_rounded, 'Correo', _email)),
                      const SizedBox(width: 10),
                      Expanded(child: _quick(Icons.copy_all_rounded, 'Duplicar', _duplicate)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Reveal(
                    index: 2,
                    child: Row(children: [
                      Expanded(child: _quick(Icons.print_rounded, 'Ticket', _printTicket)),
                      const SizedBox(width: 10),
                      if (Access.instance.has('portal_cliente')) ...[
                        Expanded(child: _quick(Icons.link_rounded, 'Enlace', _portal)),
                        const SizedBox(width: 10),
                      ],
                      if (Access.instance.has('encuestas') && inv.status != 'draft')
                        Expanded(child: _quick(Icons.sentiment_satisfied_alt_rounded, 'Encuesta', _survey))
                      else
                        const Expanded(child: SizedBox()),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (inv.status != 'draft' && _fiscal?.status != 'rejected') ...[
                    Reveal(index: 3, child: PaymentsCard(key: ValueKey('${inv.id}-${inv.status}'), invoice: inv, onChanged: _load)),
                    const SizedBox(height: 10),
                    if (inv.status == 'sent' && inv.balance > 0.004 && _note?.status != 'accepted') ...[
                      Reveal(
                        index: 4,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _payLink,
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('Enviar enlace de cobro'),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                  if (inv.items.isNotEmpty && _fiscal?.status != 'rejected') ...[
                    Reveal(
                      index: 5,
                      child: TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await showRecurringEditor(context, from: inv);
                                if (ok && context.mounted) showSuccess(context, 'Se facturará cada mes');
                              },
                        icon: const Icon(Icons.event_repeat_rounded),
                        label: const Text('Facturar esto cada mes'),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (inv.imported || inv.voided)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        inv.voided
                            ? 'Comprobante anulado: no cuenta como venta.'
                            : 'Importado de tu sistema anterior: ya se emitió allá, por eso no se envía a SUNAT desde aquí.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (!inv.imported && !inv.voided && (_fiscal == null || _fiscal!.status != 'accepted'))
                    GradientButton(
                      onPressed: _busy ? null : _emitSunat,
                      icon: Icons.verified_rounded,
                      busy: _busy,
                      label: _fiscal == null ? 'Emitir a SUNAT' : 'Reintentar envío a SUNAT',
                    ),
                  const SizedBox(height: 8),
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
                  if (inv.status == 'draft' && _fiscal == null && !inv.imported)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _setStatus('sent', 'Marcar como enviada', 'Una nota de venta enviada ya no se puede editar ni eliminar.'),
                      child: const Text('Marcar como enviada (sin comprobante SUNAT)'),
                    ),
                  if (inv.status == 'sent' && _fiscal == null && !inv.voided && !inv.isCreditNote)
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

  Widget _quick(IconData icon, String label, VoidCallback onTap) {
    final t = Theme.of(context);
    return Pressable(
      onTap: _busy ? null : onTap,
      child: Opacity(
        opacity: _busy ? 0.5 : 1,
        child: SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 14),
          radius: 20,
          child: Column(children: [
            Icon(icon, color: t.colorScheme.primary),
            const SizedBox(height: 6),
            Text(label, style: t.textTheme.labelMedium),
          ]),
        ),
      ),
    );
  }

  Widget _ticket(InvoiceRecord inv) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final f = _fiscal;
    final pillLabel = inv.voided
        ? 'Anulado'
        : f == null
            ? (inv.isCreditNote ? 'Nota de crédito (resta)' : statusLabel(inv.status))
            : '${fiscalStatusLabel(f.status)}${f.env == 'beta' ? ' · prueba' : ''}';
    final tone = inv.voided ? PillTone.bad : f == null ? (inv.status == 'paid' ? PillTone.ok : PillTone.neutral) : StatusPill.toneForFiscal(f.status);
    const kindName = {'factura': 'Factura', 'boleta': 'Boleta', 'nota_credito': 'Nota de crédito', 'nota_venta': 'Nota de venta'};
    return TicketPaper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            f == null
                ? (inv.imported ? '${kindName[inv.docKind] ?? 'Comprobante'} (importado)' : 'Nota de venta')
                : (f.docType == '01' ? 'Factura electrónica' : 'Boleta de venta electrónica'),
            style: t.textTheme.bodySmall),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(f?.number ?? inv.number, style: t.textTheme.headlineMedium)),
        // Serie-correlativo SUNAT (F001-00000023) vs. número interno (F-2026-0023): se dice claro cuál es cuál.
        Text(
          f == null
              ? (inv.imported
                  ? 'Número del sistema anterior.'
                  : 'Número interno: aún no es un comprobante SUNAT. Al emitir recibe su serie (F001/B001) y correlativo.')
              : 'N.° SUNAT ${f.number} · N.° interno ${inv.number}',
          style: t.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 10),
        StatusPill(pillLabel, tone: tone),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: inv.dueDate == null
              ? const StatusPill('Al contado', tone: PillTone.neutral)
              : StatusPill('Al crédito · vence ${displayDate(inv.dueDate!)}', tone: inv.isOverdue(todayIso()) ? PillTone.bad : PillTone.info),
        ),
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
        Row(children: [
          Hero(
            tag: 'avatar-${inv.id}',
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Text(
                  inv.clientName.trim().isEmpty || inv.clientName == '—' ? '·' : inv.clientName.trim().characters.first.toUpperCase(),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: t.colorScheme.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv.clientName, style: t.textTheme.titleMedium),
              if (inv.clientTaxId.isNotEmpty) Text(inv.clientTaxId, style: t.textTheme.bodySmall),
              Text(displayDate(inv.issueDate), style: t.textTheme.bodySmall),
            ]),
          ),
        ]),
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
