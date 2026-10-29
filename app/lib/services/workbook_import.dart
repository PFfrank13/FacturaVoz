// Importador de libros Excel con varias hojas (clientes, comprobantes, detalle, catálogo).
// 1) El servidor lee y clasifica el archivo (/api/import/workbook) y devuelve vista previa + datos normalizados.
// 2) La app guarda por bloques con su sesión (RLS + permisos en la base): clientes → productos → comprobantes.
// 3) La base cuenta lo que quedó guardado y lo compara con lo esperado. Se puede deshacer completo.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import 'pro_api.dart' show apiToken;

/// ¿Es un .xlsx con 2 o más hojas? (los nombres de archivo del zip no están comprimidos)
bool looksLikeWorkbook(Uint8List b) {
  if (b.length < 4 || b[0] != 0x50 || b[1] != 0x4B) return false;
  final needle = ascii.encode('xl/worksheets/sheet');
  var hits = 0;
  outer:
  for (var i = 0; i + needle.length < b.length; i++) {
    for (var k = 0; k < needle.length; k++) {
      if (b[i + k] != needle[k]) continue outer;
    }
    hits++;
    if (hits >= 4) return true; // cada hoja aparece 2 veces (encabezado local + directorio)
  }
  return false;
}

class WbAnalysis {
  WbAnalysis(this.preview, this.payload);
  final Map<String, dynamic> preview;
  final Map<String, dynamic> payload;

  Map<String, dynamic> get counts => Map<String, dynamic>.from(preview['counts'] as Map? ?? {});
  Map<String, dynamic> get totals => Map<String, dynamic>.from(preview['totals'] as Map? ?? {});
  List<Map<String, dynamic>> get sheets => [for (final s in (preview['sheets'] as List? ?? [])) Map<String, dynamic>.from(s as Map)];
  List<Map<String, dynamic>> get warnings => [for (final s in (preview['warnings'] as List? ?? [])) Map<String, dynamic>.from(s as Map)];
  int count(String k) => (counts[k] as num?)?.toInt() ?? 0;
  Map<String, double> money(String k) => {for (final e in Map<String, dynamic>.from(totals[k] as Map? ?? {}).entries) e.key: (e.value as num).toDouble()};
}

class WbProgress {
  const WbProgress(this.step, this.done, this.total);
  final String step;
  final int done;
  final int total;
  double get fraction => total == 0 ? 0 : done / total;
}

class WorkbookImporter {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<WbAnalysis> analyze(Uint8List bytes, {double taxRate = 18}) async {
    final res = await http
        .post(Uri.parse('${Config.apiBase}/api/import/workbook?rate=$taxRate'),
            headers: {'Authorization': 'Bearer ${await apiToken()}', 'Content-Type': 'application/octet-stream'}, body: bytes)
        .timeout(const Duration(seconds: 60));
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw AppException('El servidor no respondió bien (${res.statusCode}). Inténtalo de nuevo.');
    }
    if (res.statusCode != 200) throw AppException((body['error'] as String?) ?? 'No pude leer el Excel.');
    return WbAnalysis(Map<String, dynamic>.from(body['preview'] as Map), Map<String, dynamic>.from(body['payload'] as Map));
  }

  static List<List<dynamic>> _chunks(List<dynamic> l, int n) => [for (var i = 0; i < l.length; i += n) l.sublist(i, i + n > l.length ? l.length : i + n)];

  /// Guarda todo por bloques. Devuelve {job, result} con lo que realmente quedó en la base.
  static Future<(String, Map<String, dynamic>)> run(String org, String fileName, WbAnalysis a, void Function(WbProgress) onProgress) async {
    final clients = (a.payload['clients'] as List?) ?? const [];
    final products = (a.payload['products'] as List?) ?? const [];
    final docs = (a.payload['docs'] as List?) ?? const [];
    final total = clients.length + products.length + docs.length;
    var done = 0;
    final warnings = [for (final w in a.warnings) {'code': w['code'], 'message': w['message'], 'count': w['count']}];
    final job = await _db.rpc('wb_import_begin', params: {'p_org': org, 'p_file': fileName, 'p_expected': a.counts..addAll({'net': a.money('net')}), 'p_warnings': warnings}) as String;
    for (final c in _chunks(clients, 1000)) {
      await _db.rpc('wb_import_clients', params: {'p_job': job, 'p_rows': c});
      done += c.length;
      onProgress(WbProgress('Clientes', done, total));
    }
    for (final c in _chunks(products, 500)) {
      await _db.rpc('wb_import_products', params: {'p_job': job, 'p_rows': c});
      done += c.length;
      onProgress(WbProgress('Productos', done, total));
    }
    for (final c in _chunks(docs, 200)) {
      await _db.rpc('wb_import_docs', params: {'p_job': job, 'p_docs': c});
      done += c.length;
      onProgress(WbProgress('Comprobantes', done, total));
    }
    final r = await _db.rpc('wb_import_finish', params: {'p_job': job});
    return (job, Map<String, dynamic>.from(r as Map));
  }

  static Future<Map<String, dynamic>> undo(String job) async => Map<String, dynamic>.from(await _db.rpc('wb_import_undo', params: {'p_job': job}) as Map);

  static Future<List<Map<String, dynamic>>> history(String org) async => [
        for (final r in await _db.from('wb_imports').select('id, file_name, status, result, created_at, undone_at').eq('org_id', org).order('created_at', ascending: false).limit(20))
          Map<String, dynamic>.from(r)
      ];
}
