// Componentes del Design System (Prompt Maestro §11). Pantallas nuevas y reconstruidas usan SOLO estos
// componentes + Theme/DsColors: sin colores sueltos, sin degradados, sin alturas fijas que corten texto.
//
//   DsActionBar   acción principal SIEMPRE visible abajo (respeta área segura y teclado)
//   DsStat        indicador (etiqueta + valor + detalle) en una cuadrícula que no se encima
//   DsSection     título de bloque con acción opcional
//   DsRow         fila de lista tocable (mín. 56 de alto)
//   DsStatus      estado (ok / pendiente / error / info) con texto, nunca solo color
//   DsStateView   carga · vacío · error con "Reintentar"
//   DsLocked      función que el plan o el rol no permiten (dice por qué y no navega)
import 'package:flutter/material.dart';

import 'theme.dart';

/// Barra inferior con la acción principal de la pantalla. Úsala en Scaffold.bottomNavigationBar:
/// no se superpone al contenido, sube con el teclado y respeta el área segura.
class DsActionBar extends StatelessWidget {
  const DsActionBar({super.key, required this.label, required this.icon, required this.onPressed, this.busy = false, this.secondary});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  /// Acción secundaria opcional (texto), a la izquierda.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final ds = DsColors.of(context);
    return Material(
      color: ds.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: ds.line))),
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
          child: Row(children: [
            if (secondary != null) ...[secondary!, const SizedBox(width: Gap.md)],
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: FilledButton.icon(
                  onPressed: busy ? null : onPressed,
                  icon: busy
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: ds.onPrimary))
                      : Icon(icon),
                  label: Text(label, textAlign: TextAlign.center),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class DsSection extends StatelessWidget {
  const DsSection(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)))),
        if (action != null && onAction != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

/// Indicador. En una fila usa [DsStatGrid] para que nunca se encimen en pantallas chicas.
class DsStat extends StatelessWidget {
  const DsStat({super.key, required this.label, required this.value, this.detail, this.tone, this.onTap, this.icon});
  final String label;
  final String value;
  final String? detail;
  final Color? tone;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ds = DsColors.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: tone ?? ds.muted), const SizedBox(width: 6)],
          Expanded(child: Text(label, style: t.textTheme.labelMedium?.copyWith(color: ds.muted), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: tone ?? ds.ink, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
    return Semantics(
      button: onTap != null,
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Material(
        color: ds.surface,
        elevation: t.brightness == Brightness.dark ? 0 : 1.0,
        shadowColor: const Color(0x0A111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: ds.line.withValues(alpha: 0.22))),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// Cuadrícula de indicadores: 2 columnas en teléfono, 4 desde 600 px. Sin alturas fijas.
class DsStatGrid extends StatelessWidget {
  const DsStatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 600 ? 4 : 2;
      final w = (c.maxWidth - Gap.md * (cols - 1)) / cols;
      return Wrap(spacing: Gap.md, runSpacing: Gap.md, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
    });
  }
}

class DsRow extends StatelessWidget {
  const DsRow({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = DsColors.of(context);
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      leading: leading == null ? null : Icon(leading, color: ds.muted),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? (onTap == null ? null : Icon(Icons.chevron_right_rounded, color: ds.muted)),
      onTap: onTap,
    );
  }
}

enum DsTone { ok, pending, error, info }

class DsStatus extends StatelessWidget {
  const DsStatus(this.text, {super.key, this.tone = DsTone.info});
  final String text;
  final DsTone tone;

  @override
  Widget build(BuildContext context) {
    final ds = DsColors.of(context);
    final (c, i) = switch (tone) {
      DsTone.ok => (ds.ok, Icons.check_circle_rounded),
      DsTone.pending => (ds.warn, Icons.schedule_rounded),
      DsTone.error => (ds.bad, Icons.error_rounded),
      DsTone.info => (ds.primaryText, Icons.info_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: c),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700, color: c))),
      ]),
    );
  }
}

/// Carga · vacío · error. Siempre deja una salida (Reintentar o la acción indicada).
class DsStateView extends StatelessWidget {
  const DsStateView.loading({super.key}) : kind = 0, message = 'Cargando…', actionLabel = null, onAction = null;
  const DsStateView.empty({super.key, required this.message, this.actionLabel, this.onAction}) : kind = 1;
  const DsStateView.error({super.key, required this.message, required VoidCallback onRetry})
      : kind = 2, actionLabel = 'Reintentar', onAction = onRetry;

  final int kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ds = DsColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xl, horizontal: Gap.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (kind == 0)
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
        else
          Icon(kind == 2 ? Icons.cloud_off_rounded : Icons.inbox_rounded, size: 32, color: kind == 2 ? ds.bad : ds.muted),
        const SizedBox(height: Gap.md),
        Text(message, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: ds.muted)),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: Gap.md),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ]),
    );
  }
}

/// Función bloqueada por plan o rol: se ve, dice por qué, y no lleva a una pantalla que la base rechazaría.
class DsLocked extends StatelessWidget {
  const DsLocked({super.key, required this.title, required this.reason});
  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final ds = DsColors.of(context);
    return Semantics(
      label: '$title. Bloqueado: $reason',
      excludeSemantics: true,
      child: DsRow(title: title, subtitle: reason, leading: Icons.lock_rounded, trailing: Icon(Icons.lock_outline_rounded, color: ds.muted)),
    );
  }
}
