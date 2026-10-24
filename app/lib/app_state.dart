import 'package:flutter/foundation.dart';

import 'errors.dart';
import 'models.dart';
import 'services/repo.dart';

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  Profile? profile;
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      profile = await Repo.loadProfile();
    } catch (e) {
      error = friendly(e);
    }
    loading = false;
    notifyListeners();
  }

  void setProfile(Profile p) {
    profile = p;
    notifyListeners();
  }

  void clear() {
    profile = null;
    error = null;
    loading = false;
    notifyListeners();
  }
}
