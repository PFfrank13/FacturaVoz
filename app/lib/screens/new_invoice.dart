import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show ImageFilter;

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
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'products.dart';

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
  Uint8List? _lastAudio; // solo en memoria, para reintentar sin volver a grabar
  String? _heardOnFail;
  int _seconds = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _levels = List<double>.filled(28, 0.08, growable: true);

  final _client = TextEditingController();
  final _clientFocus = FocusNode();
  final _clientTax = TextEditingController();
  final _clientEmail = TextEditingController();
  final _taxRate = TextEditingController();
  final _notes = TextEditingController();
  final List<_Row> _rows = [];
  List<({String name, String taxId})> _known = const [];
  String? _transcript;
  bool _saving = false;
  bool _submitted = false;
  bool _dirty = false;
  bool _showNotes = false;

  Profile get _profile => AppState.instance.profile!;

  @override
  void initState() {
    super.initState();
    Repo.recentClients().then((v) {
      if (mounted) setState(() => _known = v);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _clientFocus.dispose();
    for (final c in [_client, _clientTax, _clientEmail, _taxRate, _notes]) {
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
      for (var i = 0; i < _levels.length; i++) {
        _levels[i] = 0.08;
      }
      _ampSub?.cancel();
      try {
        _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
          // dBFS (-60..0) -> 0..1
          final v = ((a.current + 55) / 55).clamp(0.05, 1.0).toDouble();
          if (!mounted) return;
          setState(() {
            _levels.removeAt(0);
            _levels.add(v);
          });
        });
      } catch (_) {}
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop();
      });
      HapticFeedback.mediumImpact();
      setState(() => _phase = _Phase.recording);
    } catch (_) {
      setState(() => _error = 'No se pudo iniciar la grabación.');
    }
  }

  Future<void> _addFromCatalog() async {
    final p = await pickProduct(context, _profile.currency);
    if (p == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      // Reemplaza la línea vacía si es la única; si no, agrega una nueva.
      final empty = _rows.length == 1 && _rows.first.desc.text.trim().isEmpty && _rows.first.price.text.trim().isEmpty;
      if (empty) _rows.removeAt(0).dispose();
      _rows.add(_Row(LineItem(description: p.name, quantity: 1, unitPrice: p.unitPrice)));
      _dirty = true;
    });
  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _timer?.cancel();
    _ampSub?.cancel();
    _lastAudio = null;
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
      _lastAudio = await XFile(path).readAsBytes();
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = friendly(e);
        });
      }
    } finally {
      // El audio no se conserva en el dispositivo (solo en memoria mientras reintentas).
      if (!kIsWeb) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
    if (_lastAudio != null) await _process();
  }

  Future<void> _process() async {
    final bytes = _lastAudio;
    if (bytes == null) return;
    setState(() {
      _phase = _Phase.processing;
      _error = '';
      _heardOnFail = null;
    });
    try {
      final draft = await ApiService.parseAudio(
        bytes: bytes,
        filename: kIsWeb ? 'dictado.webm' : 'dictado.m4a',
        mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        profile: _profile,
      );
      _lastAudio = null;
      if (!mounted) return;
      _loadDraft(draft);
      HapticFeedback.lightImpact();
      setState(() => _phase = _Phase.review);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = friendly(e);
          _heardOnFail = e is AppException ? e.transcript : null;
        });
      }
    }
  }

  /// Si la IA falló pero se oyó el dictado: abre el formulario con el texto en notas para no perderlo.
  void _useHeard() {
    final text = _heardOnFail ?? '';
    _lastAudio = null;
    _manual();
    if (text.isNotEmpty) {
      _notes.text = text.length > 500 ? text.substring(0, 500) : text;
      _showNotes = true;
      _transcript = text;
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
    _showNotes = d.notes.isNotEmpty;
    _transcript = d.transcript;
    _submitted = false;
    _dirty = false;
    _error = '';
  }

  void _touch() => setState(() => _dirty = true);

  // ---------------- Revisión ----------------
  List<LineItem> _currentItems() => _rows
      .map((r) => LineItem(
            description: r.desc.text,
            quantity: parseDecimal(r.qty.text) ?? 0,
            unitPrice: parseDecimal(r.price.text) ?? 0,
          ))
      .toList();

  /// Tipo de documento según la longitud: 11 = RUC, 8 = DNI.
  ({String label, bool ok})? _docKind() {
    final d = _clientTax.text.trim();
    if (d.isEmpty) return null;
    final digits = RegExp(r'^\d+$').hasMatch(d);
    if (digits && d.length == 11) {
      final ok = const ['10', '15', '17', '20'].contains(d.substring(0, 2));
      return (label: 'RUC', ok: ok);
    }
    if (digits && d.length == 8) return (label: 'DNI', ok: true);
    return (label: 'Doc.', ok: !digits || d.length >= 3);
  }

  RiskReport _risk() => assessRisk(
        clientName: _client.text,
        clientTaxId: _clientTax.text,
        items: _currentItems().where((i) => i.description.trim().isNotEmpty || i.unitPrice > 0).toList(),
        taxRate: parseDecimal(_taxRate.text) ?? 0,
      );

  String? _clientError() => _client.text.trim().isEmpty ? 'Escribe el nombre del cliente' : null;
  String? _taxError() {
    final k = _docKind();
    if (k == null) return null;
    final d = _clientTax.text.trim();
    if (RegExp(r'^\d+$').hasMatch(d) && d.length != 8 && d.length != 11) return 'El DNI tiene 8 dígitos y el RUC 11';
    if (!k.ok) return 'El RUC debe empezar con 10, 15, 17 o 20';
    return null;
  }

  String? _rateError() {
    final rate = parseDecimal(_taxRate.text);
    return (rate == null || rate < 0 || rate > 100) ? 'Entre 0 y 100' : null;
  }

  String? _descError(_Row r) => r.desc.text.trim().isEmpty ? 'Describe el servicio o producto' : null;
  String? _qtyError(_Row r) {
    final q = parseDecimal(r.qty.text);
    return (q == null || round2(q) <= 0 || q > 100000) ? 'Mayor que 0' : null;
  }

  String? _priceError(_Row r) {
    final p = parseDecimal(r.price.text);
    return (p == null || p < 0 || p > 10000000) ? 'Precio no válido' : null;
  }

  String? _validate() {
    if (_clientError() != null) return 'Falta el nombre del cliente.';
    if (_taxError() != null) return _taxError();
    if (_rateError() != null) return 'La tasa de impuesto debe estar entre 0 y 100.';
    if (_rows.isEmpty) return 'Agrega al menos una línea.';
    for (final r in _rows) {
      if (_descError(r) != null) return 'Cada línea necesita una descripción.';
      if (_qtyError(r) != null) return 'La cantidad debe ser mayor que 0.';
      if (_priceError(r) != null) return 'Revisa el precio de cada línea.';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    final err = _validate();
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() => _error = err);
      return;
    }
    final risk = _risk();
    if (risk.level == RiskLevel.high) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Brand.bad, size: 32),
          title: const Text('Revisa antes de guardar'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in risk.reasons) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $r')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corregir')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar igual')),
          ],
        ),
      );
      if (go != true) return;
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
      _dirty = false;
      final mail = _clientEmail.text.trim();
      if (mail.isNotEmpty) await Repo.setClientEmail(id, mail); // best-effort: no bloquea el guardado
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar. ${friendly(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Descartar esta factura?'),
        content: const Text('Perderás los datos que no guardaste.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir editando')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descartar')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final review = _phase == _Phase.review;
    return PopScope(
      canPop: !(review && _dirty) && _phase != _Phase.processing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _phase == _Phase.processing) return;
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          title: Text(review ? 'Revisa tu factura' : 'Nueva factura'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: child),
          ),
          child: review
              ? KeyedSubtree(key: const ValueKey('review'), child: _review())
              : KeyedSubtree(key: const ValueKey('rec'), child: SafeArea(child: _recorderView())),
        ),
      ),
    );
  }

  // ---------------- Vista de dictado ----------------
  Widget _recorderView() {
    final recording = _phase == _Phase.recording;
    final processing = _phase == _Phase.processing;
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final remaining = _maxSeconds - _seconds;
    return Center(
      child: SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(child: DictateButton(size: 112, recording: recording, busy: processing, onPressed: recording ? _stop : _start)),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: recording
                  ? _Wave(levels: _levels, color: Brand.goldDeep)
                  : null,
            ),
            const SizedBox(height: 8),
            if (recording)
              Money('0:${_seconds.toString().padLeft(2, '0')}', size: 36, weight: FontWeight.w700)
            else
              Text(processing ? 'Entendiendo tu dictado…' : 'Dicta tu factura', style: t.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              processing
                  ? 'Un momento, estoy separando cliente, servicio e importe.'
                  : recording
                      ? 'Toca el botón para terminar. Quedan ${remaining}s.'
                      : 'Toca el micrófono y habla con naturalidad.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!recording && !processing) ...[
              const SizedBox(height: 22),
              SoftCard(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 18, color: Brand.goldDeep),
                    const SizedBox(width: 8),
                    Text('Ejemplo', style: t.textTheme.labelLarge),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '“Factura para Ferretería Díaz: instalación eléctrica a 450 soles y dos tomacorrientes a 25 cada uno”.',
                    style: t.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                  ),
                ]),
              ),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: _error.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _Banner(text: _error, tone: PillTone.bad),
                        if (_lastAudio != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(children: [
                              Expanded(child: FilledButton.icon(onPressed: _process, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar'))),
                              if (_heardOnFail != null) ...[
                                const SizedBox(width: 10),
                                Expanded(child: OutlinedButton(onPressed: _useHeard, child: const Text('Usar lo que se oyó'))),
                              ],
                            ]),
                          ),
                      ]),
                    ),
            ),
            const SizedBox(height: 22),
            if (!recording && !processing)
              OutlinedButton.icon(
                onPressed: _manual,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Prefiero escribirla'),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- Formulario de revisión / manual ----------------
  Widget _review() {
    final t = Theme.of(context);
    final rate = parseDecimal(_taxRate.text) ?? 0;
    final totals = computeTotals(_currentItems(), rate);
    final cur = _profile.currency;
    final bottom = MediaQuery.of(context).padding.bottom;
    final heard = _transcript != null && _transcript!.trim().isNotEmpty;
    final noLines = heard && _rows.length == 1 && _rows.first.desc.text.trim().isEmpty && _rows.first.price.text.trim().isEmpty;
    return Stack(children: [
      ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 150 + bottom),
        children: [
          if (heard)
            Reveal(
              child: _HeardCard(text: _transcript!, noLines: noLines),
            ),
          if (heard) const SizedBox(height: 14),
          Reveal(index: 1, child: _section('Cliente', Icons.person_outline_rounded, _clientSection())),
          const SizedBox(height: 14),
          Reveal(index: 2, child: _linesSection(cur)),
          const SizedBox(height: 14),
          Reveal(index: 3, child: _taxSection(totals, cur)),
          const SizedBox(height: 14),
          Reveal(index: 4, child: _notesSection()),
          const SizedBox(height: 14),
          _RiskCard(report: _risk()),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _error.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(padding: const EdgeInsets.only(top: 14), child: _Banner(text: _error, tone: PillTone.bad)),
          ),
        ],
      ),
      // Barra inferior con efecto cristal: total vivo + guardar
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottom),
              decoration: BoxDecoration(
                color: t.scaffoldBackgroundColor.withValues(alpha: 0.82),
                border: Border(top: BorderSide(color: t.colorScheme.outline)),
              ),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Total', style: t.textTheme.bodySmall),
                  CountUp(
                    value: totals.total,
                    builder: (c, v) => Money(money(v, cur), size: 24, weight: FontWeight.w700),
                  ),
                ]),
                const SizedBox(width: 18),
                Expanded(
                  child: GradientButton(
                    label: _saving ? 'Guardando…' : 'Guardar factura',
                    icon: Icons.check_rounded,
                    busy: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _section(String title, IconData icon, Widget child, {Widget? trailing}) {
    final t = Theme.of(context);
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: t.textTheme.titleSmall)),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _clientSection() {
    final kind = _docKind();
    return Column(children: [
      RawAutocomplete<({String name, String taxId})>(
        textEditingController: _client,
        focusNode: _clientFocus,
        displayStringForOption: (o) => o.name,
        optionsBuilder: (v) {
          final q = v.text.trim().toLowerCase();
          if (q.isEmpty) return _known.take(5);
          return _known.where((c) => c.name.toLowerCase().contains(q) && c.name.toLowerCase() != q).take(5);
        },
        onSelected: (o) {
          if (o.taxId.isNotEmpty) _clientTax.text = o.taxId;
          _touch();
        },
        fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
          controller: controller,
          focusNode: focus,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Nombre o razón social',
            counterText: '',
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: _submitted ? _clientError() : null,
          ),
          onChanged: (_) => _touch(),
        ),
        optionsViewBuilder: (context, onSelected, options) {
          final t = Theme.of(context);
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              shadowColor: Brand.indigo.withValues(alpha: 0.25),
              color: t.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 64, maxHeight: 260),
                child: ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: t.colorScheme.primaryContainer,
                          child: Text(o.name.characters.first.toUpperCase(), style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: o.taxId.isEmpty ? null : Text(o.taxId),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _clientTax,
        maxLength: 30,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-]'))],
        decoration: InputDecoration(
          labelText: 'DNI o RUC (opcional)',
          counterText: '',
          prefixIcon: const Icon(Icons.numbers_rounded),
          suffixIcon: kind == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Align(
                    widthFactor: 1,
                    child: StatusPill(kind.label, tone: _taxError() == null ? PillTone.ok : PillTone.warn),
                  ),
                ),
          errorText: _taxError(),
        ),
        onChanged: (_) => _touch(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _clientEmail,
        maxLength: 120,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'Correo del cliente (opcional)',
          counterText: '',
          prefixIcon: const Icon(Icons.alternate_email_rounded),
          errorText: _clientEmail.text.trim().isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(_clientEmail.text.trim())
              ? null
              : 'Ese correo no parece válido',
        ),
        onChanged: (_) => _touch(),
      ),
    ]);
  }

  Widget _linesSection(String cur) {
    final t = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, size: 20, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Detalle', style: t.textTheme.titleSmall)),
            Text('${_rows.length} ${_rows.length == 1 ? 'línea' : 'líneas'}', style: t.textTheme.bodySmall),
          ]),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(children: [
            for (var k = 0; k < _rows.length; k++) _lineCard(k, cur),
          ]),
        ),
        Center(
          child: TextButton.icon(
            onPressed: _rows.length >= 50
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _rows.add(_Row(LineItem()));
                      _dirty = true;
                    });
                  },
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Agregar línea'),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: _rows.length >= 50 ? null : _addFromCatalog,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Agregar del catálogo'),
          ),
        ),
      ]),
    );
  }

  void _step(_Row r, double delta) {
    final q = (parseDecimal(r.qty.text) ?? 0) + delta;
    final v = q < 1 ? 1.0 : (q > 100000 ? 100000.0 : q);
    HapticFeedback.selectionClick();
    r.qty.text = qtyText(v);
    _touch();
  }

  Widget _lineCard(int k, String cur) {
    final t = Theme.of(context);
    final r = _rows[k];
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final amount = round2((parseDecimal(r.qty.text) ?? 0) * (parseDecimal(r.price.text) ?? 0));
    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        TextField(
          controller: r.desc,
          maxLength: 200,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Servicio o producto',
            counterText: '',
            errorText: _submitted ? _descError(r) : null,
          ),
          onChanged: (_) => _touch(),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cantidad con − / +
          SizedBox(
            width: 140,
            child: TextField(
              controller: r.qty,
              inputFormatters: numFmt,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cant.',
                errorText: _submitted ? _qtyError(r) : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                prefixIcon: IconButton(icon: const Icon(Icons.remove_rounded), onPressed: () => _step(r, -1)),
                suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _step(r, 1)),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                suffixIconConstraints: const BoxConstraints(minWidth: 40),
              ),
              onChanged: (_) => _touch(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: r.price,
              inputFormatters: numFmt,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Precio unitario',
                prefixText: '${currencySymbols[cur] ?? ''} ',
                errorText: _submitted ? _priceError(r) : null,
              ),
              onChanged: (_) => _touch(),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          if (_rows.length > 1)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Brand.bad, visualDensity: VisualDensity.compact),
              onPressed: () => _removeRow(k),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Quitar'),
            ),
          const Spacer(),
          Text('Importe  ', style: t.textTheme.bodySmall),
          Money(money(amount, cur), size: 15.5, weight: FontWeight.w700),
        ]),
      ]),
    );
    return KeyedSubtree(key: ObjectKey(r), child: card);
  }

  void _removeRow(int k) {
    final r = _rows[k];
    HapticFeedback.mediumImpact();
    setState(() {
      _rows.removeAt(k);
      _dirty = true;
    });
    final restored = LineItem(
      description: r.desc.text,
      quantity: parseDecimal(r.qty.text) ?? 1,
      unitPrice: parseDecimal(r.price.text) ?? 0,
    );
    r.dispose();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('Línea eliminada'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => setState(() => _rows.insert(math.min(k, _rows.length), _Row(restored))),
        ),
      ));
  }

  Widget _taxSection(Totals t, String cur) {
    final th = Theme.of(context);
    final rate = parseDecimal(_taxRate.text);
    final base = _profile.taxRate ?? 0;
    final presets = <double>{if (base > 0) base, 0};
    final isPreset = rate != null && presets.any((p) => (p - rate).abs() < 0.001);
    final custom = !isPreset;
    return _section(
      _profile.taxLabel.isEmpty ? 'Impuesto' : _profile.taxLabel,
      Icons.percent_rounded,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in presets)
            ChoiceChip(
              label: Text(p == 0 ? 'Sin impuesto (0%)' : '${_profile.taxLabel} ${qtyText(p)}%'),
              selected: rate != null && (p - rate).abs() < 0.001,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                _taxRate.text = qtyText(p);
                _touch();
              },
            ),
          ChoiceChip(
            label: const Text('Otra tasa'),
            selected: custom,
            onSelected: (_) {
              if (!custom) _taxRate.text = '';
              _touch();
            },
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: custom
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _taxRate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(labelText: 'Tasa %', errorText: _rateError()),
                      onChanged: (_) => _touch(),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 14),
        DataRow2('Subtotal', money(t.subtotal, cur)),
        DataRow2(_profile.taxLabel.isEmpty ? 'Impuesto' : _profile.taxLabel, money(t.tax, cur)),
        Divider(color: th.colorScheme.outline),
        DataRow2('Total', money(t.total, cur), strong: true),
      ]),
    );
  }

  Widget _notesSection() {
    final t = Theme.of(context);
    if (!_showNotes) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showNotes = true),
          icon: const Icon(Icons.sticky_note_2_outlined),
          label: const Text('Agregar nota'),
        ),
      );
    }
    return SoftCard(
      child: TextField(
        controller: _notes,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: 'Nota (opcional)', prefixIcon: Icon(Icons.sticky_note_2_outlined, color: t.colorScheme.onSurfaceVariant)),
        onChanged: (_) => _touch(),
      ),
    );
  }
}

