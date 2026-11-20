import 'package:flutter/foundation.dart';

/// Configuración por --dart-define. Nada de esto es secreto:
/// la clave "anon" de Supabase es pública por diseño (la protege RLS).
/// NUNCA pongas aquí la service_role ni la clave de Groq.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');
  static const termsUrl = String.fromEnvironment('TERMS_URL');

  /// WhatsApp de soporte (9 dígitos o con 51). Vacío = el botón de ayuda abre el correo de soporte.
  static const supportWhatsapp = String.fromEnvironment('SUPPORT_WHATSAPP');
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '3.4.0');

  /// Muestra "Continuar con Google" (requiere activar el proveedor en Supabase). --dart-define=GOOGLE_LOGIN=true
  static const googleLogin = bool.fromEnvironment('GOOGLE_LOGIN');

  /// Esquema de retorno del inicio de sesión con navegador (debe coincidir con el manifest y con Supabase).
  static const authRedirect = 'dev.solvexsoftware.facturavoz://login-callback';

  static bool _secure(String u) =>
      u.startsWith('https://') ||
      (kDebugMode && (u.startsWith('http://localhost') || u.startsWith('http://10.0.2.2')));

  /// Accept only a public Supabase key, not a full Flutter run command.
  /// Format validation cannot replace Supabase's server-side authentication.
  static bool isPublicKeyFormat(String value) {
    final key = value.trim();
    if (key != value || key.contains(RegExp(r'\s'))) return false;
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]{10,}$').hasMatch(key)) return true;
    return RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(key);
  }

  static bool get isValid =>
      _secure(supabaseUrl) && isPublicKeyFormat(supabaseAnonKey) && _secure(apiBaseUrl);

  static String get apiBase =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
}
