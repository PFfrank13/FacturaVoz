// Importación masiva: sube las filas por bloques, la base de datos las procesa por lotes y aquí solo se mira el progreso.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../import_logic.dart';

class ImportJob {
  const ImportJob({
    required this.id,
    required this.status,
    required this.total,
    required this.processed,
    required this.imported,
    required this.skipped,
    this.error,
  });
  final String id;
  final String status; // uploading | queued | processing | done | failed | cancelled
  final int total;
  final int processed;
  final int imported;
  final int skipped;
  final String? error;

  double get progress => total <= 0 ? 0 : (processed / total).clamp(0.0, 1.0);
  bool get finished => status == 'done' || status == 'failed' || status == 'cancelled';

  factory ImportJob.fromJson(Map<String, dynamic> j) => ImportJob(
        id: j['id'] as String,
        status: (j['status'] ?? 'uploading') as String,
        total: (j['total'] as num?)?.toInt() ?? 0,
        processed: (j['processed'] as num?)?.toInt() ?? 0,
        imported: (j['imported'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
      );
}

class ImportService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const chunkSize = 500;
  static const _cols = 'id, status, total, processed, imported, skipped, error';

  static Future<String> createJob(String orgId, String fileName) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw AppException('Sesión caducada. Vuelve a entrar.');
    final r = await _db
        .from('import_jobs')
        .insert({'org_id': orgId, 'user_id': uid, 'file_name': fileName.length > 200 ? fileName.substring(0, 200) : fileName})
        .select('id')
        .single();
    return r['id'] as String;
  }

  /// Sube en bloques de 500 filas, con reintentos. [onProgress] recibe las filas ya subidas.
  static Future<void> upload(String jobId, List<ImportRow> rows, {required void Function(int sent) onProgress, bool Function()? cancelled}) async {
    for (var i = 0; i < rows.length; i += chunkSize) {
      if (cancelled?.call() ?? false) return;
      final end = (i + chunkSize) > rows.length ? rows.length : i + chunkSize;
      final payload = rows.sublist(i, end).map((r) => r.toJson()).toList();
      for (var attempt = 0;; attempt++) {
        try {
          await _db.rpc('import_add_rows', params: {'p_job': jobId, 'p_rows': payload});
          break;
        } catch (_) {
          if (attempt >= 3) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
      onProgress(end);
    }
  }

  static Future<void> start(String jobId, double taxRate) => _db.rpc('import_start', params: {'p_job': jobId, 'p_tax_rate': taxRate});

  /// Avanza un lote mientras la app está abierta (el worker de la base lo hace igual si se cierra).
  static Future<void> step(String jobId) => _db.rpc('import_step', params: {'p_job': jobId, 'p_batch': chunkSize});

  static Future<ImportJob?> fetch(String id) async {
    final r = await _db.from('import_jobs').select(_cols).eq('id', id).maybeSingle();
    return r == null ? null : ImportJob.fromJson(Map<String, dynamic>.from(r));
  }

  /// Importación en curso de esta empresa (para retomar la vista si se cerró la pantalla).
  static Future<ImportJob?> activeJob(String orgId) async {
    final r = await _db
        .from('import_jobs')
        .select(_cols)
        .eq('org_id', orgId)
        .inFilter('status', ['queued', 'processing'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return r == null ? null : ImportJob.fromJson(Map<String, dynamic>.from(r));
  }

  static Future<void> cancel(String id) => _db.rpc('import_cancel', params: {'p_job': id});

  /// Cambios en vivo del trabajo (Realtime). Si Realtime no está disponible, la pantalla también consulta cada pocos segundos.
  static Stream<ImportJob> watch(String id) => _db
      .from('import_jobs')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => ImportJob.fromJson(Map<String, dynamic>.from(rows.first)));
}
