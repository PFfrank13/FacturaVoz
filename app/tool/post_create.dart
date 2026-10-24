// Ejecutar UNA vez después de `flutter create`:  dart run tool/post_create.dart
// Aplica los ajustes de producción a las carpetas android/, ios/ y web/ generadas.
// Es idempotente: se puede repetir sin duplicar nada.
import 'dart:io';

int problems = 0;

String? read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('AVISO: no existe $path (¿corriste flutter create con esa plataforma?)');
    return null;
  }
  return f.readAsStringSync();
}

void write(String path, String content) => File(path).writeAsStringSync(content);

void android() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  var m = read(manifestPath);
  if (m != null) {
    for (final perm in ['android.permission.INTERNET', 'android.permission.RECORD_AUDIO']) {
      if (!m!.contains('"$perm"')) {
        m = m.replaceFirst('<application', '<uses-permission android:name="$perm"/>\n    <application');
      }
    }
    if (!m!.contains('android:allowBackup')) {
      m = m.replaceFirst('<application', '<application android:allowBackup="false" android:usesCleartextTraffic="false"');
    }
    m = m!.replaceFirstMapped(RegExp(r'android:label="[^"]*"'), (_) => 'android:label="FacturaVoz"');
    if (!m.contains('android.intent.action.VIEW')) {
      const q = '<intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>';
      if (m.contains('</queries>')) {
        m = m.replaceFirst('</queries>', '$q\n    </queries>');
      } else {
        m = m.replaceFirst('</manifest>', '<queries>$q</queries>\n</manifest>');
      }
    }
    write(manifestPath, m);
    stdout.writeln('OK  AndroidManifest.xml');
  }

  // record exige minSdk 23 o superior
  for (final p in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    var g = read(p);
    if (g == null) continue;
    final re = RegExp(r'(minSdk(?:Version)?\s*=?\s*)flutter\.minSdkVersion');
    if (re.hasMatch(g)) {
      g = g.replaceAllMapped(re, (m) => '${m[1]}24');
      write(p, g);
      stdout.writeln('OK  $p (minSdk 24)');
    } else if (!RegExp(r'minSdk(?:Version)?\s*=?\s*(2[4-9]|[3-9]\d)').hasMatch(g)) {
      stderr.writeln('REVISA: fija minSdk >= 23 manualmente en $p');
      problems++;
    }
  }
}

void ios() {
  const path = 'ios/Runner/Info.plist';
  var s = read(path);
  if (s == null) return;
  if (!s.contains('NSMicrophoneUsageDescription')) {
    s = s.replaceFirst(
      RegExp(r'</dict>\s*</plist>'),
      '\t<key>NSMicrophoneUsageDescription</key>\n'
      '\t<string>FacturaVoz usa el micrófono solo para dictar tus facturas.</string>\n</dict>\n</plist>',
    );
  }
  s = s.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (m) => '${m[1]}FacturaVoz${m[2]}',
  );
  write(path, s);
  stdout.writeln('OK  Info.plist');
}

void web() {
  const path = 'web/index.html';
  var s = read(path);
  if (s == null) return;
  s = s.replaceFirstMapped(RegExp(r'<title>[^<]*</title>'), (_) => '<title>FacturaVoz</title>');
  write(path, s);
  stdout.writeln('OK  web/index.html');
}

void cleanup() {
  // `flutter create` puede añadir una prueba de ejemplo que no corresponde a esta app.
  final f = File('test/widget_test.dart');
  if (f.existsSync() && f.readAsStringSync().contains('MyApp')) {
    f.deleteSync();
    stdout.writeln('OK  eliminado test/widget_test.dart de ejemplo');
  }
}

void main() {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Ejecuta este script desde la carpeta app/ (donde está pubspec.yaml).');
    exit(2);
  }
  android();
  ios();
  web();
  cleanup();
  if (problems > 0) {
    stderr.writeln('\nTerminó con $problems aviso(s) que debes revisar a mano.');
    exit(1);
  }
  stdout.writeln('\nListo.');
}
