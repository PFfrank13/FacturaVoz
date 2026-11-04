import 'package:facturavoz/models_v2.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:facturavoz/ui/work_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 768.0]) {
    testWidgets('actividades legibles a $width con texto ampliado', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MediaQuery(
        data: MediaQueryData(size: Size(width, 1200), textScaler: const TextScaler.linear(1.6)),
        child: Scaffold(body: SingleChildScrollView(child: WorkQueue(title: 'Tus citas de hoy', jobs: [Job(id: 'local', title: 'Una actividad administrativa con un nombre largo')], onOpen: (_) => opened = true))),
      )));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(ListTile));
      expect(opened, isTrue);
    });
  }
}
