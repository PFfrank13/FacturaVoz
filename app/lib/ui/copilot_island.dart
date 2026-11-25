// Copiloto dentro de la Isla Dinámica (planes con Copiloto: Pro y Empresa).
// Cabe en la vista expandida que recomienda Apple (alto de 84 a 160 pt): una pregunta, su respuesta en vivo y una fila
// para escribir o hablar. Para seguir con acciones (facturar, anotar fiado, etc.) se abre el Copiloto completo.
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../errors.dart';
import '../services/pro_api.dart';

class CopilotIslandPanel extends StatefulWidget {
  const CopilotIslandPanel({super.key, required this.onClose, required this.onOpenFull});

  final VoidCallback onClose;

  /// Abre el Copiloto completo (con la pregunta, si hay una).
  final void Function(String? ask) onOpenFull;

  @override
  State<CopilotIslandPanel> createState() => _CopilotIslandPanelState();
}

class _CopilotIslandPanelState extends State<CopilotIslandPanel> {
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  StreamSubscription<CopilotEvent>? _sub;
  Timer? _tick;
  String _question = '';
  String _answer = '';
  String _status = '';
  String _error = '';
  bool _busy = false;
  bool _recording = false;
  bool _actionable = false;
  int _seconds = 0;

  static const _maxSeconds = 30;
  static const _white = Colors.white;
  static const _soft = Color(0xffc3cdda);
  static const _accent = Color(0xffb69cff);

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _text.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _ask({String? text, Uint8List? audio}) async {
    final profile = AppState.instance.profile;
    final q = text?.trim() ?? '';
    if (profile == null || (audio == null && q.isEmpty) || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _sub?.cancel();
    setState(() {
      _busy = true;
      _error = '';
      _actionable = false;
      _question = audio != null ? '🎙️' : q;
      _answer = '';
      _status = audio != null ? 'Escuchando lo que dijiste…' : 'Pensando…';
      _text.clear();
    });
    final events = audio != null
        ? CopilotStream.ask(audio: audio, filename: kIsWeb ? 'copiloto.webm' : 'copiloto.m4a', mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4', profile: profile)
        : CopilotStream.ask(text: q, profile: profile);
    _sub = events.listen((e) {
      if (!mounted) return;
      switch (e.type) {
        case 'status':
          setState(() => _status = e.text);
        case 'transcript':
          setState(() => _question = e.text);
        case 'delta':
          setState(() => _answer += e.text);
        case 'final':
          final r = e.reply!;
          setState(() {
            _busy = false;
            _answer = r.answer.isNotEmpty ? r.answer : r.speak;
            if (r.transcript.isNotEmpty) _question = r.transcript;
            // Facturar, anotar fiado, registrar un gasto…: se confirma en el Copiloto completo.
            _actionable = !const {'question', 'summary', 'unknown'}.contains(r.intent);
          });
        case 'error':
          setState(() {
            _busy = false;
            _error = friendly(e.error ?? AppException('No pude procesar tu pedido.'));
          });
      }
    }, onError: (Object err) {
      if (mounted) setState(() { _busy = false; _error = friendly(err); });
    });
  }

  Future<void> _mic() async {
    if (_recording) return _stop();
    if (_busy) return;
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Permite el micrófono en los ajustes del teléfono.');
        return;
      }
      var path = '';
      if (!kIsWeb) path = '${(await getTemporaryDirectory()).path}/isla_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc, bitRate: 64000, sampleRate: 16000, numChannels: 1), path: path);
      _seconds = 0;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _seconds++);
        if (_seconds >= _maxSeconds) _stop();
      });
      setState(() { _recording = true; _error = ''; });
    } catch (_) {
      setState(() => _error = 'No se pudo usar el micrófono.');
    }
  }

  Future<void> _stop() async {
    _tick?.cancel();
    setState(() => _recording = false);
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (path == null || path.isEmpty || _seconds < 1) {
      setState(() => _error = 'Habla un poco más y vuelve a tocar el micrófono.');
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
    if (bytes != null) await _ask(audio: bytes);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = _error.isNotEmpty
        ? _error
        : _answer.isNotEmpty
            ? _answer
            : _busy
                ? _status
                : _recording
                    ? 'Te escucho… toca el micrófono para enviar (${_maxSeconds - _seconds} s)'
                    : 'Pregúntame por tus ventas, fiados, caja o qué reponer.';
    return Column(
      key: const ValueKey('copilot-island'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xffd3c4ff), Color(0xff7d6cf0)])),
            child: const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xff10142a)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_question.isEmpty ? 'Copiloto' : _question, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.titleSmall?.copyWith(color: _white, fontWeight: FontWeight.w800)),
          ),
          if (_actionable || _answer.isNotEmpty)
            _RoundIcon(icon: Icons.open_in_full_rounded, tooltip: 'Abrir en grande', onTap: () => widget.onOpenFull(_actionable ? _question : null)),
          _RoundIcon(icon: Icons.close_rounded, tooltip: 'Cerrar', onTap: widget.onClose),
        ]),
        const SizedBox(height: 6),
        Flexible(
          child: SingleChildScrollView(
            reverse: _busy,
            child: Text(body,
                style: t.bodyMedium?.copyWith(color: _error.isNotEmpty ? const Color(0xffff9a8f) : (_answer.isNotEmpty ? _white : _soft), height: 1.3)),
          ),
        ),
        if (_actionable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: _accent, padding: EdgeInsets.zero, minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => widget.onOpenFull(_question),
                child: const Text('Continuar en el Copiloto para confirmarlo'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _text,
                enabled: !_recording,
                textInputAction: TextInputAction.send,
                onSubmitted: (v) => _ask(text: v),
                style: t.bodyMedium?.copyWith(color: _white),
                cursorColor: _accent,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Escribe tu pregunta…',
                  hintStyle: t.bodyMedium?.copyWith(color: const Color(0xff8a96a8)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .10),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _RoundIcon(
            icon: _recording ? Icons.stop_rounded : Icons.mic_rounded,
            tooltip: _recording ? 'Enviar audio' : 'Hablar',
            size: 40,
            color: _recording ? const Color(0xffff6b6b) : Colors.white.withValues(alpha: .14),
            onTap: _mic,
          ),
          const SizedBox(width: 6),
          _RoundIcon(
            icon: _busy ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded,
            tooltip: 'Enviar',
            size: 40,
            color: _accent,
            iconColor: const Color(0xff10142a),
            onTap: _busy ? null : () => _ask(text: _text.text),
          ),
        ]),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap, this.size = 30, this.color, this.iconColor = Colors.white});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: color ?? Colors.white.withValues(alpha: .12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, size: size * .5, color: iconColor)),
          ),
        ),
      );
}
