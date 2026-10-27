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
