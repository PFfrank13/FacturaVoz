import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import '../models.dart';
import '../models_pro.dart';
import 'repo.dart';

/// Token de sesión para llamar al servidor propio (nunca una clave secreta).
Future<String> apiToken() => _token();

Future<String> _token() async {
  final auth = Supabase.instance.client.auth;
  var session = auth.currentSession;
  if (session == null) throw AppException('Sesión caducada. Vuelve a entrar.');
  if (session.isExpired) {
    try {
      session = (await auth.refreshSession()).session;
    } catch (_) {
      session = null;
    }
    if (session == null) throw AppException('Sesión caducada. Vuelve a entrar.');
  }
  return session.accessToken;
}

Map<String, dynamic> _decode(http.Response res) {
  try {
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
  } catch (_) {
    return {};
  }
}

Never _fail(http.Response res, Map<String, dynamic> body, String fallback) {
  if (res.statusCode == 401) throw AppException('Sesión caducada. Vuelve a entrar.');
  if (res.statusCode == 404) throw AppException('El servidor aún no tiene esta función. Sube el backend actualizado a Vercel.', code: 'http_404');
  if (res.statusCode == 429) throw AppException((body['error'] as String?) ?? 'Demasiadas solicitudes seguidas. Espera un minuto.');
  throw AppException(
    (body['error'] as String?) ?? fallback,
    code: (body['code'] as String?) ?? 'http_${res.statusCode}',
    transcript: body['transcript'] is String && (body['transcript'] as String).trim().isNotEmpty ? body['transcript'] as String : null,
  );
}

Future<http.Response> _send(http.BaseRequest req, int seconds) async {
  try {
    final streamed = await req.send().timeout(Duration(seconds: seconds));
    return await http.Response.fromStream(streamed);
  } catch (_) {
    throw AppException('No hay conexión con el servidor. Inténtalo de nuevo.', code: 'net');
  }
}

/// Copiloto de voz/texto (POST /api/assistant).
class AssistantApi {
  static Future<AssistantReply> askText(String text, Profile profile) async {
    final req = http.Request('POST', Uri.parse('${Config.apiBase}/api/assistant'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'text': text, 'org_id': Repo.activeOrgId});
    final res = await _send(req, 50);
    final body = _decode(res);
    if (res.statusCode == 200 && body['reply'] is Map) return AssistantReply.fromJson(body, profile);
    _fail(res, body, 'No pude procesar tu pedido.');
  }

