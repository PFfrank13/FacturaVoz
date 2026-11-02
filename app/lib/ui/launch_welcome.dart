import 'package:flutter/material.dart';
import 'theme.dart';
import 'widgets.dart';

/// Brief, skippable welcome. Shown once each app process, never blocks a sale after startup.
class LaunchWelcome extends StatefulWidget {
  const LaunchWelcome({super.key, required this.child});
  final Widget child;
  @override State<LaunchWelcome> createState() => _LaunchWelcomeState();
}

class _LaunchWelcomeState extends State<LaunchWelcome> with SingleTickerProviderStateMixin {
  bool _done = false;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1050));
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) { _finish(); return; }
      _intro.forward();
      Future<void>.delayed(const Duration(milliseconds: 2600), () { if (mounted) _finish(); });
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
          colors: [Color(0x8C0A1132), Color(0x300B1238), Color(0xDA0A1132)],
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
                Container(width: 44, height: 4, decoration: BoxDecoration(color: const Color(0xFF47D9FF), borderRadius: BorderRadius.circular(8))),
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
                  backgroundColor: const Color(0xFF6348EA), foregroundColor: Colors.white)))),
          ],
        ))),
      ]),
    );
  }
}
