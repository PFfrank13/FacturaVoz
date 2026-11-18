import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/motion.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  testWidgets('La tarjeta responde al toque y cancela el efecto al desplazar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: FvTactileScale(
            child: SizedBox(
              key: ValueKey('tactile-target'),
              width: 100,
              height: 100,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    ));

    final scale = find.descendant(
      of: find.byType(FvTactileScale),
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(scale).scale, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('tactile-target'))),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(scale).scale, closeTo(0.985, 0.001));

    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
    await gesture.up();
  });

  testWidgets('FadeThrough desactiva la animación cuando lo solicita accesibilidad', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: FadeThrough(child: Text('Contenido')),
      ),
    ));
    expect(tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration, Duration.zero);
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('Scroll usa físicas adecuadas para $platform', (tester) async {
      ScrollPhysics? physics;
      await tester.pumpWidget(MaterialApp(
        home: Theme(
          data: ThemeData(platform: platform),
          child: Builder(builder: (context) {
            physics = const PremiumScrollBehavior().getScrollPhysics(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      final mobile = platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS;
      if (mobile) {
        expect(physics, isA<BouncingScrollPhysics>());
      } else {
        expect(physics, isA<ClampingScrollPhysics>());
      }
    });
  }
}
