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

  testWidgets('El scroll conserva rebote en móvil y precisión en escritorio', (tester) async {
    ScrollPhysics? physics;
    Future<void> check(TargetPlatform platform) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(builder: (context) {
          physics = const PremiumScrollBehavior().getScrollPhysics(context);
          return const SizedBox.shrink();
        }),
      ));
    }

    await check(TargetPlatform.iOS);
    expect(physics, isA<BouncingScrollPhysics>());
    await check(TargetPlatform.windows);
    expect(physics, isA<ClampingScrollPhysics>());
  });
}
