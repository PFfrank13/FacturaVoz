// Idempotencia de extremo a extremo para cobros, abonos de fiado y movimientos de caja (orden de producción §8).
//
// Un INTENTO lógico (p. ej. "cobrar S/ 40 de la factura X") recibe un id UNA vez y se guarda en el teléfono ANTES de
// enviarse. Ese id es la clave primaria de la fila en la base, así que:
//   * reintento automático, respuesta perdida, cierre de la app o reintento manual → mismo id → la base rechaza el
//     duplicado (23505) y se toma como "ya registrado";
//   * mientras un intento esté en estado DESCONOCIDO para un mismo objetivo (misma factura, mismo cliente, misma caja),
//     no se crea otro: primero se comprueba en el servidor si el anterior existe.
// Estados visibles: pendiente de confirmar · confirmado · rechazado · desconocido (comprobar antes de repetir).
import 'dart:convert';

import '../errors.dart';

enum IntentState { pending, confirmed, rejected, unknown }

class FinancialIntent {
  FinancialIntent({
    required this.id,
    required this.orgId,
    required this.userId,
    required this.table,
    required this.target,
    required this.row,
    required this.createdAt,
    this.state = IntentState.pending,
  });

  final String id;
  final String orgId;
  final String userId;
  final String table; // payments | credit_ledger | cash_movements
  /// Objetivo lógico: no puede haber dos intentos sin resolver para el mismo objetivo.
  final String target;
  final Map<String, dynamic> row;
  final DateTime createdAt;
  IntentState state;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'org': orgId,
        'user': userId,
        'table': table,
        'target': target,
        'row': row,
        'at': createdAt.toUtc().toIso8601String(),
        'state': state.name,
      };

  factory FinancialIntent.fromJson(Map<String, dynamic> j) => FinancialIntent(
        id: j['id'] as String,
        orgId: j['org'] as String,
        userId: j['user'] as String,
        table: j['table'] as String,
        target: j['target'] as String,
        row: Map<String, dynamic>.from(j['row'] as Map),
        createdAt: DateTime.parse(j['at'] as String),
        state: IntentState.values.firstWhere((s) => s.name == j['state'], orElse: () => IntentState.unknown),
      );
}

/// Almacenamiento clave → texto (en la app: FlutterSecureStorage; en pruebas: memoria).
abstract class IntentStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryIntentStorage implements IntentStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Resultado para la pantalla.
enum IntentOutcome {
  /// Se registró ahora.
  confirmed,

  /// Había un intento anterior sin confirmar para el mismo objetivo y SÍ estaba registrado: no se creó otro.
  previousConfirmed,
}

/// Estado desconocido (sin conexión): NO repetir; se comprueba con el mismo id al volver la conexión.
class IntentUnknown extends AppException {
  IntentUnknown(this.intent)
      : super('Sin conexión: no sabemos si la operación se registró. Queda PENDIENTE DE CONFIRMAR y se comprobará con el mismo registro al volver la conexión; no la vuelvas a crear.');
  final FinancialIntent intent;
}

/// Lógica pura y probada. [send] inserta la fila con su id; [exists] comprueba en el servidor si el id existe.
class FinancialIntents {
  FinancialIntents(this.storage);
  final IntentStorage storage;

  static String _key(String userId, String orgId) => 'fv_fin_intents_v1_${userId}_$orgId';

  Future<List<FinancialIntent>> list(String userId, String orgId) async {
    final raw = await storage.read(_key(userId, orgId));
    if (raw == null) return [];
    return [
      for (final m in (jsonDecode(raw) as List))
        if (FinancialIntent.fromJson(Map<String, dynamic>.from(m as Map)) case final i when i.orgId == orgId && i.userId == userId) i,
    ];
  }

  Future<void> _save(String userId, String orgId, List<FinancialIntent> all) async {
    if (all.isEmpty) {
      await storage.delete(_key(userId, orgId));
    } else {
      await storage.write(_key(userId, orgId), jsonEncode([for (final i in all) i.toJson()]));
    }
  }

  Future<void> _put(FinancialIntent i) async {
    final all = await list(i.userId, i.orgId)..removeWhere((x) => x.id == i.id);
    await _save(i.userId, i.orgId, [...all, i]);
  }

  Future<void> _drop(FinancialIntent i) async {
    final all = await list(i.userId, i.orgId)..removeWhere((x) => x.id == i.id);
    await _save(i.userId, i.orgId, all);
  }

  /// Registra una operación financiera exactamente una vez.
  Future<IntentOutcome> record({
    required String orgId,
    required String userId,
    required String table,
    required String target,
    required Map<String, dynamic> row,
    required String Function() newId,
    required Future<void> Function(String table, Map<String, dynamic> row) send,
    required Future<bool> Function(String table, String id) exists,
    required bool Function(Object error) isDuplicate,
    required bool Function(Object error) isTransient,
  }) async {
    // 1) ¿Hay un intento previo sin resolver para el mismo objetivo? Se resuelve ANTES de crear otro.
    for (final prev in (await list(userId, orgId)).where((i) => i.table == table && i.target == target)) {
      final ok = await resolve(prev, send: send, exists: exists, isDuplicate: isDuplicate, isTransient: isTransient);
      if (ok) return IntentOutcome.previousConfirmed;
    }
    // 2) Nuevo intento: se guarda con su id ANTES de enviarlo.
    final id = newId();
    final intent = FinancialIntent(id: id, orgId: orgId, userId: userId, table: table, target: target, row: {...row, 'id': id}, createdAt: DateTime.now());
    await _put(intent);
    await _attempt(intent, send: send, isDuplicate: isDuplicate, isTransient: isTransient);
    return IntentOutcome.confirmed;
  }

  /// Comprueba un intento previo: si existe en el servidor → confirmado; si no → lo envía con el MISMO id.
  /// Devuelve true si quedó confirmado; lanza [IntentUnknown] si sigue sin conexión.
  Future<bool> resolve(
    FinancialIntent prev, {
    required Future<void> Function(String table, Map<String, dynamic> row) send,
    required Future<bool> Function(String table, String id) exists,
    required bool Function(Object error) isDuplicate,
    required bool Function(Object error) isTransient,
  }) async {
    bool found;
    try {
      found = await exists(prev.table, prev.id);
    } catch (e) {
      if (isTransient(e)) {
        prev.state = IntentState.unknown;
        await _put(prev);
        throw IntentUnknown(prev);
      }
      rethrow;
    }
    if (found) {
      await _drop(prev);
      return true;
    }
    await _attempt(prev, send: send, isDuplicate: isDuplicate, isTransient: isTransient);
    return true;
  }

  Future<void> _attempt(
    FinancialIntent i, {
    required Future<void> Function(String table, Map<String, dynamic> row) send,
    required bool Function(Object error) isDuplicate,
    required bool Function(Object error) isTransient,
  }) async {
    try {
      await send(i.table, i.row);
      await _drop(i); // confirmado
    } catch (e) {
      if (isDuplicate(e)) {
        await _drop(i); // ya estaba registrado con este id
        return;
      }
      if (isTransient(e)) {
        i.state = IntentState.unknown;
        await _put(i);
        throw IntentUnknown(i);
      }
      await _drop(i); // rechazado por la base (permiso, licencia, validación): definitivo
      rethrow;
    }
  }
}
