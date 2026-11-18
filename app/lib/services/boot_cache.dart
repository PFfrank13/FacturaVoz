// Arranque instantáneo: guarda, CIFRADO (llavero de Android / Keychain de iOS), lo mínimo para abrir la app sin esperar
// a la red: empresas, perfil de la empresa activa, rol/permisos, licencia y configuración del negocio.
// NO guarda clientes, facturas, montos ni productos. Se borra al cerrar sesión y si entra otra cuenta.
// En web no se usa (el navegador no ofrece un almacén seguro equivalente).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BootCache {
  BootCache._();

  static const _key = 'fv_boot_v1';
  static const _version = 1;
  static const _store = FlutterSecureStorage(aOptions: AndroidOptions());

  static Map<String, dynamic>? _data;

  /// Lee el archivo cifrado a memoria (se llama en paralelo con el inicio de Supabase).
  static Future<void> preload() async {
    if (kIsWeb) return;
    try {
      final s = await _store.read(key: _key);
      if (s == null) return;
      final m = jsonDecode(s);
      if (m is Map && m['v'] == _version) _data = Map<String, dynamic>.from(m);
    } catch (_) {
      _data = null;
    }
  }

  /// Lo guardado para ESTA cuenta; si es de otra, se borra.
  static Map<String, dynamic>? forUser(String? uid) {
    final d = _data;
    if (d == null || uid == null) return null;
    if (d['uid'] != uid) {
      wipe();
      return null;
    }
    return d;
  }

  static void putCore(String uid, {required List<Map<String, dynamic>> orgs, required String? active, required Map<String, dynamic> profile, Map<String, dynamic>? access, Map<String, dynamic>? license}) {
    final old = _data != null && _data!['uid'] == uid ? _data! : const <String, dynamic>{};
    _data = {
      'v': _version,
      'uid': uid,
      'orgs': orgs,
      'active': active,
      'profile': profile,
      'access': access,
      'license': license,
      // la configuración solo vale para la misma empresa
      if (old['settings_org'] == active) ...{'settings': old['settings'], 'settings_org': old['settings_org']},
    };
    _persist();
  }

  static void putSettings(String org, Map<String, dynamic> raw) {
    final d = _data;
    if (d == null || d['active'] != org) return;
    d['settings'] = raw;
    d['settings_org'] = org;
    _persist();
  }

  static Future<void> wipe() async {
    _data = null;
    if (kIsWeb) return;
    try {
      await _store.delete(key: _key);
    } catch (_) {}
  }

  static void _persist() {
    if (kIsWeb || _data == null) return;
    try {
      // Sin esperar (no frena la app) y sin dejar errores sueltos si el almacén seguro no está disponible.
      unawaited(_store.write(key: _key, value: jsonEncode(_data)).catchError((_) {}));
    } catch (_) {}
  }
}
