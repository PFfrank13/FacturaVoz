import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Introducción de 3 pasos para usuarios nuevos (solo se muestra una vez).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  static const _pages = [
    (Icons.mic_rounded, 'Dicta tu venta', 'Di el cliente, lo que vendiste y el precio. FacturaVoz arma la factura por ti en segundos.'),
    (Icons.fact_check_rounded, 'Revisa antes de guardar', 'Ves todo lo que entendió, lo corriges si hace falta y te avisamos si algo se ve raro, como un monto muy alto o un cliente sin documento.'),
    (Icons.mark_email_read_rounded, 'Envía y emite', 'Comparte el PDF, recibe una copia en tu correo y, con tu RUC configurado, emite el comprobante electrónico a SUNAT.'),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_i == _pages.length - 1) {
      widget.onDone();
    } else {
      _page.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final last = _i == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: last ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: TextButton(onPressed: last ? null : widget.onDone, child: const Text('Saltar')),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: _pages.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (context, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Reveal(
                      key: ValueKey('icon$i'),
                      child: Container(
                        width: 128,
                        height: 128,
                        decoration: BoxDecoration(gradient: Brand.heroGradient, shape: BoxShape.circle, boxShadow: Brand.softShadow(false, a: .25)),
                        child: Icon(p.$1, size: 56, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Reveal(
                      key: ValueKey('title$i'),
                      index: 1,
                      child: Text(p.$2, textAlign: TextAlign.center, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 12),
                    Reveal(
                      key: ValueKey('body$i'),
                      index: 2,
                      child: Text(p.$3, textAlign: TextAlign.center, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4)),
                    ),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var d = 0; d < _pages.length; d++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: d == _i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: d == _i ? t.colorScheme.primary : t.colorScheme.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: GradientButton(label: last ? 'Empezar' : 'Siguiente', icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded, onPressed: _next),
          ),
        ]),
      ),
    );
  }
}