  static Future<AssistantReply> askAudio(Uint8List bytes, {required String filename, required String mimeType, required Profile profile}) async {
    final req = http.MultipartRequest('POST', Uri.parse('${Config.apiBase}/api/assistant'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..fields.addAll({if (Repo.activeOrgId != null) 'org_id': Repo.activeOrgId!})
      ..files.add(http.MultipartFile.fromBytes('audio', bytes, filename: filename, contentType: MediaType.parse(mimeType)));
    final res = await _send(req, 60);
    final body = _decode(res);
    if (res.statusCode == 200 && body['reply'] is Map) return AssistantReply.fromJson(body, profile);
    _fail(res, body, 'No pude procesar tu pedido.');
  }
}

/// Evento del Copiloto en tiempo real: status | transcript | delta (texto nuevo) | final (respuesta completa) | error.
class CopilotEvent {
  const CopilotEvent(this.type, {this.text = '', this.reply, this.error, this.code});
  final String type;
  final String text;
  final AssistantReply? reply;
  final AppException? error;
  final String? code;
}

/// Copiloto en TIEMPO REAL (Server-Sent Events): la respuesta aparece palabra por palabra mientras se genera.
/// En la web el navegador puede entregar todo al final (igual funciona, solo que sin el efecto de escritura).
class CopilotStream {
  static Stream<CopilotEvent> ask({String? text, Uint8List? audio, String filename = 'audio.m4a', String mimeType = 'audio/mp4', required Profile profile}) async* {
    final uri = Uri.parse('${Config.apiBase}/api/assistant');
    final http.BaseRequest req;
    if (audio != null) {
      req = http.MultipartRequest('POST', uri)
        ..fields.addAll({if (Repo.activeOrgId != null) 'org_id': Repo.activeOrgId!})
        ..files.add(http.MultipartFile.fromBytes('audio', audio, filename: filename, contentType: MediaType.parse(mimeType)));
    } else {
      req = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'text': text ?? '', 'org_id': Repo.activeOrgId});
    }
    req.headers['Authorization'] = 'Bearer ${await _token()}';
    req.headers['Accept'] = 'text/event-stream';
    final client = http.Client();
    try {
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(const Duration(seconds: 20));
      } catch (_) {
        throw AppException('No hay conexión con el servidor. Inténtalo de nuevo.', code: 'net');
      }
      if (res.statusCode != 200 || !(res.headers['content-type'] ?? '').contains('text/event-stream')) {
        final full = await http.Response.fromStream(res);
        final body = _decode(full);
        // Servidor anterior (sin streaming): responde JSON normal y se usa tal cual.
        if (full.statusCode == 200 && body['reply'] is Map) {
          yield CopilotEvent('final', text: (body['transcript'] ?? '') as String, reply: AssistantReply.fromJson(body, profile));
          return;
        }
        _fail(full, body, 'No pude procesar tu pedido.');
      }
      final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 45));
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        Map<String, dynamic> e;
        try {
          e = Map<String, dynamic>.from(jsonDecode(line.substring(5).trim()) as Map);
        } catch (_) {
          continue;
        }
        switch (e['t']) {
          case 'status':
          case 'transcript':
          case 'delta':
            yield CopilotEvent(e['t'] as String, text: (e['text'] ?? '') as String);
          case 'final':
            yield CopilotEvent('final', text: (e['transcript'] ?? '') as String, reply: AssistantReply.fromJson(e, profile));
            return;
          case 'error':
            final t = e['transcript'];
            yield CopilotEvent('error',
                error: AppException((e['error'] ?? 'No pude procesar tu pedido.') as String, code: e['code'] as String?, transcript: t is String && t.trim().isNotEmpty ? t : null));
            return;
        }
      }
    } on AppException catch (e) {
      yield CopilotEvent('error', error: e);
    } on TimeoutException {
      yield CopilotEvent('error', error: AppException('La respuesta tardó demasiado. Inténtalo de nuevo.', code: 'timeout'));
    } catch (_) {
      yield CopilotEvent('error', error: AppException('Se cortó la conexión. Inténtalo de nuevo.', code: 'net'));
    } finally {
      client.close();
    }
  }
}

/// Lectura de fotos con IA (POST /api/scan).
class ScanApi {
  static Future<http.Response> _post(Uint8List bytes, String kind) async {
    final req = http.MultipartRequest('POST', Uri.parse('${Config.apiBase}/api/scan'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..fields['kind'] = kind
      ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: 'foto.jpg', contentType: MediaType('image', 'jpeg')));
    return _send(req, 70);
  }

  static Future<DocScan> document(Uint8List bytes) async {
    final res = await _post(bytes, 'document');
    final body = _decode(res);
    if (res.statusCode == 200 && body['document'] is Map) return DocScan.fromJson(Map<String, dynamic>.from(body['document'] as Map));
    _fail(res, body, 'No pude leer el comprobante.');
  }

  static Future<PaymentScan> payment(Uint8List bytes) async {
    final res = await _post(bytes, 'payment');
    final body = _decode(res);
    if (res.statusCode == 200 && body['payment'] is Map) return PaymentScan.fromJson(Map<String, dynamic>.from(body['payment'] as Map));
    _fail(res, body, 'No pude leer la constancia.');
  }
}

/// Conexión de Mercado Pago (el token viaja una sola vez al servidor y se guarda cifrado).
class PayApi {
  static Future<bool> setMercadoPago(String? accessToken) async {
    final req = http.Request('POST', Uri.parse('${Config.apiBase}/api/pay/settings'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'org_id': Repo.activeOrgId, 'mp_access_token': accessToken});
    final res = await _send(req, 30);
    final body = _decode(res);
    if (res.statusCode == 200) return body['mp_enabled'] == true;
    _fail(res, body, 'No se pudo guardar.');
  }
}
