import 'package:facturavoz/screens/shell.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'offline_retail.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (!const {'localhost', '127.0.0.1', '::1'}.contains(Uri.base.host)) {
    throw StateError('Esta vista de prueba requiere localhost.');
  }
  await startOfflineRetailBackend();
  // Expose the same accessible controls that screen readers use to Playwright.
  binding.ensureSemantics();
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
