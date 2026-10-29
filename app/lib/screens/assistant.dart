import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../access.dart';
import '../app_state.dart';
import '../errors.dart';
import '../models_pro.dart';
import '../services/pro_api.dart';
import '../services/voice.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'collections.dart';
import 'expenses.dart';
import 'new_invoice.dart';
import '../models.dart';
import '../services/repo.dart';
import 'cash_day.dart';
import 'clients_hub.dart';
import 'fiados.dart';
import 'invoice_detail.dart';
import 'jobs.dart' show AgendaScreen;
import 'products.dart';
import 'profit.dart';
import 'taxes.dart';

/// Abre el Copiloto: pregunta por tu negocio o da una orden, por voz o por texto.
/// Con [ask] la pregunta se envía sola al abrir (p. ej. "plan de rescate de caja").
Future<void> openCopilot(BuildContext context, {String? ask}) {
  final nav = Navigator.of(context);
  Haptics.soft();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.9, child: _CopilotSheet(nav: nav, ask: ask)),
  );
}

enum _Phase { idle, listening, thinking }

class _Turn {
  _Turn(this.question, this.reply);
  final String question;
  final AssistantReply? reply;
}

class _CopilotSheet extends StatefulWidget {
  const _CopilotSheet({required this.nav, this.ask});
  final NavigatorState nav;
  final String? ask;

  @override
  State<_CopilotSheet> createState() => _CopilotSheetState();
}

class _CopilotSheetState extends State<_CopilotSheet> {
  static const _maxSeconds = 30;
  static bool _muted = false; // se recuerda mientras la app está abierta

  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  _Phase _phase = _Phase.idle;
  double _level = 0;
  int _seconds = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amp;
  String _error = '';

