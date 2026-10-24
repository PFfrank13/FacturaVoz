import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/profile_form.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Config.isValid) {
    runApp(const _ConfigError());
    return;
  }
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  runApp(const FacturaVozApp());
}

class FacturaVozApp extends StatelessWidget {
  const FacturaVozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FacturaVoz',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
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
          return const Scaffold(body: Center(child: BrandMark(size: 64)));
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
        if (!s.profile!.isComplete) return const ProfileFormScreen(onboarding: true);
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
