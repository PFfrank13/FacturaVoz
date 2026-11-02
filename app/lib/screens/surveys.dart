// Encuestas de satisfacción (Fase 8 · módulo 21): enlace de 1 a 5 estrellas que el cliente responde sin cuenta.
// Las respuestas bajas (≤ 2) llegan como alerta al dueño para actuar rápido.
import 'package:flutter/material.dart';

import '../access.dart';
import '../models_v2.dart';
import '../services/live.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'client_profile.dart' show shortDateTime;
import 'invoice_detail.dart';

class SurveysScreen extends StatefulWidget {
  const SurveysScreen({super.key});

  @override
  State<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends State<SurveysScreen> with LiveReload<SurveysScreen> {
  List<SurveyRow>? _rows;
  OrgSettings? _s;
  String? _error;

  @override
  List<String> get liveTables => const ['surveys', 'org_settings'];

  @override
  Future<void> reloadLive() => _load();

  @override
  void initState() {
    super.initState();
    _rows = LiveCache.get<List<SurveyRow>>('surveys.rows');
    _s = LiveCache.get<OrgSettings>('surveys.s');
    startLive();
    _load();
  }

  @override
  void dispose() {
    stopLive();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await V2Repo.surveys();
      final s = await V2Repo.settings(refresh: true);
      LiveCache.put('surveys.rows', r);
      LiveCache.put('surveys.s', s);
      if (mounted) {
        setState(() {
          _rows = r;
          _s = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = V2Repo.missingHint(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = _rows ?? const <SurveyRow>[];
    final answered = rows.where((r) => r.score != null).toList();
    final avg = answered.isEmpty ? 0.0 : answered.fold(0, (a, r) => a + r.score!) / answered.length;
    final happy = answered.where((r) => r.score! >= 4).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Encuestas')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _rows == null
              ? const SkeletonList()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    Reveal(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(26)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Satisfacción', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.85))),
                              Text(answered.isEmpty ? '—' : '${avg.toStringAsFixed(1)} ★', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                              Text('${answered.length} respuestas de ${rows.length} enviadas', style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.9))),
                            ]),
                          ),
                          if (answered.isNotEmpty)
                            ProgressRing(
                              value: happy / answered.length,
                              size: 72,
                              stroke: 8,
                              color: Colors.white,
                              child: Text('${(happy / answered.length * 100).round()}%', style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_s != null && Access.instance.can('settings'))
                      SwitchListTile(
                        value: _s!.surveyAuto,
                        onChanged: (v) async {
                          await V2Repo.saveSettingsFields({'survey_auto': v}).catchError((_) {});
                          _load();
                        },
                        title: const Text('Ofrecer la encuesta al enviar cada comprobante'),
                        subtitle: const Text('Se agrega el enlace al mensaje de WhatsApp.'),
                      ),
                    Text('Para enviar una encuesta: abre un comprobante → Compartir → "Encuesta".', style: t.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    if (rows.isEmpty) const EmptyState(title: 'Aún sin encuestas', body: 'Pregunta a tus clientes cómo les fue: mejoras y consigues recomendaciones.'),
                    for (final r in rows)
                      ListTile(
                        leading: Text(r.score == null ? '⏳' : '★' * r.score!, style: TextStyle(color: (r.score ?? 5) <= 2 ? Brand.bad : Brand.warn, fontSize: 16)),
                        title: Text(r.comment.isEmpty ? (r.score == null ? 'Sin responder' : 'Sin comentario') : r.comment),
                        subtitle: Text(shortDateTime((r.answeredAt ?? r.createdAt) ?? DateTime.now())),
                        onTap: r.invoiceId == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: r.invoiceId!))),
                      ),
                  ]),
                ),
    );
  }
}