  static const _starters = [
    '¿Llegaré a mi meta este mes?',
    '¿Quién me debe más?',
    'Dame un plan de rescate para mi caja',
    '¿Qué clientes están dejando de comprarme?',
    '¿Cuánto gané este mes?',
    '¿Qué producto se me está acabando?',
    'Gasté 50 soles en movilidad',
    'Cotiza a Corpax 3 sillas a 150',
    'Dame el resumen del día',
    'Muéstrame las ventas de ayer',
    'Anota que Rosa me debe 30 de arroz',
    '¿Cuánto debo guardar para SUNAT?',
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    final q = widget.ask;
    if (q != null && q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ask(text: q);
      });
    }
  }

  Future<void> _initTts() async {
    try {
      for (final l in const ['es-PE', 'es-US', 'es-MX', 'es-ES']) {
        if (await _tts.isLanguageAvailable(l) == true) {
          await _tts.setLanguage(l);
          break;
        }
      }
      await _tts.setSpeechRate(kIsWeb ? 1.0 : 0.5);
      await _tts.setPitch(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _amp?.cancel();
    _recorder.dispose();
    _tts.stop();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// [premium]: voz natural del servidor (solo si la pidieron con "Escuchar" o preguntaron hablando).
  /// Si no hay voz premium (sin clave, sin cuota o sin internet) se usa la voz del teléfono.
  Future<void> _speak(String s, {bool premium = false}) async {
    if (_muted || s.trim().isEmpty) return;
    try {
      await _tts.stop();
      await PremiumVoice.instance.stop();
      if (premium && await PremiumVoice.instance.speak(s)) return;
      final n = PremiumVoice.instance.notice.value;
      if (premium && n.isNotEmpty && mounted && Access.instance.isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n)));
        PremiumVoice.instance.notice.value = '';
      }
      await _tts.speak(s);
    } catch (_) {}
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
    });
  }

  // ───────────── Voz ─────────────
  Future<void> _listen() async {
    if (_phase == _Phase.listening) return _stop();
    if (_phase == _Phase.thinking) return;
    setState(() => _error = '');
    try {
      await _tts.stop();
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Permite el micrófono en los ajustes del dispositivo.');
        return;
      }
      var path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/copiloto_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc, bitRate: 64000, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      _seconds = 0;
      _amp?.cancel();
      try {
        _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
          if (mounted) setState(() => _level = ((a.current + 50) / 50).clamp(0.0, 1.0).toDouble());
        });
      } catch (_) {}
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop();
      });
      Haptics.soft();
      setState(() => _phase = _Phase.listening);
    } catch (_) {
      setState(() => _error = 'No se pudo usar el micrófono.');
    }
  }

  Future<void> _stop() async {
    if (_phase != _Phase.listening) return;
    _timer?.cancel();
    _amp?.cancel();
    Haptics.soft();
    setState(() {
      _phase = _Phase.thinking;
      _level = 0;
    });
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (path == null || path.isEmpty || _seconds < 1) {
      setState(() {
        _phase = _Phase.idle;
        _error = 'Mantén presionado un poco más y habla con naturalidad.';
      });
      return;
    }
    Uint8List? bytes;
    try {
      bytes = await XFile(path).readAsBytes();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (bytes == null) {
      setState(() => _phase = _Phase.idle);
      return;
    }
    await _ask(audio: bytes);
  }

  // ───────────── Pregunta (en tiempo real) ─────────────
  StreamSubscription<CopilotEvent>? _sub;
  String _liveQuestion = '';
  String _liveAnswer = '';
  String _liveStatus = '';

  Future<void> _ask({String? text, Uint8List? audio}) async {
    final profile = AppState.instance.profile;
    if (profile == null) return;
    final q = text?.trim() ?? '';
    if (audio == null && q.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _tts.stop();
    await _sub?.cancel();
    setState(() {
      _phase = _Phase.thinking;
      _error = '';
      _text.clear();
      _liveQuestion = audio != null ? '🎙️' : q;
      _liveAnswer = '';
      _liveStatus = audio != null ? 'Escuchando lo que dijiste…' : 'Pensando…';
    });
    _toBottom();
    final events = audio != null
        ? CopilotStream.ask(audio: audio, filename: kIsWeb ? 'copiloto.webm' : 'copiloto.m4a', mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4', profile: profile)
        : CopilotStream.ask(text: q, profile: profile);
    _sub = events.listen((e) {
      if (!mounted) return;
      switch (e.type) {
        case 'status':
          setState(() => _liveStatus = e.text);
        case 'transcript':
          setState(() => _liveQuestion = e.text);
        case 'delta':
          // Las palabras aparecen apenas el modelo las escribe.
          setState(() => _liveAnswer += e.text);
          _toBottom();
        case 'final':
          final r = e.reply!;
          Haptics.success();
          setState(() {
            _turns.add(_Turn(audio != null ? (r.transcript.isEmpty ? _liveQuestion : r.transcript) : q, r));
            _phase = _Phase.idle;
            _liveAnswer = '';
            _liveQuestion = '';
          });
          _toBottom();
          _speak(r.speak, premium: audio != null);
        case 'error':
          Haptics.error();
          setState(() {
            _phase = _Phase.idle;
            _liveAnswer = '';
            _liveQuestion = '';
            _error = friendly(e.error ?? AppException('No pude procesar tu pedido.'));
          });
      }
    });
  }

  // ───────────── Acciones ─────────────
  void _act(AssistantReply r) {
    final nav = widget.nav;
    Navigator.of(context).pop();
    switch (r.intent) {
      case 'invoice':
        if (r.draft != null) {
          nav.push(MaterialPageRoute(builder: (_) => NewInvoiceScreen(initial: r.draft))).then((_) => AppState.instance.bump());
        }
      case 'quote':
        if (r.draft != null) {
          nav.push(MaterialPageRoute(builder: (_) => NewInvoiceScreen(quote: true, initial: r.draft))).then((_) => AppState.instance.bump());
        }
      case 'expense':
        if (r.expense != null) {
          showExpenseSheet(nav.context, prefill: r.expense).then((ok) {
            if (ok) {
              AppState.instance.bump();
              if (nav.mounted) showSuccess(nav.context, 'Gasto registrado');
            }
          });
        }
      case 'collections':
        nav.push(MaterialPageRoute(builder: (_) => const CollectionsScreen()));
      case 'fiado':
        final a = r.action;
        showFiadoSheet(
          nav.context,
          clientName: (a['client_name'] ?? '') as String,
          kind: a['kind'] == 'abono' ? 'abono' : 'cargo',
          amount: (a['amount'] as num?)?.toDouble(),
          description: (a['description'] ?? '') as String,
        ).then((ok) {
          if (ok) AppState.instance.bump();
        });
      case 'show':
        final a = r.action;
        final range = (a['range'] ?? 'today') as String;
        final Widget page = switch (a['screen']) {
          'collections' => const CollectionsScreen(),
          'expenses' => const ExpensesScreen(),
          'stock' => const ProductsScreen(),
          'clients' => const ClientsHubScreen(),
          'agenda' => const AgendaScreen(),
          'fiados' => const FiadosScreen(),
          'taxes' => const TaxesScreen(),
          'profit' => const ProfitScreen(),
          'cash' => const CashDayScreen(),
          _ => RangeSalesScreen(range: range),
        };
        nav.push(MaterialPageRoute(builder: (_) => page));
      case 'void':
        _openToVoid(nav, r.action);
    }
  }

  /// "Anula la última boleta de Juan": busca el último comprobante ACEPTADO de ese cliente y abre su ficha, donde se
  /// confirma la anulación (con el PIN del dueño si está activo). Nunca anula solo.
  Future<void> _openToVoid(NavigatorState nav, Map<String, dynamic> a) async {
    final name = ((a['client_name'] ?? '') as String).trim().toLowerCase();
    final kind = (a['doc_kind'] ?? '') as String;
    try {
      final list = await Repo.listInvoices(limit: 300);
      final match = list.where((i) {
        if (i.fiscalStatus != 'accepted') return false;
        if (name.isNotEmpty && !i.clientName.toLowerCase().contains(name)) return false;
        final n = i.fiscalNumber ?? '';
        if (kind == 'boleta' && !n.startsWith('B')) return false;
        if (kind == 'factura' && !n.startsWith('F')) return false;
        return true;
      }).firstOrNull;
      if (match == null) {
        if (nav.mounted) ScaffoldMessenger.of(nav.context).showSnackBar(const SnackBar(content: Text('No encontré un comprobante aceptado de ese cliente.')));
        return;
      }
      await nav.push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: match.id)));
      AppState.instance.bump();
    } catch (e) {
      if (nav.mounted) ScaffoldMessenger.of(nav.context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  String? _actionLabel(AssistantReply r) => switch (r.intent) {
        'invoice' => r.draft == null ? null : 'Revisar y guardar la factura',
        'quote' => r.draft == null ? null : 'Revisar y guardar la cotización',
        'expense' => r.expense == null ? null : 'Confirmar el gasto',
        'collections' => 'Ir a Cobranza',
        'fiado' => r.action.isEmpty ? null : (r.action['kind'] == 'abono' ? 'Confirmar el abono' : 'Confirmar el fiado'),
        'show' => 'Ver ahora',
        'void' => 'Buscar el comprobante para anular',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final listening = _phase == _Phase.listening;
    final thinking = _phase == _Phase.thinking;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Brand.indigo),
          const SizedBox(width: 8),
          Expanded(child: Text('Copiloto', style: t.textTheme.titleLarge)),
          IconButton(
            tooltip: _muted ? 'Activar voz' : 'Silenciar voz',
            onPressed: () {
              setState(() => _muted = !_muted);
              if (_muted) {
                _tts.stop();
                PremiumVoice.instance.stop();
              }
            },
            icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          children: [
            if (_turns.isEmpty) ...[
              const SizedBox(height: 8),
              Center(child: AiOrb(size: 170, level: _level, active: listening, thinking: thinking)),
              const SizedBox(height: 8),
              Text(
                listening ? 'Te escucho… (${_maxSeconds - _seconds} s)' : (thinking ? 'Pensando…' : 'Pregúntame por tu negocio o dame una orden'),
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Conozco tus ventas, cobros, gastos, clientes y stock. También puedo crear facturas, cotizaciones y gastos.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (final s in _starters) ActionChip(label: Text(s), onPressed: thinking || listening ? null : () => _ask(text: s)),
              ]),
            ] else
              for (final (i, turn) in _turns.indexed) ...[
                _Bubble(text: turn.question),
                if (turn.reply != null) Reveal(key: ValueKey('r$i'), child: _answer(context, turn.reply!, last: i == _turns.length - 1)),
              ],
            // Respuesta EN VIVO: la pregunta y el texto que va llegando, palabra por palabra.
            if (thinking && _liveQuestion.isNotEmpty) ...[
              if (_turns.isNotEmpty || _liveAnswer.isNotEmpty) _Bubble(text: _liveQuestion),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(22), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
                    boxShadow: Brand.softShadow(t.brightness == Brightness.dark, a: 0.08),
                  ),
                  child: _liveAnswer.isEmpty
                      ? Row(children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_liveStatus, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
                        ])
                      : Text('$_liveAnswer▍', style: t.textTheme.bodyLarge),
                ),
              ),
            ],
            if (_turns.isNotEmpty && listening)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(child: AiOrb(size: 90, level: _level, active: listening, thinking: thinking)),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Brand.bad, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
      AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 14 + bottom),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              enabled: !thinking && !listening,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) => _ask(text: v),
              decoration: InputDecoration(
                hintText: 'Escribe tu pregunta…',
                isDense: true,
                suffixIcon: IconButton(icon: const Icon(Icons.send_rounded), onPressed: thinking ? null : () => _ask(text: _text.text)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _listen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening ? Brand.bad : null,
                gradient: listening ? null : Brand.coralGradient,
                boxShadow: [BoxShadow(color: (listening ? Brand.bad : Brand.goldDeep).withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: thinking
                  ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _answer(BuildContext context, AssistantReply r, {required bool last}) {
    final t = Theme.of(context);
    final action = _actionLabel(r);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(22), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
            boxShadow: Brand.softShadow(t.brightness == Brightness.dark, a: 0.08),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.answer, style: t.textTheme.bodyLarge),
            if (r.highlights.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final h in r.highlights)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: _tone(h.tone).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(h.label, style: t.textTheme.labelSmall),
                      Text(h.value, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: _tone(h.tone), fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                  ),
              ]),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              GradientButton(label: action, icon: Icons.arrow_forward_rounded, onPressed: () => _act(r)),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Escuchar',
                onPressed: () => _speak(r.speak.isEmpty ? r.answer : r.speak, premium: true),
                icon: Icon(Icons.volume_up_rounded, size: 18, color: t.colorScheme.onSurfaceVariant),
              ),
            ),
          ]),
        ),
        if (last && r.suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in r.suggestions) ActionChip(avatar: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16), label: Text(s), onPressed: () => _ask(text: s)),
          ]),
        ],
      ]),
    );
  }

  Color _tone(String tone) => switch (tone) {
        'ok' => Brand.ok,
        'warn' => Brand.warn,
        'bad' => Brand.bad,
        _ => Brand.indigo,
      };
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 8, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          gradient: Brand.heroGradient,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(6), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
        ),
        child: Text(text, style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 15)),
      ),
    );
  }
}


