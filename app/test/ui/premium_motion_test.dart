import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/motion.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  testWidgets('La cantidad cambia de dirección con toques rápidos y anuncia sólo el valor actual', (tester) async {
    final quantity = ValueNotifier('12');
    addTearDown(quantity.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(child: ValueListenableBuilder<String>(
        valueListenable: quantity,
        builder: (_, value, _) => FvQuantityText(value),
      )),
    ));

    quantity.value = '13';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final rising = find.ancestor(of: find.text('3'), matching: find.byType(FractionalTranslation));
    expect(tester.widget<FractionalTranslation>(rising.first).translation.dy, greaterThan(0));
    expect(find.text('1'), findsOneWidget);
    quantity.value = '11';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.bySemanticsLabel('11'), findsOneWidget);
    expect(find.bySemanticsLabel('13'), findsNothing);
    final offsets = tester.widgetList<FractionalTranslation>(
      find.ancestor(of: find.text('1'), matching: find.byType(FractionalTranslation)),
    ).map((w) => w.translation.dy);
    expect(offsets, contains(lessThan(0.0)));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
  });

  testWidgets('Reducir movimiento presenta la cantidad y el sello terminados', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Column(children: [FvQuantityText('10.25'), FvReceiptCheck()]),
      ),
    ));
    expect(find.text('10.25'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(find.descendant(of: find.byType(FvReceiptCheck), matching: find.byType(CustomPaint)), findsOneWidget);
  });

  testWidgets('El botón con respuesta táctil se puede activar una vez por teclado', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FvTactileScale(
        child: FilledButton(
          autofocus: true,
          onPressed: () => calls++,
          child: const Text('Confirmar'),
        ),
      )),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

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
      if (platform == TargetPlatform.iOS) {
        expect(physics, isA<BouncingScrollPhysics>());
      } else {
        // Android usa scroll nativo Material; escritorio usa rueda/trackpad.
        expect(physics, isA<ClampingScrollPhysics>());
      }
    });
  }
}
