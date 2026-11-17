// §15/§17: pantallas de ~320 px de ancho lógico y letra grande sin desbordes (un desborde hace fallar la prueba).
import 'package:facturavoz/permissions.dart';
import 'package:facturavoz/screens/plan_compare.dart';
import 'package:facturavoz/ui/ds.dart';
import 'package:facturavoz/ui/onboarding_steps.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double width = 320, double scale = 1, Brightness b = Brightness.light, Widget? bottom}) async {
  tester.view.physicalSize = Size(width * 2, 640 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(b),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 640), textScaler: TextScaler.linear(scale)),
      child: Scaffold(bottomNavigationBar: bottom, body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    ),
  ));
  await tester.pump();
}

void main() {
  for (final scale in [1.0, 1.3]) {
    for (final b in Brightness.values) {
      testWidgets('planes a 320 px (letra x$scale, ${b.name})', (tester) async {
        await _pump(tester, PlanCompare(rubro: 'bodega', currentPlan: 'BASICO', onChoose: (_) {}), scale: scale, b: b);
        expect(find.text('RECOMENDADO'), findsOneWidget);
        expect(find.text('Tu plan actual'), findsOneWidget);
        expect(find.text('Elegir Pro'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('indicadores y barra de acción a 320 px (letra x$scale)', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        const DsStatGrid(children: [
          DsStat(label: 'Ventas de hoy', value: 'S/ 12,345.67', detail: '120 ventas'),
          DsStat(label: 'Estado de mi caja', value: 'Abierta', detail: 'Cierra con arqueo al final del día'),
          DsStat(label: 'Fiados por cobrar', value: 'S/ 999,999.99', detail: '35 clientes'),
          DsStat(label: 'Stock bajo', value: '12', detail: 'productos por reponer'),
        ]),
        scale: scale,
        bottom: DsActionBar(label: 'Cerrar caja (arqueo)', icon: Icons.lock_clock_rounded, onPressed: () => tapped = true),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cerrar caja (arqueo)'));
      expect(tapped, isTrue, reason: 'la acción principal se puede tocar');
    });

    testWidgets('pasos de activación a 320 px (letra x$scale)', (tester) async {
      await _pump(tester, const OnboardingSteps(current: 1), scale: scale);
      expect(find.textContaining('Paso 2 de 5'), findsOneWidget);
      expect(find.textContaining('Después: Empresa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('estado de error siempre ofrece Reintentar', (tester) async {
    var retried = 0;
    await _pump(tester, DsStateView.error(message: 'Sin conexión', onRetry: () => retried++));
    await tester.tap(find.text('Reintentar'));
    expect(retried, 1);
  });

  test('vista previa de permisos: el cajero no ve ganancia; el técnico no cobra', () {
    final cajero = previewPermissions('cajero', (_) => true);
    expect(cajero.allowed, contains('Registrar ventas'));
    expect(cajero.denied, contains('Ver ganancia y márgenes'));
    final tecnico = previewPermissions('tecnico', (_) => true);
    expect(tecnico.denied, containsAll(['Registrar cobros', 'Registrar ventas']));
    expect(previewPermissions('admin', (_) => true).denied, contains('Pagar o cambiar el plan'));
  });
}
