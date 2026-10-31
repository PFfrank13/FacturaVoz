// Corte por mora: no se registra un corte si antes no se registró el aviso al abonado.
// La regla de días es de la app (no una norma): el dueño puede aumentar el plazo con su asesor.
import '../finance.dart' show daysBetween;

/// Días mínimos entre el aviso previo y el corte.
const minNoticeDays = 1;

/// Fecha (AAAA-MM-DD) del último aviso previo guardado en `clients.extra`, o null.
String? noticeDate(Map<String, dynamic> extra) {
  final v = extra['aviso_corte_fecha'];
  return v is String && v.length >= 10 ? v.substring(0, 10) : null;
}

/// Días desde el aviso hasta hoy; null si nunca se avisó.
int? noticeAge(Map<String, dynamic> extra, String today) {
  final d = noticeDate(extra);
  return d == null ? null : daysBetween(d, today);
}

/// Se puede registrar el corte solo con un aviso de hace [minNoticeDays] o más.
bool canCut(Map<String, dynamic> extra, String today) {
  final a = noticeAge(extra, today);
  return a != null && a >= minNoticeDays;
}

String noticeLabel(Map<String, dynamic> extra, String today) {
  final a = noticeAge(extra, today);
  if (a == null) return 'Sin aviso previo';
  if (a <= 0) return 'Avisado hoy';
  return 'Avisado hace $a día${a == 1 ? '' : 's'}';
}

/// Clave del aviso de pensión pendiente (academia), guardado en `clients.extra`.
const pensionNoticeKey = 'aviso_pension_fecha';

/// "Avisado hoy", "Avisado hace N días" o "" si nunca se avisó (para no avisar dos veces sin querer).
String lastNoticeText(Map<String, dynamic> extra, String key, String today) {
  final v = extra[key];
  if (v is! String || v.length < 10) return '';
  final a = daysBetween(v.substring(0, 10), today);
  if (a <= 0) return 'Avisado hoy';
  return 'Avisado hace $a día${a == 1 ? '' : 's'}';
}
