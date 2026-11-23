import 'package:facturavoz/services/payment_listener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interpreta la cola nativa y descarta lo que no es un pago', () {
    final at = DateTime(2026, 11, 23, 10, 0).millisecondsSinceEpoch;
    final list = parseQueued([
      {'key': 'a', 'pkg': 'com.bcp.innovacxion.yapeapp', 'text': 'Confirmación de Pago ¡Yape! JUAN PEREZ te envió un pago por S/ 12.50. El cód. de seguridad es: 527', 'at': at},
      {'key': 'b', 'pkg': 'com.bcp.innovacxion.yapeapp', 'text': 'Tienes una nueva promoción', 'at': at},
      'basura',
    ]);
    expect(list, hasLength(1));
    expect(list.single.notice.app, 'yape');
    expect(list.single.notice.amount, 12.5);
    expect(list.single.notice.payer, 'JUAN PEREZ');
    expect(list.single.at, DateTime(2026, 11, 23, 10, 0));
  });

  test('los códigos de seguridad de 3 dígitos no sirven para evitar duplicados', () {
    expect(dedupeOperation('527'), '');
    expect(dedupeOperation(' 00123456 '), '00123456');
  });

  test('empareja con el cobro: mismo monto y reciente', () {
    final now = DateTime(2026, 11, 23, 10, 5);
    final p = parseQueued([{'text': '¡Yape! ANA te envió un pago por S/ 8.00', 'at': DateTime(2026, 11, 23, 10, 0).millisecondsSinceEpoch}]).single;
    expect(matchesCharge(p, 8, now: now), isTrue);
    expect(matchesCharge(p, 8.01, now: now), isFalse);
    expect(matchesCharge(p, 8, now: now.add(const Duration(minutes: 20))), isFalse);
  });
}
