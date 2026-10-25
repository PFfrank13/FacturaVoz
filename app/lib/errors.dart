import 'package:supabase_flutter/supabase_flutter.dart';

class AppException implements Exception {
  AppException(this.message, {this.code});
  final String message;

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
