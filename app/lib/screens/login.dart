import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
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
    } catch (_) {
      if (mounted) setState(() => _msg = 'No se pudo enviar el código. Espera un minuto e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    } catch (_) {
      if (mounted) setState(() => _msg = 'Correo o contraseña incorrectos');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 56)),
                  const SizedBox(height: 28),
                  Text('Factura hablando.', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Dicta el cliente y el importe, revisa y emite tu comprobante electrónico.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 36),
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
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Contraseña'),
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
                  const SizedBox(height: 24),
                  if (Config.privacyUrl.isNotEmpty)
                    TextButton(onPressed: openPrivacyPolicy, child: const Text('Política de privacidad')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
