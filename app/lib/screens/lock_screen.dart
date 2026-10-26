// Pantalla de bloqueo: PIN de 6 dígitos + huella. Fondo animado, puntos que "saltan", sacudida al fallar,
// destello de éxito y salida con zoom. Se dibuja ENCIMA del Navigator (ver main.dart) para que ninguna
// pantalla abierta quede visible mientras la app está bloqueada.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pin_logic.dart';
import '../services/app_lock.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _okGreen = Color(0xFF5BE3B0);
const _errRose = Color(0xFFFF8A9B);

/// Fondo con dos halos que flotan lentamente.
class LockBackdrop extends StatefulWidget {
  const LockBackdrop({super.key, required this.child});
  final Widget child;

  @override
  State<LockBackdrop> createState() => _LockBackdropState();
}

class _LockBackdropState extends State<LockBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _halo(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0)]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A1940), Color(0xFF2B2480), Color(0xFF14132B)]),
        ),
      ),
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            return Stack(fit: StackFit.expand, children: [
              Align(alignment: Alignment(-0.9 + 0.35 * math.sin(t), -0.75 + 0.2 * math.cos(t)), child: _halo(Brand.lilac, 380)),
              Align(alignment: Alignment(0.95 + 0.25 * math.cos(t), 0.85 + 0.15 * math.sin(t)), child: _halo(Brand.gold, 340)),
            ]);
          },
        ),
      ),
      widget.child,
    ]);
  }
}

/// Teclado numérico + puntos. Reutilizable para desbloquear, crear y cambiar el PIN.
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
    required this.onDone,
    this.onBiometric,
    this.footer,
    this.lockedSeconds = 0,
    this.icon = Icons.lock_rounded,
  });

  final String title;
  final String subtitle;

  /// Devuelve un mensaje de error, o null si el PIN es válido.
  final Future<String?> Function(String pin) onSubmit;
  final VoidCallback onDone;
  final Future<void> Function()? onBiometric;
  final Widget? footer;
  final int lockedSeconds;
  final IconData icon;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> with TickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final List<Animation<double>> _st = List.generate(
    16,
    (i) => CurvedAnimation(parent: _in, curve: Interval(i * 0.03, i * 0.03 + 0.5, curve: Curves.easeOutCubic)),
  );

  String _pin = '';
  bool _busy = false;
  bool _ok = false;
  String? _error;

  bool get _blocked => widget.lockedSeconds > 0;

  @override
  void dispose() {
    _shake.dispose();
    _in.dispose();
    super.dispose();
  }

  void _tap(String d) {
    if (_busy || _ok || _blocked || _pin.length >= pinLength) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == pinLength) _submit();
  }

  void _back() {
    if (_busy || _ok || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 140)); // deja ver el último punto
    if (!mounted) return;
    String? err;
    try {
      err = await widget.onSubmit(_pin);
    } catch (_) {
      err = 'No se pudo verificar. Inténtalo de nuevo.';
    }
    if (!mounted) return;
    if (err == null) {
      HapticFeedback.mediumImpact();
      setState(() => _ok = true);
      await Future<void>.delayed(const Duration(milliseconds: 460));
      if (!mounted) return;
      widget.onDone();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _error = err);
    await _shake.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _pin = '';
      _busy = false;
    });
  }

  Widget _stag(int i, Widget child) => FadeTransition(
        opacity: _st[i],
        child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(_st[i]), child: child),
      );

  Widget _dots() {
    final color = _ok ? _okGreen : (_error != null ? _errRose : Colors.white);
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        return Transform.translate(offset: Offset(math.sin(t * math.pi * 5) * 14 * (1 - t), 0), child: child);
      },
      child: AnimatedScale(
        scale: _ok ? 1.14 : 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(pinLength, (i) {
            final on = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: on ? 18 : 13,
              height: on ? 18 : 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? color : Colors.white.withValues(alpha: 0.0),
                border: Border.all(color: on ? color : Colors.white.withValues(alpha: 0.4), width: 1.6),
                boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 12)] : null,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _key(double size, {String? digit, IconData? icon, VoidCallback? onTap, VoidCallback? onLong, required int i, String? label}) {
    if (digit == null && icon == null) return SizedBox(width: size, height: size);
    return _stag(
      i,
      AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _blocked && digit != null ? 0.35 : 1,
        child: Semantics(
          button: true,
          label: label ?? digit,
          excludeSemantics: true,
          child: Pressable(
            scale: 0.88,
            onTap: onTap,
            onLongPress: onLong,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: digit != null ? 0.12 : 0.0),
                border: digit != null ? Border.all(color: Colors.white.withValues(alpha: 0.14)) : null,
              ),
              child: digit != null
                  ? Text(digit, style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w500))
                  : Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: size * 0.4),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = _error ?? (_blocked ? 'Demasiados intentos. Reintenta en ${formatCountdown(widget.lockedSeconds)}' : widget.subtitle);
    return LayoutBuilder(builder: (context, c) {
      final size = ((c.maxHeight - 300) / 4 - 14).clamp(52.0, 76.0);
      final gap = c.maxHeight > 700 ? 28.0 : 14.0;
      Widget row(List<Widget> keys) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var j = 0; j < keys.length; j++) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: keys[j]),
            ]),
          );
      Widget d(String n, int i) => _key(size, digit: n, i: i, onTap: () => _tap(n));
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(height: gap),
            _stag(0, _PulseBadge(icon: widget.icon, ok: _ok)),
            SizedBox(height: gap * 0.7),
            _stag(1, Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3))),
            const SizedBox(height: 8),
            _stag(
              2,
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      message,
                      key: ValueKey(message),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _error != null ? _errRose : Colors.white.withValues(alpha: 0.72), fontSize: 14.5, height: 1.3),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: gap * 0.6),
            _stag(3, _dots()),
            SizedBox(height: gap),
            row([d('1', 4), d('2', 5), d('3', 6)]),
            row([d('4', 7), d('5', 8), d('6', 9)]),
            row([d('7', 10), d('8', 11), d('9', 12)]),
            row([
              widget.onBiometric != null
                  ? _key(size, icon: Icons.fingerprint_rounded, i: 13, label: 'Usar huella', onTap: () => widget.onBiometric!())
                  : SizedBox(width: size, height: size),
              d('0', 14),
              _key(size, icon: Icons.backspace_outlined, i: 15, label: 'Borrar', onTap: _back, onLong: () {
                if (!_busy && !_ok) setState(() => _pin = '');
              }),
            ]),
            if (widget.footer != null) ...[const SizedBox(height: 6), _stag(15, widget.footer!)],
            SizedBox(height: gap),
          ]),
        ),
      );
    });
  }
}

