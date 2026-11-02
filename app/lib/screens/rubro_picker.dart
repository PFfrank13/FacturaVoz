// Elegir o cambiar el rubro (B / B4).
//  - Puerta (gate): empresas que tenían "Otro / personalizado" o que nunca eligieron. Solo el dueño o un administrador
//    eligen; el resto del equipo ve un aviso y puede seguir trabajando (no se bloquea nada ni se pierde ningún dato).
//  - Cambio desde Ajustes: muestra una VISTA PREVIA (barra de abajo, accesos de Inicio y función estrella) antes de
//    confirmar. El cambio es inmediato y no borra datos.
import 'package:flutter/material.dart';

import '../access.dart';
import '../business_templates.dart';
import '../errors.dart';
import '../rubros.dart';
import '../services/rubro_apply.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class RubroPickerScreen extends StatefulWidget {
  const RubroPickerScreen({super.key, this.current, this.gate = false, this.onDone});
  final String? current;
  final bool gate;
  final VoidCallback? onDone;

  @override
  State<RubroPickerScreen> createState() => _RubroPickerScreenState();
}

class _RubroPickerScreenState extends State<RubroPickerScreen> {
  String? _sel;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _sel = rubroFor(widget.current)?.id;
  }

  Future<void> _confirm() async {
    final id = _sel;
    if (id == null) return;
    if (!widget.gate && id == widget.current) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _Preview(spec: rubroFor(id)!));
    if (ok != true) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await applyRubro(id, firstTime: widget.gate);
      Access.instance.rubro = id;
      Haptics.success();
      if (!mounted) return;
      if (widget.onDone != null) {
        widget.onDone!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendly(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final canChoose = Access.instance.isAdmin;
    return Scaffold(
      appBar: AppBar(title: Text(widget.gate ? 'Elige tu rubro' : 'Cambiar de rubro'), automaticallyImplyLeading: !widget.gate),
      body: SafeArea(
        child: !canChoose
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.storefront_rounded, size: 56),
                  const SizedBox(height: 12),
                  Text('El dueño o un administrador debe elegir el rubro del negocio.', textAlign: TextAlign.center, style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Mientras tanto puedes seguir trabajando normal.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: widget.onDone ?? () => Navigator.of(context).pop(), child: const Text('Continuar')),
                ]),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                Text(
                  widget.gate
                      ? 'Ahora cada rubro tiene su propia app: su barra, sus palabras, sus pantallas y su función estrella. Elige el tuyo con cuidado: queda fijo para tu negocio (si algún día necesitas cambiarlo, nosotros lo hacemos sin perder tus datos).'
                      : 'Elige el rubro de tu negocio. Cambian la barra de abajo, las palabras y los accesos. Queda fijo después.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final r in rubros)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pressable(
                      onTap: () {
                        Haptics.select();
                        setState(() => _sel = r.id);
                      },
                      child: AnimatedContainer(
                        duration: Motion.d(context, Motion.fast),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _sel == r.id ? t.colorScheme.primary.withValues(alpha: 0.10) : t.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _sel == r.id ? t.colorScheme.primary : t.colorScheme.outline, width: _sel == r.id ? 2 : 1),
                        ),
                        child: Row(children: [
                          SizedBox(width: 88, child: SectorPhotoTile(
                            rubro: r.id, label: '', selected: _sel == r.id, height: 86,
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.name, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(r.pitch, style: t.textTheme.bodySmall),
                              if (widget.current == r.id) Text('Tu rubro actual', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary)),
                            ]),
                          ),
                          if (_sel == r.id) Icon(Icons.check_circle_rounded, color: t.colorScheme.primary),
                        ]),
                      ),
                    ),
                  ),
                if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error, style: const TextStyle(color: Brand.bad))),
                GradientButton(
                  label: _saving ? 'Guardando…' : (widget.gate ? 'Listo' : 'Ver cómo queda'),
                  icon: Icons.check_rounded,
                  busy: _saving,
                  onPressed: _sel == null || _saving ? null : _confirm,
                ),
              ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.spec});
  final RubroSpec spec;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Así queda: ${spec.name}', style: t.textTheme.titleLarge),
        const SizedBox(height: 12),
        SectorPhotoBanner(rubro: spec.id, title: spec.name, subtitle: spec.pitch, height: 138),
        const SizedBox(height: 14),
        Text('Barra de abajo', style: t.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (i, n) in spec.nav.indexed) ...[
            Chip(label: Text(n.label)),
            if (i == 1) const Chip(avatar: Icon(Icons.mic_rounded, size: 16), label: Text('Micrófono')),
          ],
        ]),
        const SizedBox(height: 10),
        Text('Función estrella', style: t.textTheme.labelLarge),
        Text('${spec.signatureTitle}: ${spec.signaturePitch}'),
        const SizedBox(height: 10),
        Text('Palabras', style: t.textTheme.labelLarge),
        Text('${spec.word('clients')} · ${spec.word('jobs')} · ${spec.word('products')}'),
        const SizedBox(height: 10),
        const Text('Atención: el rubro queda fijo después de confirmar. Solo nosotros podemos cambiarlo luego, sin perder tus datos.'),
        const SizedBox(height: 16),
        Row(children: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          const Spacer(),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar rubro')),
        ]),
      ]),
    )));
  }
}

