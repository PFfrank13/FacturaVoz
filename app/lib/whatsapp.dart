import 'models.dart';

/// Normaliza un celular a formato internacional para wa.me (solo dígitos).
/// Acepta "987 654 321", "+51 987654321", "51987654321". null = número no válido.
String? normalizePhone(String raw, {String defaultCountry = '51'}) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 9 && d.startsWith('9')) d = '$defaultCountry$d'; // celular peruano sin código
  if (d.length < 10 || d.length > 15) return null;
  return d;
}

/// Mensaje de recordatorio de cobro (sin datos sensibles: solo lo que el cliente ya conoce).
String reminderText({
  required String clientName,
  required String businessName,
  required String number,
  required String currency,
  required double total,
  required double balance,
  String? dueDate,
  required String today,
}) {
  final overdue = dueDate != null && dueDate.compareTo(today) < 0;
  final b = StringBuffer('Hola ${clientName.trim().isEmpty || clientName == '—' ? '' : clientName.trim()}'.trimRight())
    ..write(', te escribimos de ${businessName.trim().isEmpty ? 'nuestro negocio' : businessName.trim()}. ')
    ..write('Te recordamos que el comprobante $number por ${money(total, currency)} tiene un saldo pendiente de ${money(balance, currency)}');
  if (dueDate != null) b.write(overdue ? ', vencido el ${displayDate(dueDate)}' : ', con vencimiento el ${displayDate(dueDate)}');
  b.write('. ¡Gracias!');
  return b.toString();
}

/// Enlace https://wa.me/<número>?text=<mensaje> (el mensaje se codifica).
Uri whatsappUri(String phoneDigits, String message) => Uri.https('wa.me', '/$phoneDigits', {'text': message});
