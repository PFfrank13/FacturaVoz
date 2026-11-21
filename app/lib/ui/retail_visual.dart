import 'package:flutter/material.dart';

import 'theme.dart';
import 'design_tokens.dart';

enum RetailChapter {
  cash(0xFF123F38, 0xFF25665A, 0xFFABD7B4),
  inventory(0xFF243C67, 0xFF496797, 0xFFB1CEF2),
  receipts(0xFF263E48, 0xFF40636D, 0xFFB1DBDA),
  purchases(0xFF523927, 0xFF82583B, 0xFFE7C9A1),
  credit(0xFF51293F, 0xFF82445B, 0xFFF1C4CB),
  reports(0xFF292B53, 0xFF505382, 0xFFCAC9ED);

  const RetailChapter(this.base, this.light, this.accent);
  final int base;
  final int light;
  final int accent;
  String get asset => 'assets/editorial/$name.webp';
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

  /// Cabecera de cada módulo con su propia paleta y una fotografía local.
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
    final colors = DsColors.of(context);
    final accent = Color(chapter.accent);
    final contrast = MediaQuery.highContrastOf(context);
    final dark = theme.brightness == Brightness.dark;
    final base = Color(chapter.base);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(FvTokens.sheetRadius),
        border: Border.all(
          color: dark ? colors.line : base.withValues(alpha: .16),
        ),
        boxShadow: FvTokens.shadow(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [base, contrast ? base : Color(chapter.light)],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final narrow =
                    box.maxWidth < 332 ||
                    MediaQuery.textScalerOf(context).scale(16) > 20;
                final inset = box.maxWidth < 350 ? 16.0 : 20.0;
                final artSize = narrow
                    ? 72.0
                    : (box.maxWidth * .29).clamp(102.0, 158.0).toDouble();
                final art = Image.asset(
                  chapter.asset,
                  width: artSize,
                  height: artSize,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                );
                final label = Row(
                  children: [
                    Icon(icon, color: accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        eyebrow,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
                final heading = Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontSize: box.maxWidth < 332 ? 26 : null,
                      height: 1.08,
                    ),
                  ),
                );
                return Padding(
                  padding: EdgeInsets.all(inset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (narrow) ...[
                        Row(
                          children: [
                            Expanded(child: label),
                            const SizedBox(width: 8),
                            art,
                          ],
                        ),
                        heading,
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  label,
                                  const SizedBox(height: 14),
                                  heading,
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            art,
                          ],
                        ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                            color: const Color(0xFFF3F5F6),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: footer,
            ),
        ],
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
