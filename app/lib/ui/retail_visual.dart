import 'package:flutter/material.dart';

import 'theme.dart';
import 'design_tokens.dart';

/// Componentes de presentacion compartidos por los flujos de Bodega/Tienda.
///
/// Las pantallas comerciales usan los mismos tokens que el shell. Ningun
/// componente fuerza ThemeData.dark, crea metricas falsas ni modifica el flujo.
abstract final class RetailVisual {
  // Compatibilidad para pantallas que importan estas constantes antiguas.
  static const navy = FvTokens.canvasDark;
  static const surface = FvTokens.surfaceDark;
  static const violet = FvTokens.ink; // Alias legado; usar roles del tema.
  static const mint = FvTokens.emerald;

  /// Cabecera editorial compartida por los módulos operativos.
  /// El contraste se deriva del tema activo (claro/oscuro).
  static Widget hero({
    required BuildContext context,
    required String eyebrow,
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? footer,
  }) {
    final c = DsColors.of(context);
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: FvLuxe.editorial(t.brightness),
        borderRadius: BorderRadius.circular(FvTokens.sheetRadius),
        border: Border.all(color: t.brightness == Brightness.dark
            ? const Color(0xFF476174) : Colors.white, width: 1.1),
        boxShadow: FvTokens.shadow(t.brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: FvEngraving(c.primaryText.withValues(alpha: MediaQuery.highContrastOf(context) ? 0 : .09)),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 360 ? 16 : 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: c.primaryText, size: 19),
              const SizedBox(width: Gap.sm),
              Expanded(child: Text(eyebrow, style: t.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600, color: c.primaryText))),
            ]),
            const SizedBox(height: 14),
            Text(title, style: t.textTheme.headlineMedium?.copyWith(
              color: c.ink, fontSize: MediaQuery.sizeOf(context).width < 360 ? 26 : null)),
            const SizedBox(height: 6),
            Text(subtitle, style: t.textTheme.bodyMedium?.copyWith(color: c.muted)),
            if (footer != null) ...[
              const SizedBox(height: 16),
              Divider(color: c.line),
              const SizedBox(height: 14),
              footer,
            ],
          ]),
        ),
      ),
    );
  }

  /// Titulo de una etapa del flujo sin introducir una navegacion secundaria.
  static Widget section({
    required int number,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Builder(builder: (context) {
      final c = DsColors.of(context);
      final t = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 12),
        child: Row(children: [
          Icon(icon, color: c.primaryText, size: 21),
          const SizedBox(width: Gap.md),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleMedium?.copyWith(
                color: c.ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle, style: t.textTheme.bodySmall?.copyWith(color: c.muted)),
            ],
          )),
          const SizedBox(width: Gap.sm),
          Text('$number', style: t.textTheme.labelMedium?.copyWith(color: c.muted)),
        ]),
      );
    });
  }

  /// Superficie operativa consistente en Caja, Fiados y Ventas.
  static Widget panel(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: FvSurfaces.card(Theme.of(context)),
      child: child,
    );
  }

  /// Progreso semantico del proceso de venta, accesible en ambos temas.
  static Widget journey({required int step, required String label}) {
    assert(step >= 1 && step <= 4);
    return Builder(builder: (context) {
      final c = DsColors.of(context);
      final t = Theme.of(context);
      return Semantics(
        label: 'Paso $step de 4: $label',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (var i = 1; i <= 4; i++)
              Expanded(child: Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 5),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? c.primary : c.line,
                    borderRadius: BorderRadius.circular(8)),
                ),
              )),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            Text('Paso $step de 4', style: t.textTheme.labelSmall?.copyWith(
              color: c.primaryText, fontWeight: FontWeight.w800)),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(label, textAlign: TextAlign.end,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(
                color: c.muted, fontWeight: FontWeight.w600))),
          ]),
        ]),
      );
    });
  }

  /// Metricas reales que heredan los colores del tema, no texto blanco fijo.
  static Widget microStat(String label, String value) {
    return Builder(builder: (context) {
      final c = DsColors.of(context);
      final t = Theme.of(context);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: t.textTheme.labelSmall?.copyWith(
            color: c.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: Gap.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: t.textTheme.titleLarge?.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]);
    });
  }
}
