// Bloqueo de la app: PIN (siempre) + huella/rostro (si el equipo lo tiene). Se pide en cada inicio
// y al volver tras un rato en segundo plano. El PIN nunca se guarda en claro: PBKDF2-HMAC-SHA256 con sal
// aleatoria dentro del almacén seguro del sistema (Keystore / Keychain).
// v4.0: el PIN es de la CUENTA. El servidor guarda su bcrypt (app_pin_*): en un celular nuevo hay que escribir el PIN
// de siempre (no se puede crear otro), cambiarlo exige el actual y, si se olvidó, solo se crea otro tras entrar con
// el código del correo. Cada celular guarda una copia cifrada para abrir sin internet.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../errors.dart';
import '../pin_logic.dart';

/// Llave del Navigator: permite volver a la raíz al cerrar sesión desde la pantalla de bloqueo.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

enum LockStatus { off, checking, noPin, locked, unlocked }

class PinCheck {
  const PinCheck({required this.ok, this.failsLeft = 0, this.waitSeconds = 0, this.signedOut = false, this.offline = false});
  final bool ok;
  final int failsLeft;
  final int waitSeconds;
  final bool signedOut;

  /// No se pudo consultar el PIN de la cuenta (celular nuevo sin internet).
  final bool offline;
}

class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();
  static final AppLock instance = AppLock._();

  /// Tiempo en segundo plano a partir del cual se vuelve a pedir el PIN.
  static const background = Duration(seconds: 20);

  final _store = const FlutterSecureStorage(aOptions: AndroidOptions());
  final _auth = LocalAuthentication();

  LockStatus status = LockStatus.off;
  bool biometricOn = false;
  bool biometricAvailable = false;
  bool setupAllowed = false;

  /// La cuenta ya tiene PIN en el servidor (un celular nuevo debe escribirlo, no crear otro).
  bool serverHasPin = false;

  /// Entró con el código del correo hace poco: puede crear un PIN nuevo si olvidó el suyo.
  bool canReset = false;

  /// Creando un PIN nuevo tras «Olvidé mi PIN» (con el código del correo).
  bool resetMode = false;

  bool _needsUpload = false;
  DateTime? _serverUntil;
  String? _uid;
  DateTime? _leftAt;
  bool _askingBiometric = false;
  bool _bound = false;

  /// La pantalla de bloqueo solo se dibuja cuando corresponde.
  bool get showOverlay => status == LockStatus.checking || status == LockStatus.locked ||
      (status == LockStatus.noPin && (setupAllowed || resetMode));

  SupabaseClient get _db => Supabase.instance.client;

  Future<Map<String, dynamic>?> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      final r = await _db.rpc(fn, params: params).timeout(const Duration(seconds: 10));
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null; // sin internet o migración pendiente: se usa la copia del celular
    }
  }

  String _k(String name) => '${name}_$_uid';

  Future<String?> _read(String key) async {
    try {
      return await _store.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String? value) async {
    try {
      if (value == null) {
        await _store.delete(key: key);
      } else {
        await _store.write(key: key, value: value);
      }
    } catch (_) {}
  }

  /// Engancha el bloqueo a la sesión de Supabase. Llamar una vez antes de runApp.
  void bind() {
    if (_bound || kIsWeb) return; // En web no hay almacén seguro: no se bloquea.
    _bound = true;
    WidgetsBinding.instance.addObserver(this);
    final auth = Supabase.instance.client.auth;
    final u = auth.currentSession?.user.id;
    if (u != null) _activate(u, fresh: false);
    auth.onAuthStateChange.listen((s) {
      final user = s.session?.user.id;
      if (user == null) {
        if (s.event == AuthChangeEvent.signedOut) deactivate();
      } else if (user != _uid) {
        _activate(user, fresh: true); // inicio de sesión nuevo: no se pide el PIN recién puesto
      }
    });
  }

  Future<void> _activate(String uid, {required bool fresh}) async {
    _uid = uid;
    status = LockStatus.checking;
    resetMode = false;
    notifyListeners();
    var enc = await _read(_k('pin'));
    final st = await _rpc('app_pin_status');
    if (_uid != uid) return;
    serverHasPin = st?['has_pin'] == true;
    canReset = st?['can_reset'] == true;
    _needsUpload = false;
    if (st != null) {
      if (serverHasPin) {
        // El PIN de la cuenta cambió en otro celular (o este nunca lo confirmó): manda el del servidor.
        if (enc != null && await _read(_k('pinv')) != st['version']) {
          await _write(_k('pin'), null);
          enc = null;
        }
        final wait = (st['wait'] as num?)?.toInt() ?? 0;
        _serverUntil = wait > 0 ? DateTime.now().add(Duration(seconds: wait)) : null;
      } else if (enc != null) {
        _needsUpload = true; // PIN creado antes de v4.0: se sube a la cuenta al próximo desbloqueo
      }
    }
    biometricAvailable = await _canBio();
    // Sin copia local del PIN (celular nuevo) la huella NO abre: primero el PIN de la cuenta.
    biometricOn = enc != null && biometricAvailable && (await _read(_k('bio'))) != '0';
    if (_uid != uid) return;
    if (enc != null) {
      status = fresh ? LockStatus.unlocked : LockStatus.locked;
    } else if (serverHasPin) {
      status = LockStatus.locked; // celular nuevo: escribe el PIN de tu cuenta
    } else {
      status = LockStatus.noPin;
    }
    notifyListeners();
  }

  /// «Olvidé mi PIN» tras entrar con el código del correo: pasa a crear uno nuevo.
  void startReset() {
    if (!canReset) return;
    resetMode = true;
    status = LockStatus.noPin;
    notifyListeners();
  }

  /// Cierra sesión local: borra PIN y contadores de este usuario.
  Future<void> deactivate() async {
    final uid = _uid;
    if (uid != null) {
      for (final k in ['pin', 'pinv', 'bio', 'fails', 'until']) {
        await _write('${k}_$uid', null);
      }
    }
    _uid = null;
    status = LockStatus.off;
    setupAllowed = false;
    serverHasPin = false;
    canReset = false;
    resetMode = false;
    _needsUpload = false;
    _serverUntil = null;
    notifyListeners();
  }

  /// El perfil ya está completo: a partir de aquí se puede pedir crear el PIN.
  void allowSetup() {
    if (setupAllowed) return;
    setupAllowed = true;
    notifyListeners();
  }

  Future<bool> _canBio() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPin() async => _uid != null && await _read(_k('pin')) != null;

  Future<void> _storeLocal(String pin, String? version) async {
    await _write(_k('pin'), encodePin(pin));
    await _write(_k('pinv'), version);
    await _write(_k('fails'), '0');
    await _write(_k('until'), null);
  }

  /// Crea el PIN de la cuenta (primera vez, o uno nuevo tras entrar con el código del correo).
  /// No cambia el estado: lo hace [completeSetup] cuando termina la animación.
  Future<void> setPin(String pin) async {
    if (_uid == null) return;
    final r = await _rpc('app_pin_set', {'p_new': pin, 'p_current': null});
    if (r == null) {
      // Sin internet: solo se permite la primera vez (la cuenta aún no tiene PIN). Se sube al volver la señal.
      if (resetMode || serverHasPin) throw AppException('Necesitas internet para crear tu PIN nuevo.');
      await _storeLocal(pin, null);
      _needsUpload = true;
      return;
    }
    if (r['ok'] != true) throw AppException((r['error'] ?? 'No se pudo guardar el PIN.') as String);
    await _storeLocal(pin, r['version'] as String?);
    serverHasPin = true;
    _needsUpload = false;
    resetMode = false;
  }

  /// Cambia el PIN de la cuenta: exige el actual (lo comprueba el servidor). Necesita internet.
  Future<void> changePin(String current, String next) async {
    if (_uid == null) return;
    final r = await _rpc('app_pin_set', {'p_new': next, 'p_current': current});
    if (r == null) throw AppException('Necesitas internet para cambiar tu PIN (así el cambio vale en todos tus celulares).');
    if (r['ok'] != true) throw AppException((r['error'] ?? 'No se pudo cambiar el PIN.') as String);
    await _storeLocal(next, r['version'] as String?);
    serverHasPin = true;
    _needsUpload = false;
  }

  void _upload(String pin) {
    if (!_needsUpload) return;
    _rpc('app_pin_set', {'p_new': pin, 'p_current': null}).then((r) async {
      if (r != null && r['ok'] == true) {
        _needsUpload = false;
        serverHasPin = true;
        await _write(_k('pinv'), r['version'] as String?);
      }
    });
  }

  /// Termina la configuración inicial: activa la huella (si el equipo la tiene) y desbloquea.
  Future<void> completeSetup() async {
    biometricAvailable = await _canBio();
    if (biometricAvailable) {
      final ok = await authenticateBiometric(reason: 'Confirma tu huella para entrar más rápido');
      biometricOn = ok;
      await _write(_k('bio'), ok ? '1' : '0');
    }
    unlockNow();
  }

  void unlockNow() {
    status = LockStatus.unlocked;
    notifyListeners();
  }

  Future<int> waitSeconds() async {
    final until = int.tryParse(await _read(_k('until')) ?? '') ?? 0;
    final left = ((until - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    final server = _serverUntil == null ? 0 : _serverUntil!.difference(DateTime.now()).inSeconds;
    final w = left > server ? left : server;
    return w > 0 ? w : 0;
  }

  /// Celular sin copia del PIN: lo comprueba el servidor (con su propio límite de intentos).
  Future<PinCheck> _verifyServer(String pin, bool unlock) async {
    final r = await _rpc('app_pin_verify', {'p_pin': pin});
    if (r == null) return const PinCheck(ok: false, offline: true);
    if (r['ok'] == true) {
      await _storeLocal(pin, r['version'] as String?);
      _serverUntil = null;
      biometricOn = biometricAvailable && (await _read(_k('bio'))) != '0';
      if (unlock) unlockNow();
      return const PinCheck(ok: true);
    }
    if (r['signed_out'] == true) {
      await _forceSignOut();
      return const PinCheck(ok: false, signedOut: true);
    }
    final wait = (r['wait'] as num?)?.toInt() ?? 0;
    _serverUntil = wait > 0 ? DateTime.now().add(Duration(seconds: wait)) : null;
    return PinCheck(ok: false, failsLeft: (r['fails_left'] as num?)?.toInt() ?? 0, waitSeconds: wait);
  }

  /// Comprueba el PIN con límite de intentos y espera creciente. `unlock` desbloquea la app si es correcto.
  Future<PinCheck> verifyPin(String pin, {bool unlock = true}) async {
    final wait = await waitSeconds();
    if (wait > 0) return PinCheck(ok: false, waitSeconds: wait);
    final enc = await _read(_k('pin'));
    if (enc == null) return _verifyServer(pin, unlock);
    if (verifyEncodedPin(pin, enc)) {
      await _write(_k('fails'), '0');
      await _write(_k('until'), null);
      _upload(pin);
      if (unlock) unlockNow();
      return const PinCheck(ok: true);
    }
    final fails = (int.tryParse(await _read(_k('fails')) ?? '') ?? 0) + 1;
    await _write(_k('fails'), '$fails');
    if (fails >= maxPinFails) {
      await _forceSignOut();
      return const PinCheck(ok: false, signedOut: true);
    }
    final w = lockoutSeconds(fails);
    if (w > 0) await _write(_k('until'), '${DateTime.now().millisecondsSinceEpoch + w * 1000}');
    return PinCheck(ok: false, failsLeft: maxPinFails - fails, waitSeconds: w);
  }

  Future<void> _forceSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    AppState.instance.clear();
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    await deactivate();
  }

  /// Cierra sesión desde la pantalla de bloqueo ("Olvidé mi PIN").
  Future<void> forgotPin() => _forceSignOut();

  /// Pide huella/rostro. Devuelve true si el sistema la validó.
  Future<bool> authenticateBiometric({String reason = 'Desbloquea FacturaVoz'}) async {
    if (_askingBiometric) return false;
    _askingBiometric = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    } finally {
      _askingBiometric = false;
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (!biometricOn || status != LockStatus.locked) return false;
    final ok = await authenticateBiometric();
    if (ok && status == LockStatus.locked) {
      status = LockStatus.unlocked;
      notifyListeners();
    }
    return ok;
  }

  /// Activa/desactiva la huella. Para activarla se confirma primero con el sensor.
  Future<bool> setBiometric(bool on) async {
    if (on) {
      biometricAvailable = await _canBio();
      if (!biometricAvailable) return false;
      if (!await authenticateBiometric(reason: 'Confirma tu huella para activarla')) return false;
    }
    biometricOn = on;
    await _write(_k('bio'), on ? '1' : '0');
    notifyListeners();
    return true;
  }

  void lockNow() {
    if (status == LockStatus.unlocked) {
      status = LockStatus.locked;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!_askingBiometric) _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _leftAt;
      _leftAt = null;
      if (at != null && !_askingBiometric && DateTime.now().difference(at) >= background) lockNow();
    }
  }
}
