// Prevención de doble registro (Prompt Maestro §13) para inserciones simples (cobros, abonos de fiado, movimientos
// de caja). El id de la fila se genera UNA vez en el teléfono; si la red falla, se reintenta con el MISMO id.
// Si el primer intento sí llegó a la base, el reintento choca con la clave primaria (23505) y se toma como hecho:
// el cobro queda registrado exactamente una vez. Ventas y compras ya usan RPC idempotentes (request_id).

/// Ejecuta [op] hasta [attempts] veces. [isDuplicate]: el registro ya existe (reintento de algo que sí se guardó).
/// [isTransient]: error de red/tiempo que vale la pena reintentar. Cualquier otro error se propaga de inmediato.
Future<void> runIdempotent(
  Future<void> Function() op, {
  required bool Function(Object error) isDuplicate,
  required bool Function(Object error) isTransient,
  int attempts = 2,
  Duration wait = const Duration(milliseconds: 700),
}) async {
  for (var i = 0;; i++) {
    try {
      await op();
      return;
    } catch (e) {
      if (i > 0 && isDuplicate(e)) return; // el intento anterior sí se guardó
      if (!isTransient(e) || i + 1 >= attempts) rethrow;
      await Future<void>.delayed(wait);
    }
  }
}
