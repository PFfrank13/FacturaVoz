import '../ui/retail_identity.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'employee_login.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'legal.dart';

/// Acceso sin contraseña: código de 6-8 dígitos enviado por correo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _signup = false;
  bool _usePassword = true;
  bool _obscure = true;
  bool _sent = false;
  bool _busy = false;
  String _msg = '';
  int _cooldown = 0;
  Timer? _timer;
  static const _offlineMsg = 'No hay conexión a internet. Revisa tus datos móviles o el Wi‑Fi e inténtalo de nuevo.';

  static bool _isOffline(String lowerMsg) =>
      lowerMsg.contains('socketexception') || lowerMsg.contains('failed host lookup') || lowerMsg.contains('clientexception') || lowerMsg.contains('timed out');

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(what)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _msg = 'Escribe un correo válido');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email, shouldCreateUser: true);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _msg = 'Te enviamos un código a $email. Revisa también spam.';
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _msg = _isOffline(e.message.toLowerCase()) ? _offlineMsg : _explainSendError(e));
    } catch (_) {
      if (mounted) setState(() => _msg = 'No hay conexión. Revisa tu internet e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Traduce el error de Supabase a una causa concreta (sin exponer datos sensibles).
  String _explainSendError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('rate limit') || m.contains('too many') || e.statusCode == '429') {
      return 'Supabase limita los correos de su servicio gratuito (unos pocos por hora). Espera una hora, '
          'configura un SMTP propio en Supabase o entra con contraseña.';
    }
    if (m.contains('not authorized') || m.contains('not allowed') || m.contains('cannot be used')) {
      return 'Supabase solo envía correos a miembros de tu equipo mientras no configures un SMTP propio. '
          'Configura SMTP o entra con contraseña.';
    }
    if (m.contains('signups not allowed') || m.contains('otp') && m.contains('disabled')) {
      return 'El registro por código está desactivado en Supabase (Authentication → Providers → Email).';
    }
    if (m.contains('sending') || m.contains('smtp') || e.statusCode == '500') {
      return 'Supabase no pudo enviar el correo (revisa Authentication → Emails/SMTP). Mientras tanto, entra con contraseña.';
    }
    return 'No se pudo enviar el código (${e.message}). Entra con contraseña mientras lo revisas.';
  }

  Future<void> _verify() async {
    final token = _code.text.trim();
    if (!RegExp(r'^\d{6,8}$').hasMatch(token)) {
      setState(() => _msg = 'El código tiene 6 a 8 dígitos');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await Supabase.instance.client.auth
          .verifyOTP(email: _email.text.trim().toLowerCase(), token: token, type: OtpType.email);
      // AuthGate reacciona al cambio de sesión.
    } catch (_) {
      if (mounted) setState(() => _msg = 'Código incorrecto o caducado');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : Config.authRedirect,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _msg = 'No se pudo abrir Google: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _msg = 'No se pudo abrir el inicio de sesión con Google.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Registro con correo y contraseña (sin crear usuarios a mano en Supabase).
  Future<void> _signUp() async {
    final email = _email.text.trim().toLowerCase();
    final pass = _password.text;
    if (!_emailRe.hasMatch(email)) {
      setState(() => _msg = 'Escribe un correo válido');
      return;
    }
    if (pass.length < 8) {
      setState(() => _msg = 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _msg = 'Las contraseñas no coinciden');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final res = await Supabase.instance.client.auth.signUp(email: email, password: pass);
      if (!mounted) return;
      if (res.session != null) return; // sesión iniciada: AuthGate te lleva a la app
      if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
        setState(() {
          _signup = false;
          _msg = 'Ese correo ya está registrado. Inicia sesión con tu contraseña.';
        });
      } else {
        setState(() {
          _signup = false;
          _confirm.clear();
          _msg = 'Cuenta creada. Te enviamos un correo para confirmarla; ábrelo y luego inicia sesión.';
        });
      }
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      final text = _isOffline(m)
          ? _offlineMsg
          : m.contains('already') || m.contains('registered')
              ? 'Ese correo ya está registrado. Inicia sesión.'
              : m.contains('rate limit') || m.contains('too many') || e.statusCode == '429'
                  ? 'Demasiados intentos o correos enviados. Espera un rato e inténtalo otra vez.'
                  : m.contains('password')
                      ? 'La contraseña es muy débil. Usa 8 o más caracteres con letras y números.'
                      : m.contains('signups not allowed') || m.contains('disabled')
                          ? 'El registro está desactivado en Supabase (Authentication → Sign In / Providers → Email).'
                          : 'No se pudo crear la cuenta: ${e.message}';
      if (mounted) setState(() => _msg = text);
    } catch (_) {
      if (mounted) setState(() => _msg = _offlineMsg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Entrar con correo y contraseña. Solo para cuentas con contraseña creada a mano en Supabase (p. ej. revisores de las tiendas).
  Future<void> _signInPassword() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email) || _password.text.isEmpty) {
      setState(() => _msg = 'Escribe correo y contraseña');
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: _password.text);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      final text = _isOffline(m)
          ? _offlineMsg
          : m.contains('invalid login') || m.contains('invalid credentials')
          ? 'Correo o contraseña incorrectos'
          : m.contains('not confirmed')
              ? 'El correo no está confirmado en Supabase (marca Auto Confirm User)'
              : m.contains('api key') || m.contains('apikey')
                  ? 'La clave anon de Supabase con la que se compiló la app no es válida'
                  : 'No se pudo entrar: ${e.message}';
      if (mounted) setState(() => _msg = text);
    } catch (e) {
      if (mounted) setState(() => _msg = 'Sin conexión con Supabase (${e.runtimeType}). Revisa internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const RetailWordmark(), const SizedBox(height: 36),
            Text('Tu tienda.\nTodo en su lugar.', style: t.textTheme.displaySmall),
            const SizedBox(height: 12),
            Text('Productos, ventas y caja. Empieza por lo que necesitas hacer hoy.', style: t.textTheme.bodyLarge),
            const SizedBox(height: 28),
            Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(24), child: _form(t))),
            const SizedBox(height: 20),
            Text(RetailIdentity.maker, textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          ],
        )),
      ));
    })));
  }

  Widget _social(ThemeData t, String label, Widget mark, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: _busy ? null : onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.colorScheme.outline),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              mark,
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _form(ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_sent ? 'Revisa tu correo' : (_usePassword ? (_signup ? 'Crea tu cuenta' : 'Bienvenido de nuevo') : 'Crea tu cuenta'), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(
        _usePassword ? (_signup ? 'Regístrate con tu correo y una contraseña de 8 o más caracteres.' : 'Entra con tu correo y contraseña.') : 'Te enviamos un código y listo: sin contraseñas que recordar.',
        style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _email,
        enabled: !_sent,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded)),
      ),
      const SizedBox(height: 12),
      if (_usePassword) ...[
        TextField(
          controller: _password,
          obscureText: _obscure,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: _signup ? (_) => setState(() {}) : null,
          textInputAction: _signup ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) => _signup ? null : _signInPassword(),
        ),
        if (_signup) ...[
          _StrengthBar(password: _password.text),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Repite la contraseña', prefixIcon: Icon(Icons.lock_reset_rounded)),
            onSubmitted: (_) => _signUp(),
          ),
        ],
        const SizedBox(height: 16),
        GradientButton(
          label: _busy ? (_signup ? 'Creando…' : 'Entrando…') : (_signup ? 'Crear cuenta' : 'Entrar'),
          icon: _signup ? Icons.person_add_alt_1_rounded : Icons.arrow_forward_rounded,
          busy: _busy,
          onPressed: _busy ? null : (_signup ? _signUp : _signInPassword),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _signup = !_signup;
                    _msg = '';
                    _confirm.clear();
                  }),
          child: Text(_signup ? 'Ya tengo cuenta · Iniciar sesión' : '¿No tienes cuenta? Regístrate'),
        ),
      ] else if (!_sent)
        GradientButton(label: _busy ? 'Enviando…' : 'Enviar código', icon: Icons.send_rounded, busy: _busy, onPressed: _busy ? null : _send)
      else ...[
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 8,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(labelText: 'Código'),
          onSubmitted: (_) => _verify(),
        ),
        GradientButton(label: _busy ? 'Verificando…' : 'Entrar', icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _verify),
        TextButton(
          onPressed: (_busy || _cooldown > 0) ? null : _send,
          child: Text(_cooldown > 0 ? 'Reenviar código ($_cooldown s)' : 'Reenviar código'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _sent = false;
                    _code.clear();
                    _msg = '';
                  }),
          child: const Text('Cambiar correo'),
        ),
      ],
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _msg.isEmpty
              ? const SizedBox(width: double.infinity, key: ValueKey('nomsg'))
              : Padding(
                  key: ValueKey(_msg),
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_msg, textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
                ),
        ),
      ),
      if (!_sent) ...[
        const SizedBox(height: 14),
        // v2.0: acceso de empleados invitados por su empresa (mismo correo de la invitación).
        OutlinedButton.icon(
          onPressed: _busy ? null : () => showEmployeeLogin(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          icon: const Icon(Icons.badge_rounded),
          label: const Text('Iniciar con Empresa'),
        ),
      ],
      // Google/Apple quedan OCULTOS (no borrados) hasta activar GOOGLE_LOGIN=true; correo y contraseña siempre visibles.
      if (!_sent && Config.googleLogin) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Divider(color: t.colorScheme.outline)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('o continúa con', style: t.textTheme.bodySmall)),
          Expanded(child: Divider(color: t.colorScheme.outline)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _social(
            t,
            'Google',
            Text('G', style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: t.colorScheme.primary)),
            Config.googleLogin ? _google : () => _soon('El acceso con Google se activa al configurarlo en Supabase (docs/GOOGLE_LOGIN.md).'),
          ),
          const SizedBox(width: 12),
          _social(
            t,
            'Apple',
            const Icon(Icons.apple, size: 22),
            () => _soon('El acceso con Apple estará disponible junto con la versión de iPhone.'),
          ),
        ]),
      ],
      if (!_sent) ...[
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() {
            _usePassword = !_usePassword;
            _msg = '';
          }),
          child: Text(_usePassword ? '¿Primera vez? Crea tu cuenta con un código' : 'Ya tengo contraseña'),
        ),
      ],
      if (Config.privacyUrl.isNotEmpty) TextButton(onPressed: openPrivacyPolicy, child: const Text('Política de privacidad')),
    ]);
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.password});
  final String password;

  int get _score {
    if (password.isEmpty) return 0;
    var n = 0;
    if (password.length >= 8) n++;
    if (password.length >= 12) n++;
    if (RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password)) n++;
    if (RegExp(r'\d').hasMatch(password)) n++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) n++;
    return n.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final sc = _score;
    const labels = ['', 'Débil', 'Regular', 'Buena', 'Excelente'];
    final colors = [Colors.transparent, Brand.bad, Brand.warn, Brand.ok, Brand.ok];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: sc / 4),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: Theme.of(context).colorScheme.outline,
                valueColor: AlwaysStoppedAnimation<Color>(colors[sc] == Colors.transparent ? Brand.bad : colors[sc]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 70, child: Text(labels[sc], style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