/// "Muéstrame las ventas de ayer / de la semana": lista los comprobantes del rango con su total (solo emitidos).
class RangeSalesScreen extends StatefulWidget {
  const RangeSalesScreen({super.key, required this.range});
  final String range; // today | yesterday | this_week | this_month | last_month

  @override
  State<RangeSalesScreen> createState() => _RangeSalesScreenState();
}

class _RangeSalesScreenState extends State<RangeSalesScreen> {
  List<InvoiceRecord>? _items;
  String? _error;

  (DateTime, DateTime, String) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (widget.range) {
      'yesterday' => (today.subtract(const Duration(days: 1)), today, 'Ayer'),
      'this_week' => (today.subtract(Duration(days: today.weekday - 1)), today.add(const Duration(days: 1)), 'Esta semana'),
      'this_month' => (DateTime(now.year, now.month, 1), today.add(const Duration(days: 1)), 'Este mes'),
      'last_month' => (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 1), 'Mes pasado'),
      _ => (today, today.add(const Duration(days: 1)), 'Hoy'),
    };
  }

  @override
  void initState() {
    super.initState();
    final (from, to, _) = _bounds();
    Repo.listInvoicesBetween(todayIso(from), todayIso(to)).then((r) {
      if (mounted) setState(() => _items = r.where((i) => i.countsAsSale).toList());
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendly(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (_, _, label) = _bounds();
    final items = _items ?? const <InvoiceRecord>[];
    final cur = AppState.instance.profile?.currency ?? 'PEN';
    final total = items.where((i) => i.currency == cur).fold(0.0, (s, i) => s + i.signedTotal);
    return Scaffold(
      appBar: AppBar(title: Text('Ventas · $label')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _items == null
              ? const SkeletonList()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  SoftCard(
                    child: Row(children: [
                      Expanded(child: Text('${items.length} ventas', style: t.textTheme.titleMedium)),
                      Money(money(total, cur), size: 22, weight: FontWeight.w800),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty) const EmptyState(title: 'Sin ventas', body: 'No hay comprobantes emitidos en ese periodo.'),
                  for (final i in items)
                    ListTile(
                      title: Text('${i.fiscalNumber ?? i.number} · ${i.clientName}'),
                      subtitle: Text(displayDate(i.issueDate)),
                      trailing: Money(money(i.totals.total, i.currency), weight: FontWeight.w700),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: i.id))),
                    ),
                ]),
    );
  }
}
