import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../config.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'legal.dart';

/// Acceso sin contraseña: código de 6-8 dígitos enviado por correo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _usePassword = true;
  bool _obscure = true;
  bool _sent = false;
  bool _busy = false;
  String _msg = '';
  int _cooldown = 0;
  Timer? _timer;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  bool _started = false;

  static const _offlineMsg = 'No hay conexión a internet. Revisa tus datos móviles o el Wi‑Fi e inténtalo de nuevo.';

  static bool _isOffline(String lowerMsg) =>
      lowerMsg.contains('socketexception') || lowerMsg.contains('failed host lookup') || lowerMsg.contains('clientexception') || lowerMsg.contains('timed out');

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
      _loop.stop();
    } else {
      _intro.forward();
    }
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(what)));
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
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

  /// Solo para cuentas con contraseña creada a mano en Supabase (p. ej. revisores de las tiendas).
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
    final dark = t.brightness == Brightness.dark;
    final kb = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight;
        return Stack(children: [
          Positioned.fill(child: RepaintBoundary(child: _HeroBackdrop(loop: _loop))),
          // Marca: nace en el centro y sube al hacer sitio a la hoja.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, _) {
                final move = Curves.easeInOutCubic.transform(const Interval(0.5, 0.82).transform(_intro.value));
                final y = h * (0.5 - 0.33 * move);
                return Stack(children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y - 70,
                    child: AnimatedOpacity(
                      opacity: kb ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: _BrandIntro(t: _intro, move: move),
                    ),
                  ),
                ]);
              },
            ),
          ),
          // Hoja blanca que sube con el formulario.
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: kb ? 0.12 : 0.36),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, target, _) => AnimatedBuilder(
                animation: _intro,
                builder: (context, _) {
                  final k = Curves.easeOutCubic.transform(const Interval(0.62, 1.0).transform(_intro.value));
                  return Stack(children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      top: h + (h * target - h) * k,
                      child: Container(
                        decoration: BoxDecoration(
                          color: dark ? Brand.darkBg : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 30, offset: const Offset(0, -8))],
                        ),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(24, 28, 24, 20 + MediaQuery.of(context).padding.bottom),
                          child: Center(
                            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: _form(t)),
                          ),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ]);
      }),
    );
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
      Text(_sent ? 'Revisa tu correo' : (_usePassword ? 'Bienvenido de nuevo' : 'Crea tu cuenta'), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(
        _usePassword ? 'Entra con tu correo y contraseña.' : 'Te enviamos un código y listo: sin contraseñas que recordar.',
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
          onSubmitted: (_) => _signInPassword(),
        ),
        const SizedBox(height: 16),
        GradientButton(label: _busy ? 'Entrando…' : 'Entrar', icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _busy ? null : _signInPassword),
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
      if (_msg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_msg, textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
        ),
      if (!_sent) ...[
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

/// Nombre de la app: las letras aparecen una a una y la marca respira.
class _BrandIntro extends StatelessWidget {
  const _BrandIntro({required this.t, required this.move});
  final Animation<double> t;
  final double move;

  static const _name = 'FacturaVoz';

  @override
  Widget build(BuildContext context) {
    final pop = Curves.elasticOut.transform(const Interval(0.0, 0.3).transform(t.value));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Transform.scale(
        scale: (0.4 + 0.6 * pop) * (1 - 0.18 * move),
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .22),
            border: Border.all(color: Colors.white.withValues(alpha: .5), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: .25), blurRadius: 30 * pop)],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 42),
        ),
      ),
      const SizedBox(height: 14),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _name.length; i++)
          Builder(builder: (_) {
            final a = Curves.easeOutCubic.transform(Interval(0.18 + i * 0.03, 0.34 + i * 0.03, curve: Curves.linear).transform(t.value));
            return Opacity(
              opacity: a,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - a)),
                child: Text(_name[i], style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              ),
            );
          }),
      ]),
      const SizedBox(height: 6),
      Opacity(
        opacity: Curves.easeOut.transform(const Interval(0.45, 0.62).transform(t.value)),
        child: Text('Factura hablando.', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: .88), fontSize: 16)),
      ),
    ]);
  }
}

/// Fondo ilustrado y animado: degradado, orbes que flotan y comprobantes translúcidos que se mecen.
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.loop});
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final a = loop.value * 2 * math.pi;
        Widget orb(double size, double x, double y, double ph, double alpha, {Gradient? g}) => Positioned(
              left: x + 18 * math.sin(a + ph),
              top: y + 22 * math.cos(a + ph),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: g == null ? Colors.white.withValues(alpha: alpha) : null, gradient: g),
              ),
            );
        Widget ticket(double x, double y, double rot, double ph, double scale) => Positioned(
              left: x,
              top: y + 10 * math.sin(a + ph),
              child: Transform.rotate(
                angle: rot + .05 * math.sin(a + ph),
                child: Transform.scale(scale: scale, child: const _MiniTicket()),
              ),
            );
        final w = MediaQuery.sizeOf(context).width;
        return DecoratedBox(
          decoration: const BoxDecoration(gradient: Brand.heroGradient),
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            orb(260, -90, -60, 0, .10),
            orb(180, w - 110, 120, 2, .08),
            orb(120, w * .45, 20, 4, .12, g: Brand.coralGradient),
            ticket(-18, 70, -.28, 1, .8),
            ticket(w - 110, 40, .22, 3, .9),
            ticket(w * .5 - 40, 210, -.08, 5, .62),
          ]),
        );
      },
    );
  }
}

class _MiniTicket extends StatelessWidget {
  const _MiniTicket();

  @override
  Widget build(BuildContext context) {
    Widget line(double w, {double a = .55}) => Container(width: w, height: 6, margin: const EdgeInsets.only(bottom: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: a), borderRadius: BorderRadius.circular(3)));
    return Container(
      width: 96,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line(40, a: .8),
        line(70),
        line(56),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerRight, child: line(34, a: .8)),
      ]),
    );
  }
}
