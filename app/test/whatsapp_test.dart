import 'package:facturavoz/whatsapp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza celulares peruanos', () {
    expect(normalizePhone('987 654 321'), '51987654321');
    expect(normalizePhone('+51 987-654-321'), '51987654321');
    expect(normalizePhone('0051987654321'), '51987654321');
    expect(normalizePhone('51987654321'), '51987654321');
    expect(normalizePhone('12345'), isNull);
    expect(normalizePhone('abc'), isNull);
    expect(normalizePhone('1234567890123456'), isNull);
  });

  test('mensaje de recordatorio', () {
    final m = reminderText(
      clientName: 'Ana',
      businessName: 'Frank SAC',
      number: 'F001-00000007',
      currency: 'PEN',
      total: 118,
      balance: 100,
      dueDate: '2026-10-10',
      today: '2026-10-25',
    );
    expect(m.startsWith('Hola Ana, te escribimos de Frank SAC.'), isTrue);
    expect(m.contains('S/ 100.00'), isTrue);
    expect(m.contains('vencido el 10/10/2026'), isTrue);
  });

  test('el enlace codifica el mensaje', () {
    final u = whatsappUri('51987654321', 'Hola & "adiós" 100%');
    expect(u.host, 'wa.me');
    expect(u.path, '/51987654321');
    expect(u.queryParameters['text'], 'Hola & "adiós" 100%');
    expect(u.toString().contains(' '), isFalse);
  });
}
