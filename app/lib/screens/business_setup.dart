// Presentación v2.0 (Fase 1): animada, saltable y se puede volver a abrir desde Ajustes.
// Preferencia comercial aditiva; no altera el rubro histórico de licencia.
// Los permisos siguen procediendo de los contratos existentes del Hub.
import 'package:flutter/material.dart';

import '../app_state.dart';
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
  String _type = '';
  bool _easy = AppState.instance.easyMode.value;
  bool _saving = false;
  OrgSettings? _settings;

  @override
  void initState() {
    super.initState();
    V2Repo.settings(refresh: true).then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        _type = s.labels['commercial_offer'] ?? 'both';
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
    try {
      if (!skipped) s.labels['commercial_offer'] = _type;
      s.onboardingDone = true;
      await V2Repo.saveSettings(s);
      await AppState.instance.setEasyMode(_easy);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
          Text('No se guardó la configuración. Revisa la conexión y vuelve a intentarlo.')));
      }
      return;
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
                  decoration: BoxDecoration(color: i <= _page ? t.colorScheme.primary : t.colorScheme.outline, borderRadius: BorderRadius.circular(Radii.pill)),
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
      const Reveal(child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        child: SizedBox(height: 188, child: Stack(fit: StackFit.expand, children: [
          Image(image: AssetImage('assets/photos/welcome_scene.webp'), fit: BoxFit.cover),
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            colors: [Color(0xC9101746), Color(0x25101746)],
            begin: Alignment.centerLeft, end: Alignment.centerRight))),
          Align(alignment: Alignment.centerLeft, child: Padding(
            padding: EdgeInsets.all(22), child: BrandMark(size: 72))),
        ])),
      )),
      const SizedBox(height: 22),
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

  Widget _types(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
    Text('¿Qué vende tu negocio?', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('Productos, servicios o ambos. Esta preferencia no modifica tu licencia ni tus registros anteriores.'),
    const SizedBox(height: 16),
    for (final entry in const [('products', 'Productos', Icons.inventory_2_outlined),
      ('services', 'Servicios', Icons.handyman_outlined), ('both', 'Productos y servicios', Icons.storefront_outlined)])
      Card(child: ListTile(leading: Icon(entry.$3), title: Text(entry.$2),
        trailing: Icon(_type == entry.$1 ? Icons.radio_button_checked : Icons.radio_button_off),
        onTap: () => setState(() => _type = entry.$1))),
    const SizedBox(height: 16),
    GradientButton(label: 'Continuar', icon: Icons.arrow_forward_rounded,
      onPressed: _type.isEmpty ? null : () => _go(2)),
    TextButton(onPressed: () => _go(0), child: const Text('Atrás')),
  ]);

  Widget _mode(BuildContext context) {
    final t = Theme.of(context);
    const tips = ['Un servicio no necesita existencias físicas.', 'Revisa los datos comerciales, moneda e impuestos en Configuración antes de emitir.'];
    Widget option(bool easy, String title, String body, IconData icon) {
      final on = _easy == easy;
      return Pressable(
        onTap: () {
          Haptics.select();
          setState(() => _easy = easy);
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
      option(false, 'Normal', 'Inicio, ventas, caja y herramientas. Conserva el dictado de comprobantes.', Icons.dashboard_rounded),
      option(true, 'Fácil', 'Lo mismo, con letras y botones más grandes. Lo puedes cambiar en Ajustes.', Icons.text_increase_rounded),
      if (tips.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Antes de empezar:', style: t.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final tip in tips)
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
