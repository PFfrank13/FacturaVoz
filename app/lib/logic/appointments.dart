// Confirmación de citas por WhatsApp: baja las inasistencias (salón, consultorio, taller, servicios técnicos).
// Solo arma el mensaje; la app no envía nada sola ni garantiza que el cliente lo reciba.

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/// ¿Vale la pena pedir confirmación? Cita futura, sin terminar y con celular.
bool needsConfirmation({required DateTime? at, required bool done, required String phone, DateTime? now}) {
  if (at == null || done || phone.trim().isEmpty) return false;
  return at.isAfter(now ?? DateTime.now());
}

String _hora(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "hoy", "mañana" o "el viernes 31/10".
String whenText(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final a = DateTime(at.year, at.month, at.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = a.difference(today).inDays;
  if (diff == 0) return 'hoy';
  if (diff == 1) return 'mañana';
  return 'el ${_dias[at.weekday - 1]} ${at.day}/${at.month}';
}

String confirmationMessage({required String clientName, required String business, required String what, required DateTime at, DateTime? now}) {
  final first = clientName.trim().split(' ').first;
  final cita = what.trim().isEmpty ? 'cita' : what.trim();
  return 'Hola${first.isEmpty ? '' : ' $first'}, te escribe $business. Te recordamos tu $cita ${whenText(at, now: now)} a las ${_hora(at)}. '
      '¿Nos confirmas con un "sí"? Si no puedes venir, avísanos para darle ese horario a otra persona. ¡Gracias!';
}

/// Estados que significan "ya puede recogerlo / ya quedó": ofrecen avisar al cliente.
const readyStatusKeys = {'listo', 'instalado'};

String readyMessage({required String clientName, required String business, required String what}) {
  final first = clientName.trim().split(' ').first;
  final job = what.trim().isEmpty ? 'tu trabajo' : '"${what.trim()}"';
  return 'Hola${first.isEmpty ? '' : ' $first'}, te escribe $business: $job ya está listo. Puedes pasar a recogerlo cuando gustes. ¡Gracias!';
}
