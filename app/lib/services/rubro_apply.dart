// Aplicar o cambiar el rubro de la empresa SIN perder datos (B4).
// - Estados de trabajos: los del nuevo rubro + los que ya tenías (nada desaparece; los trabajos guardan su estado).
// - Datos extra del cliente: se suman (lo que ya llenaste sigue ahí).
// - Palabras (Trabajo/Cita/Obra…): pasan a ser las del rubro, salvo que tú las hayas cambiado a mano después.
// - Diseño del comprobante y ancho del ticket: solo la primera vez (si ya los elegiste, no se tocan).
import '../business_templates.dart';
import '../models_v2.dart';
import '../rubros.dart';
import 'v2_repo.dart';

/// Resultado puro (se prueba con flutter test): cómo quedan los ajustes al pasar a [rubroId].
OrgSettings mergeRubro(OrgSettings s, String rubroId) {
  final tpl = templateFor(rubroId);
  final oldStatuses = s.jobStatuses.isNotEmpty ? s.jobStatuses : s.template.statuses;
  final keys = {for (final x in tpl.statuses) x.key};
  final statuses = [...tpl.statuses, for (final x in oldStatuses) if (!keys.contains(x.key)) x];
  final fieldKeys = {for (final f in tpl.clientFields) f.key};
  final oldFields = s.clientFields.isNotEmpty ? s.clientFields : s.template.clientFields;
  final fields = [...tpl.clientFields, for (final f in oldFields) if (!fieldKeys.contains(f.key)) f];
  final labels = Map<String, String>.from(s.labels)
    ..remove('job')
    ..remove('jobs');
  return OrgSettings(
    businessType: rubroId,
    simpleMode: s.simpleMode,
    modules: s.modules,
    jobStatuses: statuses,
    clientFields: fields,
    labels: labels,
    onboardingDone: true,
    loyaltyRate: s.loyaltyRate,
    birthdayGreetings: s.birthdayGreetings,
    surveyAuto: s.surveyAuto,
    dailyReport: s.dailyReport,
    dailyReportTo: s.dailyReportTo,
    taxRegime: s.taxRegime,
  );
}

/// Guarda el rubro. Errores (sin permiso, sin conexión) se lanzan para mostrarlos en pantalla.
Future<void> applyRubro(String rubroId, {bool firstTime = false}) async {
  if (rubroFor(rubroId) == null) throw ArgumentError('Rubro desconocido: $rubroId');
  final s = await V2Repo.settings(refresh: true);
  final merged = mergeRubro(s, rubroId);
  await V2Repo.saveSettings(merged);
  if (firstTime) {
    final spec = rubroFor(rubroId)!;
    try {
      final b = await V2Repo.branding();
      final fields = <String, dynamic>{
        if (b['pdf_template'] == null || b['pdf_template'] == 'clasico') 'pdf_template': spec.pdfTemplate,
        if (b['ticket_width'] == null || b['ticket_width'] == 80) 'ticket_width': spec.ticketWidth,
      };
      if (fields.isNotEmpty) await V2Repo.saveBranding(fields);
    } catch (_) {
      // La marca es opcional (solo dueño/admin): si no se puede, el rubro igual queda aplicado.
    }
  }
}
