import 'package:flutter/material.dart';

import '../errors.dart';
import '../models.dart';
import '../services/api.dart';

/// Emisión de factura (01) o boleta (03) electrónica. El servidor reserva el número, envía a SUNAT
/// y guarda el resultado; reintentar nunca consume otro correlativo.
class EmitSunatScreen extends StatefulWidget {
  const EmitSunatScreen({super.key, required this.invoice, required this.company});
  final InvoiceRecord invoice;
  final FiscalCompany company;

  @override
  State<EmitSunatScreen> createState() => _EmitSunatScreenState();
}

class _EmitSunatScreenState extends State<EmitSunatScreen> {
  late String _docType;
  late String _clientDocType;
  String _afectacion = 'gravado';
  String _unit = 'NIU';
  late final TextEditingController _doc;
  late final TextEditingController _address;
  late final TextEditingController _name;
  bool _busy = false;
  String _error = '';
  FiscalResult? _result;

  @override
  void initState() {
    super.initState();
    final inv = widget.invoice;
    final tax = inv.clientTaxId.trim();
    _clientDocType = const ['6', '1', '4', '7', '0'].contains(inv.clientDocType)
        ? inv.clientDocType
        : (RegExp(r'^\d{11}$').hasMatch(tax) ? '6' : (RegExp(r'^\d{8}$').hasMatch(tax) ? '1' : '6'));
    _docType = _clientDocType == '6' ? '01' : '03';
    _doc = TextEditingController(text: _clientDocType == '0' ? '' : tax);
    _address = TextEditingController();
    _name = TextEditingController(text: inv.clientName == '—' ? '' : inv.clientName);
    if (inv.taxRate == 0) _afectacion = 'exonerado';
  }

  @override
  void dispose() {
    _doc.dispose();
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  double get _rate => _afectacion == 'gravado' ? widget.invoice.taxRate : 0;

  String? _precheck() {
    if (_name.text.trim().isEmpty) return 'Escribe el nombre o razón social del cliente.';
    if (_afectacion == 'gravado' && widget.invoice.taxRate != 18) {
      return 'Esta factura tiene impuesto ${qtyText(widget.invoice.taxRate)}%. Para operaciones gravadas debe ser 18%. '
          'Si la operación es exonerada o inafecta, cámbialo abajo.';
    }
    if (_clientDocType != '0' && _doc.text.trim().isEmpty) return 'Falta el número de documento del cliente.';
    return null;
  }

  Future<void> _emit() async {
    final pre = _precheck();
    if (pre != null) {
      setState(() => _error = pre);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Emitir ${_docType == '01' ? 'factura' : 'boleta'}'),
        content: Text(widget.company.env == 'beta'
            ? 'Se enviará a SUNAT BETA (pruebas). No tiene validez tributaria.'
            : 'Se enviará a SUNAT y NO podrá modificarse. Revisa cliente, importes y tipo de documento.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Emitir')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await FiscalApi.emit(
        invoiceId: widget.invoice.id,
        docType: _docType,
        afectacion: _afectacion,
        unit: _unit,
        clientDocType: _clientDocType,
        clientDocNumber: _doc.text.trim(),
        clientName: _name.text.trim(),
        clientAddress: _address.text.trim(),
      );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final t = computeTotals(inv.items, _rate);
    final scheme = Theme.of(context).colorScheme;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Emitir a SUNAT')),
      body: SafeArea(
        child: ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.company.env == 'beta')
              Card(
                color: scheme.tertiaryContainer,
                child: const Padding(padding: EdgeInsets.all(12), child: Text('Entorno de PRUEBAS (SUNAT beta): los comprobantes no tienen validez.')),
              ),
            if (r != null) _resultCard(r) else ..._form(t),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(FiscalResult r) {
    final ok = r.status == 'accepted';
    final rejected = r.status == 'rejected';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: ok ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ok ? Icons.verified : Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(ok ? 'Aceptada por SUNAT' : rejected ? 'Rechazada por SUNAT' : 'SUNAT no respondió', style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text('Comprobante ${r.number}'),
          if (r.message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.message)),
          if (!ok)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(rejected
                  ? 'Corrige los datos del cliente y vuelve a intentar: se conserva el mismo número.'
                  : 'Puedes reintentar: se reenvía el mismo comprobante, sin gastar otro número.'),
            ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Listo')),
            const SizedBox(width: 8),
            if (!ok) OutlinedButton(onPressed: () => setState(() => _result = null), child: const Text('Reintentar')),
          ]),
        ]),
      ),
    );
  }

  List<Widget> _form(Totals t) {
    final cur = widget.invoice.currency;
    return [
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: '01', label: Text('Factura')),
          ButtonSegment(value: '03', label: Text('Boleta')),
        ],
        selected: {_docType},
        onSelectionChanged: _busy
            ? null
            : (s) => setState(() {
                  _docType = s.first;
                  if (_docType == '01') {
                    _clientDocType = '6';
                  } else if (_clientDocType == '6') {
                    _clientDocType = '1';
                  }
                }),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Cliente (razón social o nombre) *'),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('$_docType-$_clientDocType'),
        initialValue: _clientDocType,
        decoration: const InputDecoration(labelText: 'Documento del cliente'),
        items: [
          const DropdownMenuItem(value: '6', child: Text('RUC')),
          if (_docType == '03') ...const [
            DropdownMenuItem(value: '1', child: Text('DNI')),
            DropdownMenuItem(value: '4', child: Text('Carnet de extranjería')),
            DropdownMenuItem(value: '7', child: Text('Pasaporte')),
            DropdownMenuItem(value: '0', child: Text('Sin documento (ventas menores a S/ 700)')),
          ],
        ],
        onChanged: _busy ? null : (v) => setState(() => _clientDocType = v ?? '6'),
      ),
      const SizedBox(height: 12),
      if (_clientDocType != '0')
        TextField(
          controller: _doc,
          maxLength: 12,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(labelText: 'Número de documento'),
        ),
      TextField(
        controller: _address,
        maxLength: 200,
        decoration: const InputDecoration(labelText: 'Dirección del cliente (opcional)'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _afectacion,
        decoration: const InputDecoration(labelText: 'Afectación al IGV'),
        items: const [
          DropdownMenuItem(value: 'gravado', child: Text('Gravado (IGV 18%)')),
          DropdownMenuItem(value: 'exonerado', child: Text('Exonerado (sin IGV)')),
          DropdownMenuItem(value: 'inafecto', child: Text('Inafecto (sin IGV)')),
        ],
        onChanged: _busy ? null : (v) => setState(() => _afectacion = v ?? 'gravado'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _unit,
        decoration: const InputDecoration(labelText: 'Tipo de ítems'),
        items: const [
          DropdownMenuItem(value: 'NIU', child: Text('Bienes (unidad)')),
          DropdownMenuItem(value: 'ZZ', child: Text('Servicios')),
        ],
        onChanged: _busy ? null : (v) => setState(() => _unit = v ?? 'NIU'),
      ),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerRight, child: Text('Subtotal: ${money(t.subtotal, cur)}')),
      Align(alignment: Alignment.centerRight, child: Text('IGV: ${money(t.tax, cur)}')),
      Align(alignment: Alignment.centerRight, child: Text('Total: ${money(t.total, cur)}', style: Theme.of(context).textTheme.titleLarge)),
      if (_error.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _emit,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        label: Text(_busy ? 'Enviando a SUNAT…' : 'Emitir a SUNAT'),
      ),
    ];
  }
}
