import 'package:flutter/material.dart';

import 'retail_icon.dart';
import 'theme.dart';
import 'design_tokens.dart';

enum RetailChapter {
  cash(0xFF103C36, 0xFFD5F5E2, 0xFF123D39, 0xFF71E5B7),
  inventory(0xFF1B3060, 0xFFDBE7FF, 0xFF1B3058, 0xFF93B9FF),
  receipts(0xFF113945, 0xFFCFF0F0, 0xFF153B46, 0xFF74DDDA),
  purchases(0xFF492F19, 0xFFFFE2A5, 0xFF473322, 0xFFFFC354),
  credit(0xFF562632, 0xFFFFDCD6, 0xFF4D2633, 0xFFFF9F93),
  reports(0xFF342758, 0xFFE5DEFF, 0xFF30284E, 0xFFBFA9FF);

  const RetailChapter(this.ink, this.paper, this.night, this.accent);
  final int ink, paper, night, accent;
}

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

  /// Color de sección e iconografía bicolor de los módulos comerciales.
  static Widget hero({
    required BuildContext context,
    required String eyebrow,
    required String title,
    required String subtitle,
    required IconData icon,
    required RetailChapter chapter,
    Widget? footer,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final paper = Color(dark ? chapter.night : chapter.paper);
    final ink = dark ? Colors.white : Color(chapter.ink);
    final accent = Color(chapter.accent);
    final secondary = highContrast ? ink : Color.lerp(ink, paper, .13)!;
    final symbolBackground = dark ? Color(chapter.paper) : Color(chapter.ink);
    final symbolInk = dark ? Color(chapter.ink) : Colors.white;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(FvTokens.sheetRadius),
        border: Border.all(color: Color.lerp(paper, ink, highContrast ? .65 : .18)!),
        boxShadow: FvTokens.shadow(theme.brightness),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ColoredBox(
          color: paper,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: symbolBackground, borderRadius: BorderRadius.circular(11),
                  ),
                  child: Padding(padding: const EdgeInsets.all(8), child: RetailIcon(
                    icon, ink: symbolInk, accent: dark ? accent : accent.withValues(alpha: .7), size: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(eyebrow, style: theme.textTheme.labelMedium?.copyWith(
                  color: ink, letterSpacing: .15, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 16),
              Semantics(header: true, child: Text(title, style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: MediaQuery.sizeOf(context).width < 350 ? 26 : 32,
                height: 1.07, color: ink))),
              const SizedBox(height: 8),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
                child: Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: secondary, height: 1.38))),
            ]),
          ),
        ),
        if (footer != null) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: footer,
        ),
      ]),
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