/// Escudo con halo que respira; se vuelve verde al acertar.
class _PulseBadge extends StatefulWidget {
  const _PulseBadge({required this.icon, required this.ok});
  final IconData icon;
  final bool ok;

  @override
  State<_PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<_PulseBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final glow = 18 + 14 * _c.value;
        final color = widget.ok ? _okGreen : Brand.lilac;
        return Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: glow, spreadRadius: 1)],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
            child: Icon(widget.ok ? Icons.check_rounded : widget.icon, key: ValueKey(widget.ok), color: Colors.white, size: 36),
          ),
        );
      },
    );
  }
}

/// Crear un PIN nuevo: escribirlo y confirmarlo.
class PinSetupFlow extends StatefulWidget {
  const PinSetupFlow({super.key, required this.onSave, required this.onFinished, this.title = 'Crea tu PIN'});
  final Future<void> Function(String pin) onSave;
  final VoidCallback onFinished;
  final String title;

  @override
  State<PinSetupFlow> createState() => _PinSetupFlowState();
}

class _PinSetupFlowState extends State<PinSetupFlow> {
  int _step = 0;
  String? _first;

  @override
  Widget build(BuildContext context) {
    final entry = _step == 0
        ? PinEntry(
            key: const ValueKey('setup0'),
            title: widget.title,
            subtitle: 'Elige $pinLength dígitos. Lo pedirás cada vez que abras la app.',
            icon: Icons.shield_rounded,
            onSubmit: (pin) async {
              if (isWeakPin(pin)) return 'Ese PIN es muy fácil de adivinar. Prueba otro.';
              _first = pin;
              return null;
            },
            onDone: () => setState(() => _step = 1),
          )
        : PinEntry(
            key: const ValueKey('setup1'),
            title: 'Confírmalo',
            subtitle: 'Escribe el mismo PIN otra vez.',
            icon: Icons.verified_user_rounded,
            onSubmit: (pin) async {
              if (pin != _first) {
                Future<void>.delayed(const Duration(milliseconds: 750), () {
                  if (mounted) {
                    setState(() {
                      _step = 0;
                      _first = null;
                    });
                  }
                });
                return 'No coinciden. Empecemos de nuevo.';
              }
              await widget.onSave(pin);
              return null;
            },
            onDone: widget.onFinished,
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) {
        final incoming = child.key == ValueKey('setup$_step');
        final begin = Offset(incoming ? 0.22 : -0.22, 0);
        return FadeTransition(opacity: a, child: SlideTransition(position: Tween<Offset>(begin: begin, end: Offset.zero).animate(a), child: child));
      },
      child: entry,
    );
  }
}

