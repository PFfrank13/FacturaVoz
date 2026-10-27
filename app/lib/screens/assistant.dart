import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models_pro.dart';
import '../services/pro_api.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'collections.dart';
import 'expenses.dart';
import 'new_invoice.dart';

/// Abre el Copiloto: pregunta por tu negocio o da una orden, por voz o por texto.
Future<void> openCopilot(BuildContext context) {
  final nav = Navigator.of(context);
  Haptics.soft();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.9, child: _CopilotSheet(nav: nav)),
  );
}

enum _Phase { idle, listening, thinking }

class _Turn {
  _Turn(this.question, this.reply);
  final String question;
  final AssistantReply? reply;
}

class _CopilotSheet extends StatefulWidget {
  const _CopilotSheet({required this.nav});
  final NavigatorState nav;

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
    '¿Cuánto vendí este mes?',
    '¿Quién me debe más?',
    '¿Cuánto gané este mes?',
    '¿Qué producto se me está acabando?',
    'Gasté 50 soles en movilidad',
    'Cotiza a Corpax 3 sillas a 150',
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
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
    _timer?.cancel();
    _amp?.cancel();
    _recorder.dispose();
    _tts.stop();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _speak(String s) async {
    if (_muted || s.trim().isEmpty) return;
    try {
      await _tts.stop();
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

  // ───────────── Pregunta ─────────────
  Future<void> _ask({String? text, Uint8List? audio}) async {
    final profile = AppState.instance.profile;
    if (profile == null) return;
    final q = text?.trim() ?? '';
    if (audio == null && q.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _phase = _Phase.thinking;
      _error = '';
      _text.clear();
    });
    _toBottom();
    try {
      final r = audio != null
          ? await AssistantApi.askAudio(audio, filename: kIsWeb ? 'copiloto.webm' : 'copiloto.m4a', mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4', profile: profile)
          : await AssistantApi.askText(q, profile);
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _turns.add(_Turn(audio != null ? (r.transcript.isEmpty ? '🎙️' : r.transcript) : q, r));
        _phase = _Phase.idle;
      });
      _toBottom();
      _speak(r.speak);
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      setState(() {
        _phase = _Phase.idle;
        _error = friendly(e);
      });
    }
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
    }
  }

  String? _actionLabel(AssistantReply r) => switch (r.intent) {
        'invoice' => r.draft == null ? null : 'Revisar y guardar la factura',
        'quote' => r.draft == null ? null : 'Revisar y guardar la cotización',
        'expense' => r.expense == null ? null : 'Confirmar el gasto',
        'collections' => 'Ir a Cobranza',
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
              if (_muted) _tts.stop();
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
            if (_turns.isNotEmpty && (thinking || listening))
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
                onPressed: () => _speak(r.speak.isEmpty ? r.answer : r.speak),
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
