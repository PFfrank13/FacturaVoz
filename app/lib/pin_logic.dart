// Lógica pura del PIN (sin Flutter): hash, comparación y bloqueo por intentos. Probada en test/pin_logic_test.dart.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const pinLength = 6;
const pbkdf2Iterations = 20000;

/// Tras este número de fallos seguidos se cierra la sesión y se borra el PIN local.
const maxPinFails = 10;

bool isValidPinFormat(String pin) => RegExp('^[0-9]{$pinLength}\$').hasMatch(pin);

Uint8List randomBytes(int n, [Random? rnd]) {
  final r = rnd ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

/// PBKDF2-HMAC-SHA256 de un solo bloque (32 bytes).
Uint8List pbkdf2(String pin, Uint8List salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  var u = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
  final t = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return t;
}

/// Formato guardado: `iteraciones:sal(base64):hash(base64)`.
String encodePin(String pin, {Uint8List? salt, int iterations = pbkdf2Iterations}) {
  final s = salt ?? randomBytes(16);
  return '$iterations:${base64.encode(s)}:${base64.encode(pbkdf2(pin, s, iterations))}';
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

bool verifyEncodedPin(String pin, String encoded) {
  try {
    final parts = encoded.split(':');
    if (parts.length != 3) return false;
    final iterations = int.parse(parts[0]);
    if (iterations < 1 || iterations > 1000000) return false;
    final salt = base64.decode(parts[1]);
    final expected = base64.decode(parts[2]);
    return constantTimeEquals(pbkdf2(pin, Uint8List.fromList(salt), iterations), expected);
  } catch (_) {
    return false;
  }
}

/// Segundos de espera tras `fails` fallos seguidos (0 = sin espera).
int lockoutSeconds(int fails) {
  if (fails < 5) return 0;
  return switch (fails) {
    5 => 30,
    6 => 60,
    7 => 300,
    8 => 900,
    _ => 3600,
  };
}

/// PIN demasiado obvio: dígitos repetidos, escaleras (123456 / 654321) o patrones comunes.
bool isWeakPin(String pin) {
  if (pin.length != pinLength) return true;
  if (pin.split('').toSet().length == 1) return true;
  final d = pin.codeUnits;
  var up = true, down = true;
  for (var i = 1; i < d.length; i++) {
    if (d[i] != d[i - 1] + 1) up = false;
    if (d[i] != d[i - 1] - 1) down = false;
  }
  if (up || down) return true;
  const common = {'121212', '112233', '123123', '123321', '012345', '000123', '147258', '159753', '202020', '696969', '101010'};
  return common.contains(pin);
}

String formatCountdown(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
