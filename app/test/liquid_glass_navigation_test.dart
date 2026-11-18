import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/design_tokens.dart';
import 'package:facturavoz/ui/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final contrast in [false, true]) {
      testWidgets('Glass sin overflow en $brightness (contraste: $contrast)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: MediaQueryData(highContrast: contrast),
            child: Scaffold(
              body: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 300,
                  child: FvGlassSurface(
                    radius: 22,
                    padding: const EdgeInsets.all(16),
                    child: Text('Navegación',
                      style: TextStyle(color: FvTokens.text(brightness))),
                  ),
                ),
              ),
            ),
          ),
        ));
        expect(find.text('Navegación'), findsOneWidget);
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
