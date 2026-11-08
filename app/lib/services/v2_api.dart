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
  /// Quita el fondo de una fotografía de catálogo usando el servidor.
  /// Los bytes PNG solo se guardan si el usuario acepta el resultado.
  static Future<Uint8List> removeProductBackground(Uint8List source, {String mime = 'image/jpeg'}) async {
    final org = Repo.activeOrgId;
    if (org == null) throw AppException('Selecciona la empresa antes de procesar fotos.');
    if (source.isEmpty || source.length > 3000000) {
      throw AppException('Elige una foto de máximo 3 MB.');
    }
    final req = http.MultipartRequest('POST', Uri.parse('${Config.apiBase}/api/products/remove-bg'))
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..fields['org_id'] = org
      ..files.add(http.MultipartFile.fromBytes(
        'image', source, filename: 'producto.${mime == 'image/png' ? 'png' : 'jpg'}',
        contentType: MediaType.parse(mime),
      ));
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 65)),
      );
    } catch (_) {
      throw AppException('No se pudo conectar con el procesador de imágenes.', code: 'net');
    }
    if (response.statusCode != 200) {
      final error = _decode(response)['error'];
      throw AppException(error is String ? error : 'No se pudo quitar el fondo.');
    }
    final png = response.bodyBytes;
    if (png.length < 12 || png.length > 4000000 ||
        png[0] != 0x89 || png[1] != 0x50 || png[2] != 0x4e || png[3] != 0x47) {
      throw AppException('El servidor devolvió una imagen PNG inválida.');
    }
    return png;
  }

  /// Consulta DNI/RUC. Nunca lanza por "no encontrado": devuelve el motivo para dejar escribir a mano.
  static Future<LookupResult> lookup(String number) async {
    try {
      final (status, body) = await _post('/api/lookup', {'number': number, if (Repo.activeOrgId != null) 'org_id': Repo.activeOrgId}, seconds: 15);
      if (body['ok'] == true && body['data'] is Map) return LookupResult(data: DocLookup.fromJson(Map<String, dynamic>.from(body['data'] as Map)));
      return LookupResult(message: (body['message'] ?? body['error'] ?? 'Escribe los datos a mano.') as String, reason: (body['reason'] ?? 'http_$status') as String);
    } on AppException catch (e) {
      return LookupResult(message: e.message, reason: e.code ?? 'error');
    }
  }

  /// Tipo de cambio del día (null si no hay proveedor: la app pide escribirlo).
  static Future<({double? buy, double? sell, String message})> fx(String date, {String currency = 'USD'}) async {
    try {
      final (_, body) = await _post('/api/fx', {'date': date, 'currency': currency, if (Repo.activeOrgId != null) 'org_id': Repo.activeOrgId}, seconds: 15);
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
      ..fields.addAll({if (Repo.activeOrgId != null) 'org_id': Repo.activeOrgId!})
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

  /// Valida contra Solvex Hub el código ligado al ID de esta empresa.
  /// La app no decide el plan ni guarda la clave.
  static Future<({String plan, String mode})> activateLicense(String code) async {
    final org = Repo.activeOrgId;
    if (org == null) throw AppException('Primero crea o selecciona tu empresa.');
    final (status, body) = await _post('/api/license/activate',
      {'org_id': org, 'license_key': code.trim()}, seconds: 35);
    if (status != 200 || body['ok'] != true) {
      throw AppException((body['error'] ?? 'No se pudo activar la licencia.') as String);
    }
    return (plan: (body['plan'] ?? '') as String, mode: (body['mode'] ?? '') as String);
  }

  /// Cierre del día: guarda y envía el reporte al dueño por correo.
  static Future<({bool emailed, DaySummary summary})> closeDay({required String day, double? counted, String note = ''}) async {
    final (status, body) = await _post('/api/day-close', {'org_id': Repo.activeOrgId, 'day': day, 'counted': counted, 'note': note});
    if (status >= 400) throw AppException((body['error'] ?? 'No se pudo cerrar la caja.') as String);
    return (emailed: body['emailed'] == true, summary: DaySummary(Map<String, dynamic>.from((body['summary'] ?? const {}) as Map)));
  }
}