/// Pantalla que se muestra al abrir la app (o al volver tras un rato).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  Timer? _timer;
  Timer? _bioTimer;
  int _wait = 0;
  bool _forgot = false;

  @override
  void initState() {
    super.initState();
    _refreshWait();
    // La huella se ofrece sola, un instante después de que la pantalla aparece.
    _bioTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && _wait == 0) AppLock.instance.unlockWithBiometric();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bioTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshWait() async {
    final w = await AppLock.instance.waitSeconds();
    _setWait(w);
  }

  void _setWait(int w) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() => _wait = w);
    if (w > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        final n = _wait - 1;
        if (n <= 0) t.cancel();
        setState(() => _wait = n < 0 ? 0 : n);
      });
    }
  }

  Future<String?> _verify(String pin) async {
    final r = await AppLock.instance.verifyPin(pin, unlock: false);
    if (r.ok) return null;
    if (r.signedOut) return 'Demasiados intentos. Cerramos tu sesión por seguridad.';
    if (r.waitSeconds > 0) {
      _setWait(r.waitSeconds);
      return 'PIN incorrecto.';
    }
    return r.failsLeft <= 3 ? 'PIN incorrecto. Te quedan ${r.failsLeft} intentos.' : 'PIN incorrecto.';
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _forgot
          ? _ForgotPanel(key: const ValueKey('forgot'), onCancel: () => setState(() => _forgot = false), onConfirm: lock.forgotPin)
          : PinEntry(
              key: const ValueKey('pin'),
              title: 'Bienvenido de nuevo',
              subtitle: 'Ingresa tu PIN para continuar.',
              lockedSeconds: _wait,
              onSubmit: _verify,
              onDone: lock.unlockNow,
              onBiometric: lock.biometricOn ? () async => lock.unlockWithBiometric() : null,
              footer: TextButton(
                onPressed: () => setState(() => _forgot = true),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('¿Olvidaste tu PIN?'),
              ),
            ),
    );
  }
}

class _ForgotPanel extends StatelessWidget {
  const _ForgotPanel({super.key, required this.onCancel, required this.onConfirm});
  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _PulseBadge(icon: Icons.help_outline_rounded, ok: false),
          const SizedBox(height: 22),
          const Text('¿Olvidaste tu PIN?', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'Cerraremos tu sesión y volverás a entrar con tu correo. Tus facturas siguen guardadas en tu cuenta y podrás crear un PIN nuevo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.4),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => onConfirm(),
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.indigoDeep, minimumSize: const Size.fromHeight(52)),
              child: const Text('Cerrar sesión'),
            ),
          ),
          TextButton(onPressed: onCancel, style: TextButton.styleFrom(foregroundColor: Colors.white70), child: const Text('Volver')),
        ]),
      ),
    );
  }
}

/// Obliga a crear el PIN la primera vez (cuentas nuevas o antiguas sin PIN).
class SetupGate extends StatelessWidget {
  const SetupGate({super.key});

  @override
  Widget build(BuildContext context) => PinSetupFlow(
        title: 'Protege tu cuenta',
        onSave: AppLock.instance.setPin,
        onFinished: () => AppLock.instance.completeSetup(),
      );
}

/// Capa que se coloca en MaterialApp.builder, por encima de todas las pantallas.
class LockOverlay extends StatelessWidget {
  const LockOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLock.instance,
      builder: (context, _) {
        final l = AppLock.instance;
        Widget? content;
        if (l.status == LockStatus.checking) {
          content = const SizedBox.expand(key: ValueKey('chk'));
        } else if (l.status == LockStatus.locked) {
          content = const SafeArea(key: ValueKey('lock'), child: LockScreen());
        } else if (l.status == LockStatus.noPin && l.setupAllowed) {
          content = const SafeArea(key: ValueKey('setup'), child: SetupGate());
        }
        if (content != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => FocusManager.instance.primaryFocus?.unfocus());
        }
        return Stack(fit: StackFit.expand, children: [
          ExcludeSemantics(excluding: content != null, child: child),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (w, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween<double>(begin: 1.1, end: 1).animate(a), child: w),
            ),
            layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
            child: content == null
                ? const SizedBox.shrink(key: ValueKey('none'))
                : Material(
                    key: const ValueKey('shell'),
                    color: Colors.transparent,
                    child: LockBackdrop(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: content,
                      ),
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}
