import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import 'fiscal_setup.dart';
import 'branding.dart';
import 'invoice_detail.dart';
import 'new_invoice.dart';

/// One place for the retail fiscal journey. Sale, internal receipt and SUNAT
/// issuance are distinct events: never call an unissued sale "SUNAT accepted".
String retailReceiptKind(InvoiceRecord invoice) {
  if (invoice.isCreditNote) return 'credit';
  final number = (invoice.fiscalNumber ?? '').toUpperCase();
  if (number.startsWith('B')) return 'boleta';
  if (number.startsWith('F')) return 'factura';
  if (invoice.docKind == 'boleta' || invoice.docKind == 'factura') {
    return invoice.docKind!;
  }
  return 'internal';
}

bool retailReceiptMatches(InvoiceRecord invoice, String filter, String query) {
  final match = switch (filter) {
    'boleta' => retailReceiptKind(invoice) == 'boleta',
    'factura' => retailReceiptKind(invoice) == 'factura',
    'review' => const {'rejected', 'error', 'pending'}.contains(invoice.fiscalStatus),
    'unissued' => invoice.fiscalStatus == null,
    _ => true,
  };
  if (!match) return false;
  final q = query.trim().toLowerCase();
  return q.isEmpty ||
      invoice.clientName.toLowerCase().contains(q) ||
      invoice.number.toLowerCase().contains(q) ||
      (invoice.fiscalNumber ?? '').toLowerCase().contains(q) ||
      invoice.clientTaxId.toLowerCase().contains(q);
}

class RetailReceiptsScreen extends StatefulWidget {
  const RetailReceiptsScreen({super.key});

  @override
  State<RetailReceiptsScreen> createState() => _RetailReceiptsScreenState();
}

