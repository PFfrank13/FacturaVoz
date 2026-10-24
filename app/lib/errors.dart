class AppException implements Exception {
  AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Mensaje seguro para mostrar al usuario (sin detalles internos).
String friendly(Object e) {
  if (e is AppException) return e.message;
  return 'Ocurrió un error. Revisa tu conexión e inténtalo de nuevo.';
}
