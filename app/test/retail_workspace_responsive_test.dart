import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/retail_workspace.dart';

void main() {
  testWidgets('workspace usa ancho completo en movil y limita escritorio', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in <double>[320, 360, 768, 960, 1024, 1440, 1920, 3440]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RetailWorkspace(
              child: SizedBox(
                key: Key('content'),
                width: double.infinity,
                height: 150,
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const Key('content')));
      final expectedWidth = width <= 960 ? width : 960.0;
      expect(rect.width, closeTo(expectedWidth, 0.01), reason: 'viewport $width');
      expect(rect.left, closeTo((width - expectedWidth) / 2, 0.01),
          reason: 'centrado a $width');
    }
  });
}
