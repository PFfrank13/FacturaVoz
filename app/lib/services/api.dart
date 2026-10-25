import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import '../models.dart';

Future<String> _accessToken() async {
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

class FiscalResult {
  FiscalResult({required this.status, required this.number, required this.message});
  final String status; // accepted | rejected | error
  final String number;
  final String message;
}

/// Facturación electrónica SUNAT (vía backend → Lycet). Los secretos nunca se guardan en la app.
class FiscalApi {
  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {int seconds = 70}) async {
    final token = await _accessToken();
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${Config.apiBase}$path'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: seconds));
    } catch (_) {
      throw AppException('No hay conexión con el servidor. Inténtalo de nuevo.');
    }
    Map<String, dynamic> data = {};
    try {
      data = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode == 401) throw AppException('Sesión caducada. Vuelve a entrar.');
    if (res.statusCode >= 400) {
      throw AppException((data['error'] as String?) ?? 'No se pudo completar la operación.');
    }
    return data;
  }

  static Future<void> setup({
    required String solUser,
    required String solPassword,
    required Uint8List certificate,
    required String certificateFormat, // pfx | pem
    required String certificatePassword,
    required String env, // beta | prod
  }) async {
    await _post('/api/fiscal/setup', {
      'sol_user': solUser,
      'sol_password': solPassword,
      'certificate_b64': base64Encode(certificate),
      'certificate_format': certificateFormat,
      'certificate_password': certificatePassword,
      'env': env,
    });
  }

  static Future<FiscalResult> emit({
    required String invoiceId,
    required String docType,
    required String afectacion,
    required String unit,
    required String clientDocType,
    required String clientDocNumber,
    required String clientName,
    required String clientAddress,
  }) async {
    final d = await _post('/api/fiscal/emit', {
      'invoice_id': invoiceId,
      'doc_type': docType,
      'afectacion': afectacion,
      'unit': unit,
      'client_doc_type': clientDocType,
      'client_doc_number': clientDocNumber,
      'client_name': clientName,
      'client_address': clientAddress,
    }, seconds: 90);
    return FiscalResult(
      status: (d['status'] ?? 'error') as String,
      number: fiscalNumberOf((d['series'] ?? '') as String, ((d['correlative'] ?? 0) as num).toInt()),
      message: (d['message'] ?? '') as String,
    );
  }

  /// Anula un comprobante ACEPTADO con una nota de crédito total (motivo 01 o 06).
  static Future<FiscalResult> creditNote({required String invoiceId, required String reasonCode, String reasonText = ''}) async {
    final d = await _post('/api/fiscal/note', {
      'invoice_id': invoiceId,
      'reason_code': reasonCode,
      'reason_text': reasonText,
    }, seconds: 90);
    return FiscalResult(
      status: (d['status'] ?? 'error') as String,
      number: fiscalNumberOf((d['series'] ?? '') as String, ((d['correlative'] ?? 0) as num).toInt()),
      message: (d['message'] ?? '') as String,
    );
  }
}

/// Llama al backend (/api/parse). La clave de Groq vive SOLO en el servidor;
/// la app envía únicamente el token de sesión del usuario.
class ApiService {
  static Future<InvoiceDraft> parseAudio({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required Profile profile,
  }) async {
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

    final req = http.MultipartRequest('POST', Uri.parse('${Config.apiBase}/api/parse'))
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes(
        'audio',
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ));

    http.Response res;
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      res = await http.Response.fromStream(streamed);
    } catch (_) {
      throw AppException('No hay conexión con el servidor. Inténtalo de nuevo.', code: 'net');
    }

    Map<String, dynamic> body = {};
    try {
      body = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}

    if (res.statusCode == 200 && body['invoice'] is Map) {
      return InvoiceDraft.fromParse(Map<String, dynamic>.from(body['invoice'] as Map), profile);
    }
    final code = (body['code'] as String?) ?? 'http_${res.statusCode}';
    switch (res.statusCode) {
      case 401:
        throw AppException('Sesión caducada. Vuelve a entrar.');
      case 403:
        throw AppException('El servidor rechazó la solicitud.', code: 'http_403');
      case 404:
        throw AppException('No se encontró el servicio de voz. Revisa API_BASE_URL y el despliegue.', code: 'http_404');
      case 429:
        throw AppException('Demasiados dictados seguidos. Espera un minuto.');
      case 413:
        throw AppException('El audio es demasiado largo. Dicta algo más corto.');
      case 422:
        throw AppException((body['error'] as String?) ?? 'No se entendió el dictado. Inténtalo de nuevo.', code: code);
      default:
        throw AppException((body['error'] as String?) ?? 'Error del servidor. Inténtalo de nuevo.', code: code);
    }
  }
}
