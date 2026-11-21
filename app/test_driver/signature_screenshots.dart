import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final directory = await Directory(
      Platform.environment['SIGNATURE_PREVIEW_DIR'] ?? 'tool/previews/android',
    ).create(recursive: true);
    for (final capture in data!['screenshots'] as List) {
      final name = capture['screenshotName'] as String;
      if (!RegExp(r'^[a-z-]+$').hasMatch(name)) {
        throw FormatException('Nombre de captura inválido');
      }
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(List<int>.from(capture['bytes'] as List));
    }
  },
);
