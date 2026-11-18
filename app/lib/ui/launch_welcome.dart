import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bienvenida breve y opcional. Usuarios autenticados pasan directo a Caja/Inicio sin espera extra.
class LaunchWelcome extends StatefulWidget {
  const LaunchWelcome({super.key, required this.child});
  final Widget child;
  @override State<LaunchWelcome> createState() => _LaunchWelcomeState();
}

class _LaunchWelcomeState extends State<LaunchWelcome> with SingleTickerProviderStateMixin {
  bool _done = false;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  @override void initState() {
    super.initState();
    // Un negocio que ya inició sesión no necesita otra presentación de marca.
    // Supabase se inicializó en _Boot antes de montar FacturaVozApp.
    if (Supabase.instance.client.auth.currentSession != null) {
      _done = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) { _finish(); return; }
      _intro.forward();
      Future<void>.delayed(const Duration(milliseconds: 1150), () { if (mounted) _finish(); });
    });
  }
  void _finish() { if (!_done && mounted) setState(() => _done = true); }
  @override void dispose() { _intro.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    if (_done) return widget.child;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Brand.darkBg,
      body: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/photos/welcome_scene.webp', fit: BoxFit.cover,
            alignment: Alignment.center),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xB00A1520), Color(0x480C5A56), Color(0xE80A1520)],
          stops: [0, .48, 1]))),
        SafeArea(child: Padding(padding: const EdgeInsets.all(26), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const BrandMark(size: 48), const SizedBox(width: 12),
              const Text('FacturaVoz', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -.7)),
              const Spacer(),
              TextButton(onPressed: _finish, child: const Text('Omitir', style: TextStyle(color: Colors.white)))
            ]),
            const Spacer(),
            FadeTransition(opacity: _intro, child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 44, height: 4, decoration: BoxDecoration(color: const Color(0xFF83E6D9), borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 18),
                const Text('Bienvenido a\nFacturaVoz', style: TextStyle(fontSize: 39, fontWeight: FontWeight.w800,
                    height: 1.09, color: Colors.white, letterSpacing: -1.2)),
                const SizedBox(height: 12),
                const Text('Tu negocio en movimiento. Vende, organiza y factura con confianza.',
                  style: TextStyle(fontSize: 16, color: Color(0xFFE9F8F7), height: 1.5)),
                const SizedBox(height: 24),
              ]))),
            Padding(padding: EdgeInsets.only(bottom: bottom > 0 ? 0 : 8), child: SizedBox(width: double.infinity,
              child: FilledButton.icon(onPressed: _finish, icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Comenzar'), style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF42CDBA), foregroundColor: const Color(0xFF062E2B))))),
          ],
        ))),
      ]),
    );
  }
}
