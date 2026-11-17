import 'package:flutter/material.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/repo.dart';
import '../ui/retail_visual.dart';
import '../ui/theme.dart';
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
  List<InvoiceRecord> _invoices = const [];
  String _filter = 'all';
  String _query = '';
  String? _error;
  bool _loading = true;
  int _limit = 100;
  bool _showHistoryOnly = false;
  final ScrollController _listController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String? _activeOrg;
  int _fetchGeneration = 0;

  /// Clear prior-tenant records immediately, even before a new network read.
  void _onCompanyChange() {
    final org = Repo.activeOrgId;
    if (org == _activeOrg || !mounted) return;
    _activeOrg = org;
    _fetchGeneration++;
    _searchController.clear();
    setState(() {
      _invoices = const [];
      _query = '';
      _filter = 'all';
      _error = null;
      _limit = 100;
      _showHistoryOnly = false;
      _loading = true;
    });
    _refresh();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onCompanyChange);
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  void _openHistory() {
    setState(() => _showHistoryOnly = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _listController.hasClients) _listController.jumpTo(0);
    });
  }

  Future<void> _shareExisting() async {
    if (_loading || _error != null) return;
    final org = Repo.activeOrgId;
    if (_invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todavía no hay comprobantes que compartir. Registra una venta primero.'),
      ));
      return;
    }
    final selected = await showModalBottomSheet<InvoiceRecord>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .72),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Align(alignment: Alignment.centerLeft, child: Text(
                'Elige qué comprobante compartir',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              )),
            ),
            Flexible(child: ListView.builder(
              shrinkWrap: true,
              itemCount: _invoices.length,
              itemBuilder: (_, index) {
                final inv = _invoices[index];
                return ListTile(
                  leading: Icon(Icons.receipt_long_rounded, color: Theme.of(sheetContext).colorScheme.primary),
                  title: Text(inv.fiscalNumber ?? inv.number),
                  subtitle: Text(
                    '${inv.clientName} · ${inv.fiscalStatus == 'accepted' ? 'Verifica su entorno SUNAT' : 'Documento interno o pendiente'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(money(inv.totals.total, inv.currency)),
                  onTap: () => Navigator.pop(sheetContext, inv),
                );
              },
            )),
          ]),
        ),
      ),
    );
    if (selected == null || !mounted || Repo.activeOrgId != org) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => InvoiceDetailScreen(invoiceId: selected.id, autoSharePdf: true),
    ));
    if (mounted) await _refresh();
  }

  @override
  void initState() {
    super.initState();
    _activeOrg = Repo.activeOrgId;
    AppState.instance.addListener(_onCompanyChange);
    _refresh();
  }

  Future<void> _refresh() async {
    final org = Repo.activeOrgId;
    final generation = ++_fetchGeneration;
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await Repo.listInvoices(limit: _limit);
      if (!mounted || generation != _fetchGeneration || Repo.activeOrgId != org) return;
      setState(() { _invoices = entries; _loading = false; });
    } catch (e) {
      if (mounted && generation == _fetchGeneration && Repo.activeOrgId == org) {
        setState(() { _error = friendly(e); _loading = false; });
      }
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
    Key? key,
  }) => RetailReceiptActionTile(
    key: key, icon: icon, label: label, caption: caption, onTap: action,
  );

  @override
  Widget build(BuildContext context) {
    final access = Access.instance;
    final entries = _invoices.where((i) => retailReceiptMatches(i, _filter, _query)).toList();
    final c = DsColors.of(context);
    final t = Theme.of(context);
    return Scaffold(
        appBar: AppBar(
          title: const Text('Comprobantes'),
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
              controller: _listController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (_showHistoryOnly) ...[
                  TextButton.icon(
                    key: const ValueKey('receipt-back-menu'),
                    onPressed: () => setState(() => _showHistoryOnly = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Volver al menú de comprobantes'),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  RetailVisual.hero(
                    context: context,
                    eyebrow: 'Facturación · Documentos',
                    title: 'Tus comprobantes',
                    subtitle: 'Emite boletas y facturas, revisa su estado SUNAT y comparte documentos reales.',
                    icon: Icons.receipt_long_rounded,
                  ),
                  const SizedBox(height: 14),
                  if (access.can('sell') && access.has('facturar')) _action(
                    key: const ValueKey('receipt-emit-action'),
                    icon: Icons.note_add_rounded,
                    label: '1. Emitir comprobante',
                    caption: 'Elige boleta o factura, revisa cliente y productos, confirma en SUNAT',
                    action: _newReceipt,
                  ),
                  const SizedBox(height: 9),
                  _action(
                    key: const ValueKey('receipt-history-action'),
                    icon: Icons.history_rounded,
                    label: '2. Historial de comprobantes',
                    caption: 'Busca, filtra, descarga y revisa estados reales',
                    action: _openHistory,
                  ),
                  const SizedBox(height: 9),
                  if (access.can('settings')) _action(
                    key: const ValueKey('receipt-sunat-action'),
                    icon: Icons.admin_panel_settings_rounded,
                    label: '3. Configuración SUNAT',
                    caption: 'RUC, entorno, usuario SOL y certificado digital',
                    action: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const FiscalSetupScreen(),
                      ));
                      if (mounted) await _refresh();
                    },
                  ),
                  const SizedBox(height: 9),
                  _action(
                    key: const ValueKey('receipt-share-action'),
                    icon: Icons.share_rounded,
                    label: '4. Compartir comprobante',
                    caption: 'Elige un documento real y abre WhatsApp, correo u otra app',
                    action: _loading || _error != null ? null : _shareExisting,
                  ),
                  if (access.can('settings')) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      key: const ValueKey('receipt-branding-extras'),
                      title: const Text('Opciones de diseño e impresión',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      leading: Icon(Icons.tune_rounded, color: t.colorScheme.primary),
                      children: [
                        ListTile(
                          leading: const Icon(Icons.palette_rounded),
                          title: const Text('Logo, PDF y ticket'),
                          subtitle: const Text('Personaliza la plantilla del negocio'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const BrandingScreen(),
                          )),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 15),
                ],
                Text('Historial de comprobantes', style: t.textTheme.titleMedium?.copyWith(
                  color: c.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('receipt-search'),
                  controller: _searchController,
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
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_loading) const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                ) else if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: c.bad)),
                  const SizedBox(height: 7),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ] else if (entries.isEmpty) ...[
                  const SizedBox(height: 20),
                  Icon(Icons.receipt_long_outlined, color: c.muted, size: 48),
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
    final c = DsColors.of(context);
    final color = inv.voided ? c.bad
      : fiscal == 'accepted' ? c.ok
      : fiscal == 'rejected' || fiscal == 'error' ? c.warn
      : c.muted;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(15),
      child: ListTile(
        key: ValueKey('receipt-${inv.id}'),
        onTap: () => _openDetail(inv),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(15),
        ),
        leading: Icon(kind == 'factura' ? Icons.description_rounded
          : Icons.receipt_long_rounded, color: c.primaryText, size: 28),
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
          Icon(Icons.chevron_right_rounded, color: c.muted, size: 18),
        ]),
      ),
    );
  }
}


/// Acción fiscal independiente y verificable en pantallas pequeñas.
class RetailReceiptActionTile extends StatelessWidget {
  const RetailReceiptActionTile({
    super.key, required this.icon, required this.label,
    required this.caption, required this.onTap,
  });
  final IconData icon;
  final String label, caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = DsColors.of(context);
    final t = Theme.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.line),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: c.elevated,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, color: c.primaryText, size: 23),
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleSmall?.copyWith(
                    color: c.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(caption,
                  style: t.textTheme.bodySmall?.copyWith(color: c.muted)),
              ],
            )),
            const SizedBox(width: Gap.xs),
            Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
          ]),
        ),
      ),
    );
  }
}
