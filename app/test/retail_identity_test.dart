import 'package:facturavoz/screens/login.dart';
import 'package:facturavoz/screens/onboarding.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 768.0]) {
    testWidgets('acceso original legible a $width con texto ampliado', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700), textScaler: const TextScaler.linear(1.6)),
        child: const LoginScreen(),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Tu negocio en movimiento.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('onboarding original permite terminar sin desbordar a $width', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var finished = false;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700), textScaler: const TextScaler.linear(1.6)),
        child: OnboardingScreen(onDone: () => finished = true),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empezar'));
      expect(finished, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
