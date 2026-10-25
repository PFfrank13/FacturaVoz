import 'package:flutter/foundation.dart';

/// Configuración por --dart-define. Nada de esto es secreto:
/// la clave "anon" de Supabase es pública por diseño (la protege RLS).
/// NUNCA pongas aquí la service_role ni la clave de Groq.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');

  /// Muestra "Continuar con Google" (requiere activar el proveedor en Supabase). --dart-define=GOOGLE_LOGIN=true
  static const googleLogin = bool.fromEnvironment('GOOGLE_LOGIN');

  /// Esquema de retorno del inicio de sesión con navegador (debe coincidir con el manifest y con Supabase).
  static const authRedirect = 'com.facturavoz.app://login-callback';

  static bool _secure(String u) =>
      u.startsWith('https://') ||
      (kDebugMode && (u.startsWith('http://localhost') || u.startsWith('http://10.0.2.2')));

  static bool get isValid =>
      _secure(supabaseUrl) && supabaseAnonKey.isNotEmpty && _secure(apiBaseUrl);

  static String get apiBase =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
}
