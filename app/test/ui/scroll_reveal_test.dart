import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/scroll_reveal.dart';

void main() {
  testWidgets('La sección solo aparece al alcanzar el viewport y no se reinicia',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: const Column(
            children: [
              SizedBox(height: 720),
              FvScrollReveal(
                child: SizedBox(
                  key: ValueKey('reveal-target'),
                  height: 100,
                  width: 200,
                ),
              ),
              SizedBox(height: 250),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    final fade = find.descendant(
      of: find.byType(FvScrollReveal),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);

    controller.jumpTo(400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

    controller.jumpTo(0);
    await tester.pump();
    controller.jumpTo(400);
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
  });

  testWidgets('Reducir movimiento hace visible el contenido sin transiciones',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: FvScrollReveal(child: Text('Sección accesible')),
      ),
    ));
    expect(find.text('Sección accesible'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FvScrollReveal),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });
}
