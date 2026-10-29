import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'access.dart';
import 'errors.dart';
import 'models.dart';
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

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      themeMode.value = _parseTheme(meta?['theme']);
      final rm = meta?['reduced_motion'];
      MotionPrefs.userReduced.value = rm is bool ? rm : null;
      // v2.0: si el dueño invitó este correo, se une a su empresa ANTES de listar empresas.
      try {
        await V2Repo.claimInvites();
      } catch (_) {}
      await _loadOrgs();
      profile = await Repo.loadProfile();
      await Access.instance.load();
    } catch (e) {
      error = friendly(e);
    }
    loading = false;
    notifyListeners();
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
    Repo.activeOrgId = o.id;
    V2Repo.forgetSettings();
    notifyListeners(); // el nombre de la empresa cambia al instante en toda la app
    try {
      profile = await Repo.loadProfile();
    } catch (_) {}
    await Access.instance.load();
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
    profile = null;
    orgs = const [];
    Repo.activeOrgId = null;
    V2Repo.forgetSettings();
    Access.instance.clear();
    themeMode.value = ThemeMode.system;
    error = null;
    loading = false;
    notifyListeners();
  }
}
