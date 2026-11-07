import 'package:facturavoz/access.dart';
import 'package:facturavoz/screens/receiving.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$w.otf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [375.0, 768.0]) {
    testWidgets(
      'recepción conserva UUID ante error y actualiza existencias a $width',
      (tester) async {
        Access.instance.isAdmin = true;
        Access.instance.licenseCheckedOnline = true;
        Access.instance.license = const LicenseInfo(
          source: 'hub',
          mode: 'full',
          features: {'stock': true},
        );
        addTearDown(Access.instance.clear);
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final attempts = <Map<String, dynamic>>[];
        var stock = 8;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            home: ReceivingScreen(
              loadData: () async => {
                'products': [
                  {
                    'id': '11111111-1111-4111-8111-111111111111',
                    'name': 'Arroz superior QA',
                    'stock': stock,
                    'unit_cost': 6,
                  },
                ],
                'receipts': stock == 8
                    ? []
                    : [
                        {
                          'id': 'qa-confirmed',
                          'supplier_name': 'Distribuidora QA',
                          'reference': 'F001-QA',
                          'total': 30,
                          'currency': 'PEN',
                          'created_at': '2026-11-07',
                        },
                      ],
              },
              receive: (input) async {
                attempts.add(input);
                if (attempts.length == 1) throw StateError('respuesta perdida');
                stock = 13;
                return 'qa-confirmed';
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Proveedor'),
          'Distribuidora QA',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Documento o referencia única'),
          'F001-QA',
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Arroz superior QA · 8').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Cantidad recibida'),
          '5',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Costo unitario de adquisición'),
          '6',
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/receiving-form-$width.png'),
        );
        if (width == 768) {
          await tester.ensureVisible(find.text('Añadir al documento'));
          await tester.tap(find.text('Añadir al documento'));
          await tester.pumpAndSettle();
          expect(find.text('5.0 × 6.0'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Confirmar recepción'));
        await tester.tap(find.text('Confirmar recepción'));
        await tester.pumpAndSettle();
        expect(find.text('Recepción confirmada'), findsNothing);
        await tester.ensureVisible(find.text('Recuperar misma recepción'));
        await tester.tap(find.text('Recuperar misma recepción'));
        await tester.pumpAndSettle();
        expect(attempts.length, 2);
        expect(attempts[0]['p_request'], attempts[1]['p_request']);
        await tester.drag(find.byType(ListView), const Offset(0, 1000));
        await tester.pumpAndSettle();
        expect(find.text('Recepción confirmada'), findsOneWidget);
        expect(find.text('13'), findsOneWidget);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/receiving-confirmed-$width.png'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
