import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'access.dart';
import 'logic/data_scope.dart';
import 'errors.dart';
import 'models.dart';
import 'services/boot_cache.dart';
import 'services/app_lock.dart' show appNavigatorKey;
import 'services/live.dart';
import 'services/repo.dart';
import 'services/v2_repo.dart';
import 'ui/motion.dart' show MotionPrefs;

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  Profile? profile;
  List<Org> orgs = const [];
  Org? get activeOrg => orgs.isEmpty ? null : orgs.firstWhere((o) => o.id == Repo.activeOrgId, orElse: () => orgs.first);
  bool loading = false;
  String? error;

  /// Se incrementa cuando cambian datos que varias pantallas muestran (facturas, cobros, gastos…).
  final ValueNotifier<int> dataVersion = ValueNotifier(0);
  void bump() => dataVersion.value++;

  /// Apariencia elegida (se recuerda en la cuenta). Escucha este notifier para cambiar el tema al instante.
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  /// Modo Fácil (E): letras más grandes y menos cosas en pantalla. Preferencia de la persona (se recuerda en su cuenta).
  final ValueNotifier<bool> easyMode = ValueNotifier(false);

  Future<void> setEasyMode(bool v) async {
    easyMode.value = v;
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'easy_mode': v}));
    } catch (_) {}
  }

  static ThemeMode _parseTheme(Object? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setTheme(ThemeMode m) async {
    themeMode.value = m;
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'theme': m.name}));
    } catch (_) {}
  }

  /// Arranque instantáneo: abre con lo último guardado (cifrado) de esta cuenta y confirma con la red por detrás.
  bool _hydrate(Map<String, dynamic> snap) {
    try {
      final o = (snap['orgs'] as List).map((e) => Org.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final p = Profile.fromJson(Map<String, dynamic>.from(snap['profile'] as Map));
      if (o.isEmpty || !p.isComplete) return false;
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata?['active_org'];
      final saved = snap['active'] as String?;
      final pick = o.where((x) => x.id == meta).firstOrNull ?? o.where((x) => x.id == saved).firstOrNull ?? o.first;
      if (pick.id != saved || snap['access'] is! Map) return false; // otra empresa: no se adivinan permisos
      orgs = o;
      Repo.activeOrgId = pick.id;
      profile = p;
      Access.instance.applyCached((snap['access'] as Map).cast<String, dynamic>(), (snap['license'] as Map?)?.cast<String, dynamic>());
      final sr = snap['settings'];
      if (sr is Map && snap['settings_org'] == pick.id) V2Repo.seedSettings(pick.id, Map<String, dynamic>.from(sr));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _saveBoot() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final p = profile;
    if (uid == null || p == null || orgs.isEmpty || !p.isComplete) return;
    BootCache.putCore(uid,
        orgs: [for (final o in orgs) o.toJson()], active: Repo.activeOrgId, profile: p.toJson(), access: Access.instance.rawAccess, license: Access.instance.rawLicense);
  }

  Future<void> load() async {
    final snap = profile == null ? BootCache.forUser(Supabase.instance.client.auth.currentUser?.id) : null;
    final fast = snap != null && _hydrate(snap);
    loading = !fast; // con datos guardados no hay pantalla de carga: se entra directo
    error = null;
    notifyListeners();
    try {
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      themeMode.value = _parseTheme(meta?['theme']);
      easyMode.value = meta?['easy_mode'] == true;
      final rm = meta?['reduced_motion'];
      MotionPrefs.userReduced.value = rm is bool ? rm : null;
      // v2.0: si el dueño invitó este correo, se une a su empresa. Se pide a la vez que la lista de empresas;
      // solo si de verdad se unió a alguna se vuelve a listar (lo normal es 0 invitaciones: una espera menos).
      final claim = V2Repo.claimInvites(); // nunca lanza: devuelve 0 si falla
      await _loadOrgs();
      if (await claim > 0) await _loadOrgs();
      // Perfil de la empresa y permisos/licencia no dependen entre sí.
      final res = await Future.wait<Object?>([Repo.loadProfile(), Access.instance.load()]);
      profile = res[0] as Profile;
      _saveBoot();
    } catch (e) {
      if (!fast) error = friendly(e); // si ya se abrió con lo guardado, un fallo de red no molesta
    }
    loading = false;
    notifyListeners();
    LiveHub.instance.start(); // tiempo real de la empresa activa
    if (error == null) unawaited(LiveCache.warmUp()); // clientes, productos y fiados listos antes de que los abras
  }

  Future<void> _loadOrgs() async {
    orgs = await Repo.listOrgs();
    final saved = Supabase.instance.client.auth.currentUser?.userMetadata?['active_org'];
    final pick = orgs.where((o) => o.id == saved).firstOrNull ?? orgs.firstOrNull;
    Repo.activeOrgId = pick?.id;
  }

  Future<void> refreshOrgs() async {
    await _loadOrgs();
    notifyListeners();
  }

  /// Cambia de empresa y lo recuerda en la cuenta (user_metadata).
  Future<void> switchOrg(Org o) async {
    // §9: ninguna pantalla de la empresa anterior queda abierta (sus respuestas tardías se descartan porque el
    // widget ya no está montado) y el Inicio se reconstruye con la clave de la nueva empresa (main.dart).
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    dataScope.value++;
    Access.instance.invalidateLicenseCheck();
    Repo.activeOrgId = o.id;
    V2Repo.forgetSettings();
    LiveCache.clear();
    LiveHub.instance.start(); // cambia de empresa: deja de escuchar la anterior
    notifyListeners(); // el nombre de la empresa cambia al instante en toda la app
    try {
      profile = await Repo.loadProfile();
    } catch (_) {}
    await Access.instance.load();
    _saveBoot();
    notifyListeners();
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'active_org': o.id}));
    } catch (_) {}
  }

  /// Animaciones: null = automático, true = reducidas, false = completas. Se recuerda en la cuenta.
  Future<void> setReducedMotion(bool? v) async {
    MotionPrefs.userReduced.value = v;
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'reduced_motion': v}));
    } catch (_) {}
  }

  void setProfile(Profile p) {
    profile = p;
    notifyListeners();
  }

  void clear() {
    dataScope.value++;
    BootCache.wipe();
    LiveHub.instance.stop();
    LiveCache.clear();
    profile = null;
    orgs = const [];
    Repo.activeOrgId = null;
    V2Repo.forgetSettings();
    Access.instance.clear();
    themeMode.value = ThemeMode.system;
    easyMode.value = false;
    error = null;
    loading = false;
    notifyListeners();
  }
}
