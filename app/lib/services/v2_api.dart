// Llamadas al servidor (Vercel) de la v2.0. Las claves de proveedores (DNI/RUC, Groq, Solvex Hub) viven SOLO allá.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import '../models_v2.dart';
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

Map<String, dynamic> _decode(http.Response r) {
  try {
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  } catch (_) {
    return {};
  }
}

Future<(int, Map<String, dynamic>)> _post(String path, Map<String, dynamic> body, {int seconds = 30}) async {
  final http.Response r;
  try {
    r = await http
        .post(Uri.parse('${Config.apiBase}$path'), headers: {'Authorization': 'Bearer ${await _token()}', 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(Duration(seconds: seconds));
  } on AppException {
    rethrow;
  } catch (_) {
    throw AppException('Sin conexión con el servidor. Inténtalo de nuevo.', code: 'net');
  }
  if (r.statusCode == 401) throw AppException('Sesión caducada. Vuelve a entrar.');
  if (r.statusCode == 404) throw AppException('El servidor aún no tiene esta función: sube el backend v2.0 a Vercel.', code: 'http_404');
  return (r.statusCode, _decode(r));
}

class LookupResult {
  const LookupResult({this.data, this.message = '', this.reason = ''});
  final DocLookup? data;
  final String message;
  final String reason;
  bool get ok => data != null;
}

class V2Api {
  /// Consulta DNI/RUC. Nunca lanza por "no encontrado": devuelve el motivo para dejar escribir a mano.
  static Future<LookupResult> lookup(String number) async {
    try {
      final (status, body) = await _post('/api/lookup', {'number': number}, seconds: 15);
      if (body['ok'] == true && body['data'] is Map) return LookupResult(data: DocLookup.fromJson(Map<String, dynamic>.from(body['data'] as Map)));
      return LookupResult(message: (body['message'] ?? body['error'] ?? 'Escribe los datos a mano.') as String, reason: (body['reason'] ?? 'http_$status') as String);
    } on AppException catch (e) {
      return LookupResult(message: e.message, reason: e.code ?? 'error');
    }
  }

  /// Tipo de cambio del día (null si no hay proveedor: la app pide escribirlo).
  static Future<({double? buy, double? sell, String message})> fx(String date, {String currency = 'USD'}) async {
    try {
      final (_, body) = await _post('/api/fx', {'date': date, 'currency': currency}, seconds: 15);
      if (body['ok'] == true) {
        return (buy: (body['buy'] as num?)?.toDouble(), sell: (body['sell'] as num?)?.toDouble(), message: '');
      }
      return (buy: null, sell: null, message: (body['message'] ?? 'Escribe el tipo de cambio del día.') as String);
    } on AppException catch (e) {
      return (buy: null, sell: null, message: e.message);
    }
  }

  /// Foto de cuaderno / nota / WhatsApp → venta para confirmar.
  static Future<NotebookSale> notebook(Uint8List jpg) async {
    final req = http.MultipartRequest('POST', Uri.parse('${Config.apiBase}/api/notebook'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..fields.addAll({if (Repo.activeOrgId != null) 'org_id': Repo.activeOrgId!})
      ..files.add(http.MultipartFile.fromBytes('image', jpg, filename: 'nota.jpg', contentType: MediaType('image', 'jpeg')));
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 70)));
    } catch (_) {
      throw AppException('Sin conexión con el servidor. Inténtalo de nuevo.', code: 'net');
    }
    final body = _decode(r);
    if (r.statusCode == 200 && body['sale'] is Map) return NotebookSale.fromJson(Map<String, dynamic>.from(body['sale'] as Map));
    if (r.statusCode == 404) throw AppException('El servidor aún no tiene esta función: sube el backend v2.0 a Vercel.');
    throw AppException((body['error'] ?? 'No pude leer la foto.') as String, code: 'http_${r.statusCode}');
  }

  /// Voz → texto (buscador universal).
  static Future<String> transcribe(Uint8List bytes, {required String filename, required String mimeType}) async {
    final req = http.MultipartRequest('POST', Uri.parse('${Config.apiBase}/api/transcribe'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..files.add(http.MultipartFile.fromBytes('audio', bytes, filename: filename, contentType: MediaType.parse(mimeType)));
    final http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 40)));
    } catch (_) {
      throw AppException('Sin conexión con el servidor.', code: 'net');
    }
    final body = _decode(r);
    if (r.statusCode == 200) return (body['text'] ?? '') as String;
    throw AppException((body['error'] ?? 'No se entendió el audio.') as String);
  }

  /// Activa la prueba gratis de 3 días en Solvex Hub (necesita el RUC de la empresa).
  static Future<({String status, String message})> requestTrial() async {
    final (_, body) = await _post('/api/license/trial', {'org_id': Repo.activeOrgId}, seconds: 25);
    return (status: (body['status'] ?? 'error') as String, message: (body['message'] ?? body['error'] ?? '') as String);
  }

  /// Cierre del día: guarda y envía el reporte al dueño por correo.
  static Future<({bool emailed, DaySummary summary})> closeDay({required String day, double? counted, String note = ''}) async {
    final (status, body) = await _post('/api/day-close', {'org_id': Repo.activeOrgId, 'day': day, 'counted': counted, 'note': note});
    if (status >= 400) throw AppException((body['error'] ?? 'No se pudo cerrar la caja.') as String);
    return (emailed: body['emailed'] == true, summary: DaySummary(Map<String, dynamic>.from((body['summary'] ?? const {}) as Map)));
  }
}
