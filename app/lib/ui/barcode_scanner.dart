// Lector de códigos de barras con la cámara (gratis, sin servidores). Las pistolas lectoras USB/Bluetooth funcionan
// como teclado: basta con tener el cursor en el campo "Código de barras".
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'motion.dart';

Future<String?> scanBarcode(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

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
          const Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text('Si la cámara no abre, permite el acceso en Ajustes del teléfono o escribe el código a mano.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          ),
          Center(
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ]),
      );
}
