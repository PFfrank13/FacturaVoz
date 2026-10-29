// "Iniciar con Empresa": el empleado entra (o crea su cuenta) con el MISMO correo con el que el dueño lo invitó.
// Al entrar, la base de datos lo une a la empresa (claim_invites / handle_new_user) con el rol que le asignaron.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

Future<void> showEmployeeLogin(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _EmployeeSheet(),
    );

class _EmployeeSheet extends StatefulWidget {
  const _EmployeeSheet();

  @override
  State<_EmployeeSheet> createState() => _EmployeeSheetState();
}

class _EmployeeSheetState extends State<_EmployeeSheet> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _create = false;
  bool _busy = false;
  bool _obscure = true;
  String _msg = '';
  int _shake = 0;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _fail(String m) {
    Haptics.error();
    setState(() {
      _msg = m;
      _busy = false;
      _shake++;
    });
  }

  Future<void> _go() async {
    final email = _email.text.trim().toLowerCase();
    final pass = _pass.text;
    if (!_emailRe.hasMatch(email)) return _fail('Escribe el correo con el que te invitaron.');
    if (pass.length < 8) return _fail('La contraseña debe tener 8 caracteres o más.');
    setState(() {
      _busy = true;
      _msg = '';
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_create) {
        final r = await auth.signUp(email: email, password: pass, data: const {'joined_as': 'employee'});
        if (r.session == null) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _msg = 'Te enviamos un correo para confirmar tu cuenta. Ábrelo y luego vuelve aquí y toca "Entrar".';
            _create = false;
          });
          return;
        }
      } else {
        await auth.signInWithPassword(email: email, password: pass);
      }
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return _fail('Correo o contraseña incorrectos. Si es tu primera vez, toca "Es mi primera vez".');
      if (m.contains('already registered')) return _fail('Ese correo ya tiene cuenta: toca "Ya tengo cuenta" y entra.');
      if (m.contains('not confirmed')) return _fail('Confirma tu correo con el enlace que te enviamos y vuelve a intentar.');
      _fail('No se pudo entrar. Revisa tus datos e inténtalo de nuevo.');
    } catch (_) {
      _fail('Sin conexión. Revisa tu internet e inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.badge_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Entrar a la empresa donde trabajo', style: t.textTheme.titleLarge)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Usa el mismo correo con el que tu jefe te invitó. Verás solo lo que tu rol permite (por ejemplo, un técnico ve sus trabajos).',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Ya tengo cuenta'), icon: Icon(Icons.login_rounded)),
              ButtonSegment(value: true, label: Text('Es mi primera vez'), icon: Icon(Icons.person_add_alt_1_rounded)),
            ],
            selected: {_create},
            onSelectionChanged: _busy ? null : (s) => setState(() => _create = s.first),
          ),
          const SizedBox(height: 16),
          Shake(
            trigger: _shake,
            child: Column(children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Correo de la invitación', prefixIcon: Icon(Icons.mail_outline_rounded)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  labelText: _create ? 'Crea una contraseña (8+ caracteres)' : 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: _busy ? 'Un momento…' : (_create ? 'Crear mi cuenta y entrar' : 'Entrar'),
            icon: Icons.arrow_forward_rounded,
            busy: _busy,
            onPressed: _busy ? null : _go,
          ),
          AnimatedSize(
            duration: Motion.d(context, Motion.medium),
            child: _msg.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg, textAlign: TextAlign.center, style: t.textTheme.bodyMedium)),
          ),
          const SizedBox(height: 8),
          Text(
            '¿No te llegó invitación? Pídele al dueño que te agregue en Ajustes → Equipo con este correo.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}
