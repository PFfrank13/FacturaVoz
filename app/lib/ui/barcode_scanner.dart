// Lector de códigos de barras con la cámara (gratis, sin servidores). Las pistolas lectoras USB/Bluetooth funcionan
// como teclado: basta con tener el cursor en el campo "Código de barras".
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'motion.dart';
import 'design_tokens.dart';

Future<String?> scanBarcode(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> with SingleTickerProviderStateMixin {
  bool _done = false;
  late final AnimationController _scanLine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _scanLine.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim() ?? '';
      if (v.isEmpty) continue;
      _done = true;
      Haptics.success();
      Navigator.of(context).pop(v);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Apunta al código de barras'), backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Stack(children: [
          Positioned.fill(
            // Sin errorBuilder a propósito: su firma cambió entre versiones del paquete; el texto de abajo ya orienta.
            child: MobileScanner(onDetect: _onDetect),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 35,
            child: SafeArea(
              top: false,
              child: FvGlassSurface(
                radius: 22,
                blur: 16,
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 28),
                  const SizedBox(height: 6),
                  Text('Apunta al código del producto',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Lo reconoceremos y mostraremos su precio al instante. '
                    'También puedes usar un lector USB o Bluetooth en Venta rápida.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 264, height: 172,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: .9), width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: MediaQuery.disableAnimationsOf(context)
                  ? const SizedBox.shrink()
                  : AnimatedBuilder(
                      animation: _scanLine,
                      builder: (context, _) => Stack(children: [
                        Positioned(
                          top: _scanLine.value * 169,
                          left: 20, right: 20,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: FvTokens.emeraldDark,
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: const [BoxShadow(
                                color: Color(0xAA10B981), blurRadius: 12)],
                            ),
                          ),
                        ),
                      ]),
                    ),
              ),
            ),
          ),
        ]),
      );
}
