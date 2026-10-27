import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'errors.dart';
import 'models.dart';
import 'services/repo.dart';

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
      themeMode.value = _parseTheme(Supabase.instance.client.auth.currentUser?.userMetadata?['theme']);
      await _loadOrgs();
      profile = await Repo.loadProfile();
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
    notifyListeners(); // el nombre de la empresa cambia al instante en toda la app
    try {
      profile = await Repo.loadProfile();
    } catch (_) {}
    notifyListeners();
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'active_org': o.id}));
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
    themeMode.value = ThemeMode.system;
    error = null;
    loading = false;
    notifyListeners();
  }
}
