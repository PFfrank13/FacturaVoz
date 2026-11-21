import 'package:facturavoz/ui/retail_sales_trend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = ValueKey('retail-trend-plot');
  Future<void> mount(WidgetTester tester, ScrollController scroll) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              RetailSalesTrend(
                values: const [45, -4, 0, 10],
                currency: 'PEN',
                lastDay: DateTime(2026, 1, 2),
              ),
              const SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'el gesto horizontal selecciona importes y el vertical desplaza Inicio',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await mount(tester, scroll);
      final box = tester.getRect(find.byKey(key));
      await tester.tapAt(Offset(box.left + box.width * .35, box.center.dy));
      await tester.pump();
      expect(find.text('31 dic · S/ -4.00'), findsOneWidget);
      await tester.dragFrom(box.center, Offset(box.width, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 ene · S/ 10.00'), findsOneWidget);
      await tester.dragFrom(box.center, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(50));
    },
  );

  testWidgets(
    'las flechas recorren días y el lector anuncia la fecha y el importe',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await mount(tester, scroll);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(find.text('30 dic · S/ 45.00'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final control = tester.getSemantics(
        find.bySemanticsLabel('Ventas diarias, últimos 4 días'),
      );
      expect(control.getSemanticsData().value, '31 dic · S/ -4.00');
      expect(control.getSemanticsData().increasedValue, '1 ene · S/ 0.00');
    },
  );
}
