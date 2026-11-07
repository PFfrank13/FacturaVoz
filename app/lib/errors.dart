import 'package:supabase_flutter/supabase_flutter.dart';

/// Only emitted after the checkout RPC reports its explicit rollback contract.
class CheckoutRejected extends AppException {
  CheckoutRejected() : super('El servidor rechazó el ticket sin registrar la venta. Revisa precios, cantidades e impuesto antes de cobrar.', code: 'P2001');
}

class AppException implements Exception {
  AppException(this.message, {this.code, this.transcript});
  final String message;

  /// Lo que se alcanzó a oír, si la transcripción funcionó pero la interpretación falló.
  final String? transcript;

  /// Código corto y SEGURO para soporte (nunca contiene secretos).
  final String? code;
  @override
  String toString() => message;
}

/// Mensaje para el usuario. Explica la causa probable y deja un código corto para soporte;
/// nunca incluye claves, tokens ni respuestas completas del servidor.
String friendly(Object e) {
  if (e is AppException) return e.code == null ? e.message : '${e.message} (${e.code})';
  if (e is PostgrestException) {
    final c = e.code ?? '';
    if (c == '42P01' || c == 'PGRST205' || c == 'PGRST200') {
      return 'Falta preparar la base de datos: ejecuta las migraciones SQL en Supabase. ($c)';
    }
    if (c == '42703' || c == 'PGRST204') {
      return 'La base de datos está desactualizada: ejecuta las migraciones SQL en Supabase. ($c)';
    }
    if (c == '23505') return 'Ya existe un elemento con ese nombre. ($c)';
    if (c == '23514') return 'Hay un dato fuera de rango (por ejemplo, un precio negativo). ($c)';
    if (c == '42501') return 'Sin permiso para esta operación. Vuelve a iniciar sesión. ($c)';
    if (c == 'PGRST301' || c == 'PGRST303') return 'Sesión caducada. Vuelve a entrar. ($c)';
    return 'La base de datos respondió con un error. (${c.isEmpty ? 'db' : c})';
  }
  if (e is AuthException) return 'Sesión no válida. Vuelve a entrar.';
  final t = e.runtimeType.toString();
  if (t.contains('Socket') || t.contains('Client') || t.contains('Timeout') || t.contains('Handshake')) {
    return 'Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo.';
  }
  return 'Ocurrió un error inesperado. ($t)';
}
