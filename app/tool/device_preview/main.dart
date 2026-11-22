import 'dart:async';

import 'package:facturavoz/screens/shell.dart';
import 'package:facturavoz/services/live.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../browser_qa/offline_retail.dart';

/// Vista de QA para teléfonos y simuladores: abre el `MainShell` con la tienda
/// ficticia Mercado Oliva. Todo el tráfico de Supabase responde en memoria; no
/// usa credenciales, no emite ventas y no toca producción.
///
/// Con `--dart-define=DEMO_ISLAND=true` publica cada pocos segundos un evento
/// comercial ficticio para grabar la isla dinámica en movimiento.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    throw StateError('La vista de QA no se compila en modo release.');
  }
  await startOfflineRetailBackend();
  if (const bool.fromEnvironment('DEMO_ISLAND')) _cycleDemoEvents();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      scrollBehavior: const PremiumScrollBehavior(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const MainShell(),
    ),
  );
}

const _events = [
  ('Venta confirmada', 'Boleta B001-128 · S/ 24.50 con Yape.', 'good'),
  ('Stock bajo', 'Leche fresca: quedan 3 unidades.', 'warn'),
  ('Diferencia en cierre de caja', 'Revisa el arqueo del turno de la tarde.', 'bad'),
];

void _cycleDemoEvents() {
  var i = 0;
  Timer.periodic(const Duration(seconds: 9), (_) {
    final (title, body, severity) = _events[i % _events.length];
    i++;
    pushFixtureAlert(title: title, body: body, severity: severity);
    LiveHub.instance.tick('owner_alerts').value++;
  });
}