/// Lo que el servidor escuchó, para que el usuario confíe en el resultado.
class _HeardCard extends StatelessWidget {
  const _HeardCard({required this.text, required this.noLines});
  final String text;
  final bool noLines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [t.colorScheme.primaryContainer, t.colorScheme.primaryContainer.withValues(alpha: 0.5)]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.graphic_eq_rounded, size: 18, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Esto escuché', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
        ]),
        const SizedBox(height: 8),
        Text('“$text”', style: t.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        if (noLines) ...[
          const SizedBox(height: 10),
          Text('No pude separar los importes: complétalos abajo con lo que dijiste.', style: t.textTheme.bodySmall),
        ],
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.tone});
  final String text;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final c = tone == PillTone.bad ? Brand.bad : Brand.warn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontFamily: 'Inter', color: c, fontWeight: FontWeight.w500, height: 1.35))),
      ]),
    );
  }
}

/// Barras de onda alimentadas por el nivel real del micrófono.
class _Wave extends StatelessWidget {
  const _Wave({required this.levels, required this.color});
  final List<double> levels;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final l in levels)
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: 6 + 38 * l,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.35 + 0.65 * l), borderRadius: BorderRadius.circular(4)),
            ),
        ],
      );
}

/// Semáforo de riesgo: verde / amarillo / rojo con los motivos.
class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.report});
  final RiskReport report;

  @override
  Widget build(BuildContext context) {
    final (c, icon, title) = switch (report.level) {
      RiskLevel.low => (Brand.ok, Icons.verified_rounded, 'Todo se ve bien'),
      RiskLevel.medium => (Brand.warn, Icons.error_outline_rounded, 'Revisa estos detalles'),
      RiskLevel.high => (Brand.bad, Icons.warning_amber_rounded, 'Atención antes de guardar'),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey('${report.level.name}${report.reasons.length}'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontFamily: 'Inter', color: c, fontWeight: FontWeight.w700)),
              for (final r in report.reasons)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(r, style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        ]),
      ),
    );
  }
}
