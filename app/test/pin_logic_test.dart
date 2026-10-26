import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/pin_logic.dart';

void main() {
  test('hash verifica el PIN correcto y rechaza otros', () {
    final enc = encodePin('483920', iterations: 100);
    expect(verifyEncodedPin('483920', enc), isTrue);
    expect(verifyEncodedPin('483921', enc), isFalse);
    expect(verifyEncodedPin('', enc), isFalse);
  });

  test('la sal hace distintos los hashes del mismo PIN', () {
    expect(encodePin('483920', iterations: 100), isNot(encodePin('483920', iterations: 100)));
  });

  test('PBKDF2 es determinista con la misma sal', () {
    final salt = Uint8List.fromList(List.generate(16, (i) => i));
    expect(pbkdf2('123456', salt, 50), pbkdf2('123456', salt, 50));
    expect(pbkdf2('123456', salt, 50), isNot(pbkdf2('123457', salt, 50)));
  });

  test('formato inválido no lanza y devuelve false', () {
    expect(verifyEncodedPin('123456', 'basura'), isFalse);
    expect(verifyEncodedPin('123456', 'x:y:z'), isFalse);
  });

  test('comparación en tiempo constante', () {
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });

  test('bloqueo escalonado', () {
    expect(lockoutSeconds(4), 0);
    expect(lockoutSeconds(5), 30);
    expect(lockoutSeconds(6), 60);
    expect(lockoutSeconds(7), 300);
    expect(lockoutSeconds(9), 3600);
  });

  test('PIN débil', () {
    for (final p in ['111111', '123456', '654321', '121212', '12345']) {
      expect(isWeakPin(p), isTrue, reason: p);
    }
    expect(isWeakPin('483920'), isFalse);
  });

  test('formato del PIN y cuenta regresiva', () {
    expect(isValidPinFormat('483920'), isTrue);
    expect(isValidPinFormat('48392'), isFalse);
    expect(isValidPinFormat('48392a'), isFalse);
    expect(formatCountdown(65), '1:05');
  });
}