class _RetailReceiptsScreenState extends State<RetailReceiptsScreen> {
  static const _bg = Color(0xFF0B1030);
  static const _surface = Color(0xFF1C224C);
  static const _violet = Color(0xFF9258FB);
  List<InvoiceRecord> _invoices = const [];
  String _filter = 'all';
  String _query = '';
  String? _error;
  bool _loading = true;
  int _limit = 100;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final org = Repo.activeOrgId;
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await Repo.listInvoices(limit: _limit);
      if (!mounted || Repo.activeOrgId != org) return;
      setState(() { _invoices = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendly(e); _loading = false; });
    }
  }

  Future<void> _newReceipt() async {
    if (!Access.instance.can('sell') || !Access.instance.has('facturar')) return;
    // The selection is intent only. Neither choice issues to SUNAT until the
    // user reviews the document and confirms inside EmitSunatScreen.
    final docType = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¿Qué deseas emitir?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          const Text('Primero revisa cliente y productos. La emisión SUNAT se confirma al final.'),
          const SizedBox(height: 12),
          ListTile(
            key: const ValueKey('receipt-create-boleta'),
            leading: const Icon(Icons.receipt_long_rounded, color: Color(0xFFC0A0FF)),
            title: const Text('Boleta electrónica'),
            subtitle: const Text('Para consumidor final o cliente identificado'),
            onTap: () => Navigator.pop(sheetContext, '03'),
          ),
          ListTile(
            key: const ValueKey('receipt-create-factura'),
            leading: const Icon(Icons.description_rounded, color: Color(0xFF89B8FF)),
            title: const Text('Factura electrónica'),
            subtitle: const Text('Requiere RUC y razón social del cliente'),
            onTap: () => Navigator.pop(sheetContext, '01'),
          ),
        ]),
      )),
    );
    if (!mounted || docType == null) return;
    final invoiceId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => NewInvoiceScreen(
        startManual: true,
        defaultClientName: docType == '03' ? 'Público general' : '',
        documentLabel: docType == '03' ? 'boleta' : 'factura',
      )),
    );
    if (!mounted) return;
    if (invoiceId != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InvoiceDetailScreen(
          invoiceId: invoiceId,
          autoEmitDocType: docType,
        ),
      ));
    }
    if (!mounted) return;
    AppState.instance.bump();
    await _refresh();
  }

  Future<void> _openDetail(InvoiceRecord inv) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => InvoiceDetailScreen(invoiceId: inv.id),
    ));
    if (mounted) await _refresh();
  }

  Widget _action({
    required IconData icon,
    required String label,
    required String caption,
    required VoidCallback? action,
    Color accent = _violet,
  }) => Material(
    color: _surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: action,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: .55)),
        ),
        child: Row(children: [
          Container(
            width: 43, height: 43,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent.withValues(alpha: .85), accent.withValues(alpha: .38)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 3),
            Text(caption, style: const TextStyle(fontSize: 12, color: Color(0xFFC5C6E1))),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFCEB9FA)),
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final access = Access.instance;
    final entries = _invoices.where((i) => retailReceiptMatches(i, _filter, _query)).toList();
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(seedColor: _violet, brightness: Brightness.dark),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Comprobantes'),
          backgroundColor: _bg,
          actions: [
            IconButton(
              tooltip: 'Actualizar comprobantes',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _refresh,
            ),
          ],
        ),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const Text('Boletas, facturas y ventas internas',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text(
                  'Crea, consulta y emite desde un solo módulo. El documento será válido '
                  'solo cuando SUNAT confirme su aceptación en producción.',
                  style: TextStyle(color: Color(0xFFBABDD9), fontSize: 12),
                ),
                const SizedBox(height: 17),
                _action(
                  icon: Icons.note_add_rounded,
                  label: 'Nuevo comprobante',
                  caption: 'Registrar productos y preparar boleta o factura',
                  action: access.can('sell') && access.has('facturar') ? _newReceipt : null,
                ),
                const SizedBox(height: 9),
                _action(
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'Configuración SUNAT',
                  caption: 'RUC, entorno, usuario SOL y certificado digital',
                  action: access.can('settings')
                    ? () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const FiscalSetupScreen(),
                        ));
                        if (mounted) _refresh();
                      }
                    : null,
                  accent: const Color(0xFF2F93CA),
                ),
                if (access.can('settings')) ...[
                  const SizedBox(height: 9),
                  _action(
                    icon: Icons.palette_rounded,
                    label: 'Plantillas, logo y formatos',
                    caption: 'Personaliza PDF A4 y ticket; se guarda por negocio',
                    action: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const BrandingScreen(),
                    )),
                    accent: const Color(0xFF8055D9),
                  ),
                ],
                const SizedBox(height: 20),
                const Text('Historial de comprobantes', style: TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('receipt-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Cliente, DNI/RUC o número',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (value, label) in const [
                      ('all', 'Todos'),
                      ('boleta', 'Boletas'),
                      ('factura', 'Facturas'),
                      ('unissued', 'Sin emitir'),
                      ('review', 'Por revisar'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          key: ValueKey('receipts-filter-$value'),
                          label: Text(label),
                          selected: _filter == value,
                          onSelected: (_) => setState(() => _filter = value),
                          selectedColor: const Color(0xFF6C3ACF),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_loading) const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                ) else if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Color(0xFFFFADB9))),
                  const SizedBox(height: 7),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ] else if (entries.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Icon(Icons.receipt_long_outlined, color: Color(0xFFB5A4DF), size: 48),
                  const SizedBox(height: 8),
                  const Text('No hay comprobantes para este filtro',
                    textAlign: TextAlign.center),
                ] else for (final inv in entries) ...[
                  _receiptTile(inv),
                  const SizedBox(height: 8),
                ],
                if (!_loading && _error == null && _invoices.length == _limit)
                  TextButton.icon(
                    onPressed: () { _limit += 100; _refresh(); },
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Cargar más comprobantes'),
                  ),
              ],
            ),
          ),
        ))),
      ),
    );
  }

  Widget _receiptTile(InvoiceRecord inv) {
    final kind = retailReceiptKind(inv);
    final fiscal = inv.fiscalStatus;
    final label = switch (kind) {
      'boleta' => 'Boleta electrónica',
      'factura' => 'Factura electrónica',
      'credit' => 'Nota de crédito',
      _ => 'Venta / documento interno',
    };
    final state = inv.voided ? 'Anulado' : switch (fiscal) {
      'accepted' => 'Aceptado · revisar entorno',
      'rejected' => 'Rechazado por SUNAT',
      'pending' => 'Pendiente de respuesta SUNAT',
      'error' => 'Sin confirmación de SUNAT',
      _ => inv.status == 'draft' ? 'Borrador · sin emitir' : 'No emitido ante SUNAT',
    };
    final color = inv.voided ? const Color(0xFFEF9299)
      : fiscal == 'accepted' ? const Color(0xFF47E3AB)
      : fiscal == 'rejected' || fiscal == 'error' ? const Color(0xFFFFB477)
      : const Color(0xFFBFC1E4);
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(15),
      child: ListTile(
        key: ValueKey('receipt-${inv.id}'),
        onTap: () => _openDetail(inv),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF484680)),
          borderRadius: BorderRadius.circular(15),
        ),
        leading: Icon(kind == 'factura' ? Icons.description_rounded
          : Icons.receipt_long_rounded, color: _violet, size: 32),
        title: Text(inv.fiscalNumber ?? inv.number,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · ${inv.clientName}', maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(state, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Text(money(inv.totals.total, inv.currency),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFB7A3EE), size: 18),
        ]),
      ),
    );
  }
}
