import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'access.dart';
import 'app_state.dart';
import 'models_v2.dart';
import 'services/v2_repo.dart';
import 'screens/business_setup.dart';
import 'screens/license_gate.dart';
import 'screens/welcome_employee.dart';
import 'ui/motion.dart';
import 'config.dart';
import 'screens/lock_screen.dart';
import 'services/app_lock.dart';
import 'services/boot_cache.dart';
import 'screens/shell.dart';
import 'screens/login.dart';
import 'screens/onboarding.dart';
import 'screens/profile_form.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    // En producción nunca se muestra un error técnico crudo al usuario.
    ErrorWidget.builder = (details) => const Material(
          color: Color(0xFF14132B),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Algo salió mal en esta pantalla.\nVuelve atrás e inténtalo de nuevo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
              ),
            ),
          ),
        );
  }
  if (!Config.isValid) {
    runApp(const _ConfigError());
    return;
  }
  // La primera pantalla (logo) se dibuja YA; Supabase se inicia detrás, sin dejar la pantalla en blanco.
  runApp(const _Boot());
  // Mide los primeros cuadros: en teléfonos lentos reduce efectos solo (si el usuario no eligió otra cosa).
  PerfGuard.start();
}

/// Muestra el logo al instante y arranca Supabase en segundo plano; cuando está listo, entra la app.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // El archivo cifrado se lee a la vez que Supabase arranca: no suma tiempo.
      await Future.wait([Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey), BootCache.preload()]);
      AppLock.instance.bind();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const FacturaVozApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: Center(
          child: _failed
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('No se pudo iniciar la app.\nRevisa tu conexión y ábrela de nuevo.', textAlign: TextAlign.center),
                )
              : const _Splash(),
        ),
      ),
    );
  }
}

class FacturaVozApp extends StatelessWidget {
  const FacturaVozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.instance.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'FacturaVoz',
        navigatorKey: appNavigatorKey,
        scrollBehavior: const PremiumScrollBehavior(),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        builder: (context, child) {
          // Evita que una fuente del sistema muy grande rompa los diseños (sigue respetando la accesibilidad hasta 125 %).
          // También aplica "Animaciones reducidas" (interruptor de la app o teléfono lento) a TODA la app.
          final mq = MediaQuery.of(context);
          return ListenableBuilder(
            listenable: Listenable.merge([MotionPrefs.listenable, AppState.instance.easyMode]),
            builder: (context, _) => MediaQuery(
              data: mq.copyWith(
                // Modo Fácil: todo un 20 % más grande (hasta 145 %).
                textScaler: AppState.instance.easyMode.value
                    ? TextScaler.linear((mq.textScaler.scale(1) * 1.2).clamp(1.15, 1.45))
                    : mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25),
                disableAnimations: MotionPrefs.effective(mq.disableAnimations),
              ),
              child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => FocusManager.instance.primaryFocus?.unfocus(), child: LockOverlay(child: child!)),
            ),
          );
        },
        themeAnimationDuration: const Duration(milliseconds: 350),
        themeAnimationCurve: Curves.easeInOut,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        if (auth.currentSession == null) return const LoginScreen();
        return const ProfileGate();
      },
    );
  }
}

/// Carga el perfil; si no está completo, obliga a configurarlo antes de facturar.
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late bool _intro = Supabase.instance.client.auth.currentUser?.userMetadata?['onboarded'] != true;

  Future<void> _finishIntro() async {
    setState(() => _intro = false);
    // Best-effort: si falla, simplemente se verá de nuevo en el próximo inicio.
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'onboarded': true}));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // load() notifica a los ListenableBuilder; hacerlo dentro de initState (en plena construcción) lanza
    // "setState() called during build". Se espera al primer cuadro; mientras tanto se muestra la pantalla de carga.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppState.instance.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final s = AppState.instance;
        if (s.loading || (s.profile == null && s.error == null)) {
          return const Scaffold(body: Center(child: _Splash()));
        }
        if (s.error != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: s.load, child: const Text('Reintentar')),
                  TextButton(
                    onPressed: () async {
                      s.clear();
                      await Supabase.instance.client.auth.signOut();
                    },
                    child: const Text('Cerrar sesión'),
                  ),
                ]),
              ),
            ),
          );
        }
        if (!s.profile!.isComplete) {
          return _intro ? OnboardingScreen(onDone: _finishIntro) : const ProfileFormScreen(onboarding: true);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => AppLock.instance.allowSetup());
        return const V2Gate();
      },
    );
  }
}

class _ConfigError extends StatelessWidget {
  const _ConfigError();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Configuración incompleta.\nCompila con --dart-define=SUPABASE_URL, SUPABASE_ANON_KEY y API_BASE_URL (https).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla de carga: la marca "respira" suavemente.
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: const BrandMark(size: 72),
      );
}

/// Puertas v2.0 antes del shell: licencia bloqueada → pantalla de pago; empleado nuevo → bienvenida;
/// dueño sin tipo de negocio → presentación. Si las migraciones v2 no están, todo sigue como antes.
class V2Gate extends StatefulWidget {
  const V2Gate({super.key});

  @override
  State<V2Gate> createState() => _V2GateState();
}

class _V2GateState extends State<V2Gate> {
  OrgSettings? _settings = V2Repo.cachedSettings; // si ya hay configuración guardada, no se espera a la red
  String? _for;
  bool _setupClosed = false;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onApp);
    _loadSettings();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    if (_for != AppState.instance.activeOrg?.id) {
      setState(() {
        _settings = null;
        _setupClosed = false;
      });
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final org = AppState.instance.activeOrg?.id;
    _for = org;
    final s = await V2Repo.settings(refresh: true);
    if (mounted && _for == org) setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Access.instance,
      builder: (context, _) {
        final a = Access.instance;
        // Bloqueado: nadie entra. Solo lectura: entra el dueño/administrador (para pagar o exportar); el personal ve
        // la pantalla de pago (la base de datos igual no le muestra nada).
        if (a.loaded && (a.license.mode == 'blocked' || (a.license.mode == 'restricted' && !a.isAdmin))) return const LicenseGateScreen();
        if (a.loaded && !a.welcomed) return const EmployeeWelcomeScreen();
        final s = _settings;
        if (s == null) return const Scaffold(body: Center(child: _Splash()));
        // Solo se muestra sola si la migración v2 está aplicada, el usuario administra y aún no la vio.
        if (V2Repo.ready && !s.onboardingDone && a.isAdmin && !_setupClosed) {
          return BusinessSetupScreen(onDone: () {
            V2Repo.forgetSettings();
            setState(() => _setupClosed = true);
            _loadSettings();
          });
        }
        return const MainShell();
      },
    );
  }
}
