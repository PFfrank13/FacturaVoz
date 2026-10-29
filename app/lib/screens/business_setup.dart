// Presentación v2.0 (Fase 1): animada, saltable y se puede volver a abrir desde Ajustes.
// Pregunta el TIPO DE NEGOCIO (10 plantillas + Otro) y si prefiere la app SIMPLE (Vender, Clientes, Cobrar, Ajustes)
// o COMPLETA. La plantilla solo ordena la pantalla: ninguna función se borra ni se bloquea.
import 'package:flutter/material.dart';

import '../business_templates.dart';
import '../models_v2.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key, required this.onDone, this.reopened = false});

  /// Se llama al terminar o al saltar (la próxima vez no se vuelve a mostrar sola).
  final VoidCallback onDone;
  final bool reopened;

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _pages = PageController();
  int _page = 0;
  String _type = 'otro';
  bool _simple = true;
  bool _saving = false;
  OrgSettings? _settings;

  @override
  void initState() {
    super.initState();
    V2Repo.settings(refresh: true).then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        _type = s.businessType;
        _simple = s.simpleMode;
      });
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int p) {
    Haptics.select();
    setState(() => _page = p);
    _pages.animateToPage(p, duration: Motion.d(context, Motion.slow), curve: Motion.emphasized);
  }

  Future<void> _finish({bool skipped = false}) async {
    setState(() => _saving = true);
    final s = _settings ?? OrgSettings();
    if (!skipped) {
      s.businessType = _type;
      s.simpleMode = _simple;
    }
    s.onboardingDone = true;
    try {
      await V2Repo.saveSettings(s);
    } catch (_) {
      // Sin la migración v2 (o sin permiso de administrador) la presentación igual se cierra.
    }
    if (!mounted) return;
    Haptics.success();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: Motion.d(context, Motion.medium),
                  curve: Motion.standard,
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: i <= _page ? t.colorScheme.primary : t.colorScheme.outline, borderRadius: BorderRadius.circular(99)),
                ),
              const Spacer(),
              TextButton(onPressed: _saving ? null : () => _finish(skipped: !widget.reopened), child: Text(widget.reopened ? 'Cerrar' : 'Saltar')),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [_welcome(context), _types(context), _mode(context)],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final t = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 12),
      const Reveal(child: Center(child: BrandMark(size: 76))),
      const SizedBox(height: 26),
      Reveal(index: 1, child: Text('Tu negocio, ordenado a tu manera', textAlign: TextAlign.center, style: t.textTheme.headlineSmall)),
      const SizedBox(height: 10),
      Reveal(
        index: 2,
        child: Text(
          'En 2 pasos te mostramos primero lo que tu negocio usa. Todo lo demás sigue disponible en "Todas las funciones".',
          textAlign: TextAlign.center,
          style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ),
      const SizedBox(height: 26),
      for (final (i, (icon, text)) in const [
        (Icons.mic_rounded, 'Factura hablando: "boleta para Rosa, 2 kilos de arroz a 4 soles"'),
        (Icons.people_alt_rounded, 'Cada cliente con su ficha: deuda, historial, fotos y WhatsApp'),
        (Icons.auto_awesome_rounded, 'Un copiloto que te avisa a quién cobrar y cuánto guardar para SUNAT'),
      ].indexed)
        Reveal(
          index: 3 + i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(icon, color: t.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: t.textTheme.bodyMedium)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 14),
      Reveal(index: 6, child: GradientButton(label: 'Empezar', icon: Icons.arrow_forward_rounded, onPressed: () => _go(1))),
    ]);
  }

  Widget _types(BuildContext context) {
    final t = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Qué tipo de negocio tienes?', style: t.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Puedes cambiarlo cuando quieras en Ajustes.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 560 ? 3 : 2;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.92),
            itemCount: businessTemplates.length,
            itemBuilder: (context, i) {
              final b = businessTemplates[i];
              final on = b.id == _type;
              return Reveal(
                index: i < 8 ? i : 8,
                child: Pressable(
                  onTap: () {
                    Haptics.select();
                    setState(() => _type = b.id);
                  },
                  child: AnimatedContainer(
                    duration: Motion.d(context, Motion.fast),
                    curve: Motion.shadow,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: on ? t.colorScheme.primary.withValues(alpha: 0.10) : t.colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: on ? t.colorScheme.primary : t.colorScheme.outline, width: on ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(b.icon, color: t.colorScheme.primary, size: 28),
                        const Spacer(),
                        AnimatedScale(
                          scale: on ? 1 : 0,
                          duration: Motion.d(context, Motion.medium),
                          curve: Motion.spring,
                          child: Icon(Icons.check_circle_rounded, color: t.colorScheme.primary),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Expanded(child: Text(b.pitch, maxLines: 4, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall)),
                    ]),
                  ),
                ),
              );
            },
          );
        }),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          TextButton(onPressed: () => _go(0), child: const Text('Atrás')),
          const SizedBox(width: 8),
          Expanded(child: GradientButton(label: 'Continuar', icon: Icons.arrow_forward_rounded, onPressed: () => _go(2))),
        ]),
      ),
    ]);
  }

  Widget _mode(BuildContext context) {
    final t = Theme.of(context);
    final tpl = templateFor(_type);
    Widget option(bool simple, String title, String body, IconData icon) {
      final on = _simple == simple;
      return Pressable(
        onTap: () {
          Haptics.select();
          setState(() => _simple = simple);
        },
        child: AnimatedContainer(
          duration: Motion.d(context, Motion.fast),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? t.colorScheme.primary.withValues(alpha: 0.10) : t.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: on ? t.colorScheme.primary : t.colorScheme.outline, width: on ? 2 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: t.colorScheme.primary, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: t.textTheme.bodySmall),
              ]),
            ),
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: t.colorScheme.primary),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('¿Cómo quieres ver la app?', style: t.textTheme.headlineSmall),
      const SizedBox(height: 16),
      option(true, 'Simple', 'Solo 4 botones: Vender, Clientes, Cobrar y Ajustes. Ideal para empezar.', Icons.looks_4_rounded),
      option(false, 'Completa', 'Inicio con resumen, Vender, Clientes, Cobrar y pagar, y Mi negocio con reportes.', Icons.dashboard_rounded),
      if (tpl.tips.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Para ${tpl.name.toLowerCase()}:', style: t.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final tip in tpl.tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.tips_and_updates_rounded, size: 18, color: Brand.warn),
              const SizedBox(width: 8),
              Expanded(child: Text(tip, style: t.textTheme.bodyMedium)),
            ]),
          ),
      ],
      const SizedBox(height: 18),
      GradientButton(label: _saving ? 'Guardando…' : '¡Listo!', icon: Icons.check_rounded, busy: _saving, onPressed: _saving ? null : _finish),
      TextButton(onPressed: () => _go(1), child: const Text('Atrás')),
    ]);
  }
}
