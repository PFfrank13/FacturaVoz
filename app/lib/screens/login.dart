import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _usePassword = false;
  bool _obscure = true;
  bool _sent = false;
  bool _busy = false;
  String _msg = '';
  int _cooldown = 0;
  Timer? _timer;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
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
      if (mounted) setState(() => _msg = _explainSendError(e));
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
          .verifyOtp(email: _email.text.trim().toLowerCase(), token: token, type: OtpType.email);
      // AuthGate reacciona al cambio de sesión.
    } catch (_) {
      if (mounted) setState(() => _msg = 'Código incorrecto o caducado');
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
      final text = m.contains('invalid login') || m.contains('invalid credentials')
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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.heroGradient),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Flexible(
              flex: 3,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                    child: Reveal(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 42),
                        ),
                        const SizedBox(height: 18),
                        const Text('FacturaVoz',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
                        const SizedBox(height: 6),
                        Text('Factura hablando.',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85), fontSize: 16)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            Flexible(
              flex: 5,
              fit: FlexFit.loose,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: dark ? Brand.darkBg : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 30, 24, 24 + MediaQuery.of(context).padding.bottom),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Reveal(
                        index: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Bienvenido', style: t.textTheme.headlineMedium),
                            const SizedBox(height: 6),
                            Text(
                              'Dicta el cliente y el importe, revisa y emite tu comprobante electrónico.',
                              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    enabled: !_sent,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
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
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _signInPassword(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _busy ? null : _signInPassword, child: Text(_busy ? 'Entrando…' : 'Entrar')),
                  ] else if (!_sent)
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: Text(_busy ? 'Enviando…' : 'Enviar código'),
                    )
                  else ...[
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(labelText: 'Código'),
                      onSubmitted: (_) => _verify(),
                    ),
                    FilledButton(onPressed: _busy ? null : _verify, child: Text(_busy ? 'Verificando…' : 'Entrar')),
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
                  if (!_sent)
                    TextButton(
                      onPressed: () => setState(() {
                        _usePassword = !_usePassword;
                        _msg = '';
                      }),
                      child: Text(_usePassword ? 'Usar código por correo' : 'Entrar con contraseña'),
                    ),
                  if (_msg.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_msg, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                            const SizedBox(height: 16),
                            if (Config.privacyUrl.isNotEmpty)
                              TextButton(onPressed: openPrivacyPolicy, child: const Text('Política de privacidad')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
