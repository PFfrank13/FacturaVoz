import 'package:integration_test/integration_test_driver.dart';

/// Ejecuta los integration_test de Android sobre el VM service del dispositivo
/// sin registrar el comparador de golden files de flutter test + --no-dds.
Future<void> main() => integrationDriver();
