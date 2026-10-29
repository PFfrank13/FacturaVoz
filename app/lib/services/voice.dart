// Voz premium del Copiloto (D3). La app NUNCA habla con ElevenLabs: pide el audio a NUESTRO servidor (/api/tts),
// que guarda la clave en Vercel, usa caché y controla la cuota. Si no hay voz premium (sin clave, sin cuota, sin
// internet), se usa la voz del teléfono y se avisa una sola vez por qué.
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'pro_api.dart' show apiToken;
import 'repo.dart';

class PremiumVoice {
  PremiumVoice._();
  static final PremiumVoice instance = PremiumVoice._();

  final AudioPlayer _player = AudioPlayer();

  /// Último aviso (p. ej. "Falta ELEVENLABS_API_KEY en Vercel…"). La pantalla lo muestra una vez.
  final ValueNotifier<String> notice = ValueNotifier('');

  /// Uso del día: (usados, límite) en caracteres. null = aún no se sabe.
  final ValueNotifier<(int, int)?> usage = ValueNotifier(null);

  bool _disabledForSession = false;

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> refreshUsage() async {
    final org = Repo.activeOrgId;
    if (org == null) return;
    try {
      final r = await Supabase.instance.client.rpc('voice_quota', params: {'p_org': org});
      if (r is Map) usage.value = ((r['used'] as num?)?.toInt() ?? 0, (r['limit'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  /// Intenta hablar con la voz premium. Devuelve false si hay que usar la voz del teléfono.
  Future<bool> speak(String text) async {
    final org = Repo.activeOrgId;
    if (_disabledForSession || org == null || text.trim().isEmpty) return false;
    try {
      final res = await http
          .post(Uri.parse('${Config.apiBase}/api/tts'),
              headers: {'Authorization': 'Bearer ${await apiToken()}', 'Content-Type': 'application/json', 'Accept': 'audio/mpeg'},
              body: jsonEncode({'text': text, 'org_id': org}))
          .timeout(const Duration(seconds: 20));
      final ctype = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 && ctype.contains('audio')) {
        await _play(res.bodyBytes);
        refreshUsage();
        return true;
      }
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        final msg = (body['message'] ?? '') as String;
        if (msg.isNotEmpty) notice.value = msg;
        // Sin clave configurada: no se insiste en esta sesión (cero llamadas inútiles).
        if (body['code'] == 'tts_not_configured' || body['code'] == 'tts_auth') _disabledForSession = true;
      } catch (_) {}
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _play(Uint8List bytes) async {
    await _player.stop();
    if (kIsWeb) {
      await _player.play(UrlSource('data:audio/mpeg;base64,${base64Encode(bytes)}'));
      return;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/copiloto_voz.mp3');
    await f.writeAsBytes(bytes, flush: true);
    await _player.play(DeviceFileSource(f.path));
  }
}
