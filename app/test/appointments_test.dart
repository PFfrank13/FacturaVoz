import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/appointments.dart';

void main() {
  readyTests();
  final now = DateTime(2026, 10, 30, 10); // viernes

  test('solo pide confirmación de citas futuras, abiertas y con celular', () {
    final at = DateTime(2026, 10, 31, 15);
    expect(needsConfirmation(at: at, done: false, phone: '987654321', now: now), isTrue);
    expect(needsConfirmation(at: at, done: true, phone: '987654321', now: now), isFalse);
    expect(needsConfirmation(at: at, done: false, phone: ' ', now: now), isFalse);
    expect(needsConfirmation(at: null, done: false, phone: '987654321', now: now), isFalse);
    expect(needsConfirmation(at: DateTime(2026, 10, 30, 9), done: false, phone: '987654321', now: now), isFalse);
  });

  test('whenText', () {
    expect(whenText(DateTime(2026, 10, 30, 18), now: now), 'hoy');
    expect(whenText(DateTime(2026, 10, 31, 9), now: now), 'mañana');
    expect(whenText(DateTime(2026, 11, 3, 9), now: now), 'el lunes 3/11');
  });

  test('mensaje', () {
    final m = confirmationMessage(clientName: 'María Pérez', business: 'Salón Luna', what: 'corte', at: DateTime(2026, 10, 31, 9, 5), now: now);
    expect(m, startsWith('Hola María, te escribe Salón Luna. Te recordamos tu corte mañana a las 09:05.'));
    expect(m, contains('¿Nos confirmas'));
  });
}

void readyTests() {
  test('aviso de listo', () {
    expect(readyStatusKeys, containsAll(['listo', 'instalado']));
    final m = readyMessage(clientName: 'Carlos Ruiz', business: 'Taller Ruiz', what: 'Cambio de aceite');
    expect(m, startsWith('Hola Carlos, te escribe Taller Ruiz: "Cambio de aceite" ya está listo.'));
    expect(readyMessage(clientName: '', business: 'X', what: ''), startsWith('Hola, te escribe X: tu trabajo ya está listo.'));
  });
}
