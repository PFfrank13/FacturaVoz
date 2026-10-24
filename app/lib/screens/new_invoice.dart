import 'dart:async';
import 'dart:io' show File;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/repo.dart';
import '../ui/widgets.dart';

enum _Phase { idle, recording, processing, review }

class _Row {
  _Row(LineItem i)
      : desc = TextEditingController(text: i.description),
        qty = TextEditingController(text: qtyText(i.quantity)),
        price = TextEditingController(text: i.unitPrice == 0 ? '' : qtyText(i.unitPrice));
  final TextEditingController desc;
  final TextEditingController qty;
  final TextEditingController price;
  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
  }
}

/// Dictado -> transcripción + extracción (servidor) -> revisión editable -> guardado atómico.
class NewInvoiceScreen extends StatefulWidget {
  const NewInvoiceScreen({super.key});

  @override
  State<NewInvoiceScreen> createState() => _NewInvoiceScreenState();
}

class _NewInvoiceScreenState extends State<NewInvoiceScreen> {
  static const _maxSeconds = 60;

  final _recorder = AudioRecorder();
  _Phase _phase = _Phase.idle;
  String _error = '';
  int _seconds = 0;
  Timer? _timer;

  final _client = TextEditingController();
  final _clientTax = TextEditingController();
  final _taxRate = TextEditingController();
  final _notes = TextEditingController();
  final List<_Row> _rows = [];
  String? _transcript;
  bool _saving = false;

