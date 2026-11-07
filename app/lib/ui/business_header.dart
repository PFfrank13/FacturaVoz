import 'retail_identity.dart';
import 'package:flutter/material.dart';
import '../models.dart' show money;
import 'theme.dart';
import 'widgets.dart' show sectorIcon, sectorShortName;

/// Identidad operativa: contexto primero, cifras verificadas y una acción clara.
/// No carga datos ni interpreta licencias; recibe únicamente datos autorizados.
class BusinessHeader extends StatelessWidget {
  const BusinessHeader({super.key, required this.name, required this.title,
    required this.subtitle, required this.rubro, required this.onMenu,
    this.total, this.count, this.currency = 'PEN', this.period = 'Ventas de hoy',
    this.onGoal, this.error = false});
  final String name, title, subtitle, currency, period;
  final String? rubro;
  final double? total;
  final int? count;
  final VoidCallback onMenu;
  final VoidCallback? onGoal;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ink = t.colorScheme.onSurface;
    return SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const RetailMark(size: 32),
          const SizedBox(width: 10),
          Expanded(child: Text(name.isEmpty ? 'Mi negocio' : name,
            style: t.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
          IconButton.filledTonal(onPressed: onMenu, tooltip: 'Herramientas de mi negocio', icon: const Icon(Icons.grid_view_rounded, size: 20)),
        ]),
        const SizedBox(height: 28),
        Row(children: [Icon(sectorIcon(rubro), size: 16, color: t.colorScheme.primary),
          const SizedBox(width: 8), Expanded(child: Text(sectorShortName(rubro).toUpperCase(),
            style: t.textTheme.labelSmall?.copyWith(letterSpacing: 1.5, color: t.colorScheme.primary)))]),
        const SizedBox(height: 12),
        Text(title, style: t.textTheme.headlineMedium?.copyWith(fontSize: 32, height: 1.12, letterSpacing: -1.1, color: ink)),
        const SizedBox(height: 10),
        Text(subtitle, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (total != null || error) ...[
          const SizedBox(height: 24),
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.colorScheme.outline), bottom: BorderSide(color: t.colorScheme.outline))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(period, style: t.textTheme.labelMedium),
              const SizedBox(height: 8),
              Text(error ? 'No disponible' : money(total!, currency),
                style: t.textTheme.displaySmall?.copyWith(fontSize: 36, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (!error && count != null) Text('$count operaciones emitidas', style: t.textTheme.bodySmall),
                if (onGoal != null) TextButton.icon(onPressed: onGoal, icon: const Icon(Icons.flag_outlined, size: 16), label: const Text('Meta del mes')),
              ]),
            ])),
        ],
      ]),
    ));
  }
}

class TaskAction extends StatelessWidget {
  const TaskAction({super.key, required this.label, required this.icon, required this.onTap, this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(color: primary ? t.colorScheme.primary : t.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: BorderSide(color: primary ? t.colorScheme.primary : t.colorScheme.outline)),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Icon(icon, size: 22, color: primary ? t.colorScheme.onPrimary : t.colorScheme.primary),
          const SizedBox(width: 12), Expanded(child: Text(label, style: t.textTheme.labelLarge?.copyWith(color: primary ? t.colorScheme.onPrimary : t.colorScheme.onSurface))),
        ]))));
  }
}
