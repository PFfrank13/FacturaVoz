import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/lock_screen.dart';
import 'services/app_lock.dart';
import 'screens/home.dart';
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
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  AppLock.instance.bind();
  runApp(const FacturaVozApp());
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
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        builder: (context, child) {
          // Evita que una fuente del sistema muy grande rompa los diseños (sigue respetando la accesibilidad hasta 125 %).
          final mq = MediaQuery.of(context);
          return MediaQuery(data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25)), child: LockOverlay(child: child!));
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
    AppState.instance.load();
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
        return const HomeScreen();
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