  Profile get _profile => AppState.instance.profile!;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    for (final c in [_client, _clientTax, _taxRate, _notes]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ---------------- Grabación ----------------
  Future<void> _start() async {
    setState(() => _error = '');
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Permite el micrófono en los ajustes del dispositivo para dictar.');
        return;
      }
      var path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/dictado_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        RecordConfig(
          encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _seconds = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop();
      });
      setState(() => _phase = _Phase.recording);
    } catch (_) {
      setState(() => _error = 'No se pudo iniciar la grabación.');
    }
  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _timer?.cancel();
    setState(() => _phase = _Phase.processing);
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = 'No se pudo grabar el audio.';
        });
      }
      return;
    }
    try {
      if (_seconds < 1) throw AppException('Dictado demasiado corto. Mantén la grabación unos segundos.');
      final bytes = await XFile(path).readAsBytes();
      final draft = await ApiService.parseAudio(
        bytes: bytes,
        filename: kIsWeb ? 'dictado.webm' : 'dictado.m4a',
        mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        profile: _profile,
      );
      if (!mounted) return;
      _loadDraft(draft);
      setState(() => _phase = _Phase.review);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = friendly(e);
        });
      }
    } finally {
      // El audio no se conserva en el dispositivo.
      if (!kIsWeb) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  void _manual() {
    _loadDraft(InvoiceDraft(taxRate: _profile.taxRate ?? 0, currency: _profile.currency, items: [LineItem()]));
    setState(() => _phase = _Phase.review);
  }

  void _loadDraft(InvoiceDraft d) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll((d.items.isEmpty ? [LineItem()] : d.items).map(_Row.new));
    _client.text = d.clientName;
    _clientTax.text = d.clientTaxId;
    _taxRate.text = qtyText(d.taxRate);
    _notes.text = d.notes;
    _transcript = d.transcript;
  }

  // ---------------- Revisión ----------------
  List<LineItem> _currentItems() => _rows
      .map((r) => LineItem(
            description: r.desc.text,
            quantity: parseDecimal(r.qty.text) ?? 0,
            unitPrice: parseDecimal(r.price.text) ?? 0,
          ))
      .toList();

  String? _validate() {
    if (_client.text.trim().isEmpty) return 'Falta el nombre del cliente.';
    final rate = parseDecimal(_taxRate.text);
    if (rate == null || rate < 0 || rate > 100) return 'La tasa de impuesto debe estar entre 0 y 100.';
    if (_rows.isEmpty) return 'Agrega al menos una línea.';
    for (final r in _rows) {
      final q = parseDecimal(r.qty.text);
      final p = parseDecimal(r.price.text);
      if (r.desc.text.trim().isEmpty) return 'Cada línea necesita una descripción.';
      if (q == null || round2(q) <= 0 || q > 100000) return 'La cantidad debe ser mayor que 0.';
      if (p == null || p < 0 || p > 10000000) return 'El precio no es válido.';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final id = await Repo.createInvoice(InvoiceDraft(
        clientName: _client.text,
        clientTaxId: _clientTax.text,
        taxRate: parseDecimal(_taxRate.text)!,
        currency: _profile.currency,
        notes: _notes.text,
        transcript: _transcript,
        items: _currentItems(),
      ));
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar la factura. Revisa los datos e inténtalo de nuevo.');
      debugPrint('createInvoice failed: ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva factura')),
      body: SafeArea(child: _phase == _Phase.review ? _review() : _recorderView()),
    );
  }

  Widget _recorderView() {
    final recording = _phase == _Phase.recording;
    final processing = _phase == _Phase.processing;
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final remaining = _maxSeconds - _seconds;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DictateButton(size: 104, recording: recording, busy: processing, onPressed: recording ? _stop : _start),
            const SizedBox(height: 12),
            if (recording)
              Money('0:${_seconds.toString().padLeft(2, '0')}', size: 34, weight: FontWeight.w700)
            else
              Text(processing ? 'Entendiendo tu dictado…' : 'Dicta tu factura', style: t.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              processing
                  ? 'Un momento, estoy separando cliente, servicio e importe.'
                  : recording
                      ? 'Toca el botón rojo para terminar. Quedan ${remaining}s.'
                      : 'Di el cliente, el servicio y el importe.\nEj.: “Factura a Ferretería Díaz por instalación eléctrica, 450”.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(_error, textAlign: TextAlign.center, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(height: 28),
            if (!recording && !processing) TextButton(onPressed: _manual, child: const Text('Prefiero escribirla')),
          ],
        ),
      ),
    );
  }

  Widget _review() {
    final rate = parseDecimal(_taxRate.text) ?? 0;
    final t = computeTotals(_currentItems(), rate);
    final cur = _profile.currency;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Revisa lo que entendí antes de guardar:'),
        if (_transcript != null && _transcript!.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Lo que escuché'),
            children: [Align(alignment: Alignment.centerLeft, child: Text(_transcript!))],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _client,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Cliente *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _clientTax,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Documento del cliente (opcional)'),
        ),
        const SizedBox(height: 12),
        for (var k = 0; k < _rows.length; k++) _rowCard(k),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _rows.length >= 50 ? null : () => setState(() => _rows.add(_Row(LineItem()))),
            icon: const Icon(Icons.add),
            label: const Text('Agregar línea'),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('${_profile.taxLabel} %'),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _taxRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notas (opcional)'),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              DataRow2('Subtotal', money(t.subtotal, cur)),
              DataRow2(_profile.taxLabel, money(t.tax, cur)),
              const Divider(height: 20),
              DataRow2('Total', money(t.total, cur), strong: true),
            ]),
          ),
        ),
        if (_error.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error, style: TextStyle(color: scheme.error))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar factura')),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                      _phase = _Phase.idle;
                      _error = '';
                    }),
            child: const Text('Repetir'),
          ),
        ]),
      ],
    );
  }

  Widget _rowCard(int k) {
    final r = _rows[k];
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: r.desc,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Descripción', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              tooltip: 'Quitar línea',
              icon: const Icon(Icons.delete_outline),
              onPressed: _rows.length <= 1
                  ? null
                  : () => setState(() {
                        _rows.removeAt(k).dispose();
                      }),
            ),
          ]),
          Row(children: [
            Expanded(
              child: TextField(
                controller: r.qty,
                inputFormatters: numFmt,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cantidad'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: r.price,
                inputFormatters: numFmt,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Precio (sin impuesto)', prefixText: '${currencySymbols[_profile.currency] ?? ''} '),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
