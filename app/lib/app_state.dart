import 'package:flutter/foundation.dart';
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

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
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
    error = null;
    loading = false;
    notifyListeners();
  }
}
