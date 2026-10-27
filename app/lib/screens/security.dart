import 'package:flutter/material.dart';

import '../pin_logic.dart';
import '../services/app_lock.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'lock_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggleBio(bool on) async {
    setState(() => _busy = true);
    final ok = await AppLock.instance.setBiometric(on);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok && on) _snack('No se pudo activar la huella. Verifica que tengas una registrada en el teléfono.');
  }

  Future<void> _changePin() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ChangePinScreen()));
    if (done == true && mounted) _snack('PIN actualizado');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad')),
      body: ListenableBuilder(
        listenable: AppLock.instance,
        builder: (context, _) {
          final l = AppLock.instance;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Reveal(
              index: 0,
              child: SoftCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  SwitchListTile(
                    secondary: Icon(Icons.fingerprint_rounded, color: t.colorScheme.primary),
                    title: const Text('Huella o rostro', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(l.biometricAvailable ? 'Entra sin escribir el PIN' : 'No hay huella registrada en este teléfono'),
                    value: l.biometricOn,
                    onChanged: (l.biometricAvailable && !_busy) ? _toggleBio : null,
                  ),
                  Divider(indent: 16, color: t.colorScheme.outline),
                  ListTile(
                    leading: Icon(Icons.password_rounded, color: t.colorScheme.primary),
                    title: const Text('Cambiar PIN', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Necesitarás tu PIN actual'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changePin,
                  ),
                  Divider(indent: 16, color: t.colorScheme.outline),
                  ListTile(
                    leading: Icon(Icons.lock_clock_rounded, color: t.colorScheme.primary),
                    title: const Text('Bloquear ahora', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('También se bloquea sola tras unos segundos fuera de la app'),
                    onTap: l.lockNow,
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tu PIN se guarda cifrado en este teléfono y nunca sale de él. Tras $maxPinFails intentos fallidos se cierra tu sesión.',
              style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
            ),
          ]);
        },
      ),
    );
  }
}

/// Cambiar el PIN: primero el actual, luego el nuevo dos veces.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  bool _verified = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.darkBg,
      body: LockBackdrop(
        child: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _verified
                  ? PinSetupFlow(
                      key: const ValueKey('new'),
                      title: 'Nuevo PIN',
                      onSave: AppLock.instance.setPin,
                      onFinished: () => Navigator.of(context).pop(true),
                    )
                  : PinEntry(
                      key: const ValueKey('old'),
                      title: 'Tu PIN actual',
                      subtitle: 'Confirma que eres tú.',
                      onSubmit: (pin) async {
                        final r = await AppLock.instance.verifyPin(pin, unlock: false);
                        if (r.ok) return null;
                        if (r.signedOut) return 'Demasiados intentos. Cerramos tu sesión.';
                        if (r.waitSeconds > 0) return 'Espera ${formatCountdown(r.waitSeconds)} para volver a intentar.';
                        return 'PIN incorrecto.';
                      },
                      onDone: () => setState(() => _verified = true),
                    ),
            )),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
