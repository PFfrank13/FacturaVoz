// Pruebas de widgets del sistema de movimiento v2.0: se construyen, animan y se destruyen sin errores
// (controladores liberados, sin valores negativos en sombras, funcionan con "Animaciones reducidas").
import 'package:facturavoz/ui/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('SwipeActions dispara la acción al pasar el umbral y vuelve a su lugar', (tester) async {
    var hits = 0;
    await tester.pumpWidget(_wrap(SizedBox(
      width: 300,
      height: 80,
      child: SwipeActions(
        left: SwipeAction(icon: Icons.receipt_long, label: 'Facturar', color: Colors.orange, onTrigger: () => hits++),
        child: const ColoredBox(color: Colors.white, child: SizedBox.expand(child: Text('Rosa'))),
      ),
    )));
    await tester.drag(find.text('Rosa'), const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(hits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SwipeActions no hace nada con un gesto corto', (tester) async {
    var hits = 0;
    await tester.pumpWidget(_wrap(SizedBox(
      width: 300,
      height: 80,
      child: SwipeActions(
        right: SwipeAction(icon: Icons.chat, label: 'WhatsApp', color: Colors.green, onTrigger: () => hits++),
        child: const SizedBox.expand(child: Text('Juan')),
      ),
    )));
    await tester.drag(find.text('Juan'), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(hits, 0);
  });

  testWidgets('Shake anima al cambiar el disparador y respeta "reducir movimiento"', (tester) async {
    await tester.pumpWidget(_wrap(const Shake(trigger: 0, child: Text('PIN'))));
    await tester.pumpWidget(_wrap(const Shake(trigger: 1, child: Text('PIN'))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(const Shake(trigger: 2, child: Text('PIN')), reduce: true));
    await tester.pumpAndSettle();
    expect(find.text('PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VoiceWave se dibuja y se destruye sin dejar animaciones vivas', (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox(width: 240, child: VoiceWave(level: 0.7))));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_wrap(const SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('VoiceWave con animaciones reducidas es estática', (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox(width: 240, child: VoiceWave(level: 0.5)), reduce: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatusMorph cambia de contenido con transición', (tester) async {
    await tester.pumpWidget(_wrap(const StatusMorph(status: 'pendiente', child: Text('Pendiente'))));
    await tester.pumpWidget(_wrap(const StatusMorph(status: 'cobrada', child: Text('Cobrada'))));
    await tester.pumpAndSettle();
    expect(find.text('Cobrada'), findsOneWidget);
    expect(find.text('Pendiente'), findsNothing);
  });

  test('MotionPrefs: automático, reducido y completo', () {
    MotionPrefs.userReduced.value = null;
    PerfGuard.slowDevice.value = false;
    expect(MotionPrefs.effective(false), isFalse);
    expect(MotionPrefs.effective(true), isTrue);
    PerfGuard.slowDevice.value = true;
    expect(MotionPrefs.effective(false), isTrue);
    MotionPrefs.userReduced.value = false;
    expect(MotionPrefs.effective(false), isFalse);
    MotionPrefs.userReduced.value = true;
    expect(MotionPrefs.effective(false), isTrue);
    MotionPrefs.userReduced.value = null;
    PerfGuard.slowDevice.value = false;
  });
}
