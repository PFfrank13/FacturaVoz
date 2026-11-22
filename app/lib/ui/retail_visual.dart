import 'package:flutter/material.dart';

import 'retail_icon.dart';
import 'theme.dart';
import 'design_tokens.dart';
import 'liquid_glass.dart';

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

  /// Darkest tone of the hero glass, the reference for its text contrast.
  static const heroGlass = Color(0xFF0B1424);

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
    final highContrast = MediaQuery.highContrastOf(context);
    final accent = Color(chapter.accent);
    // Deep glass in both themes, lit by the module's own color: the dark,
    // glowing panels of the visual reference, with readable white type.
    final ink = highContrast ? theme.colorScheme.onSurface : Colors.white;
    final secondary = highContrast ? ink : const Color(0xFFC9D5E4);
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: highContrast ? null : LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color.lerp(accent, Colors.white, .3)!, Color(chapter.ink)],
                ),
                color: highContrast ? theme.colorScheme.primaryContainer : null,
                boxShadow: highContrast ? null : [
                  BoxShadow(color: accent.withValues(alpha: .5), blurRadius: 18, offset: const Offset(0, 6)),
                ],
              ),
              alignment: Alignment.center,
              child: RetailIcon(icon, ink: Colors.white, accent: Color.lerp(accent, Colors.white, .5)!, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(eyebrow.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(
              color: highContrast ? ink : Color.lerp(accent, Colors.white, .25),
              letterSpacing: 1.2, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 18),
          Semantics(header: true, child: Text(title, style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: MediaQuery.sizeOf(context).width < 350 ? 27 : 33,
            height: 1.05, color: ink))),
          const SizedBox(height: 8),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
            child: Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: secondary, height: 1.4))),
        ]),
      ),
      if (footer != null) DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highContrast ? 0 : .06),
          border: Border(top: BorderSide(color: highContrast
              ? theme.colorScheme.outline : Colors.white.withValues(alpha: .12))),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Theme(
            // Footer metrics sit on dark glass in every theme.
            data: highContrast ? theme : theme.copyWith(extensions: [
              ...theme.extensions.values, const RetailOnGlass()]),
            child: footer,
          ),
        ),
      ),
    ]);
    if (highContrast) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(FvTokens.sheetRadius),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: content,
      );
    }
    // No backdrop blur: the aurora under a hero is already a soft field, so
    // blurring it adds nothing visible and only costs frames in long lists.
    return FvLiquidGlass(
      radius: FvTokens.sheetRadius,
      tone: Brightness.dark,
      strength: 2.1,
      blur: 0,
      tint: accent,
      child: Stack(children: [
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ChapterLight(accent)))),
        content,
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
      final onGlass = t.extension<RetailOnGlass>() != null;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: t.textTheme.labelSmall?.copyWith(
            color: onGlass ? const Color(0xFFB4C3D6) : c.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: Gap.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: t.textTheme.titleLarge?.copyWith(
              color: onGlass ? Colors.white : c.ink,
              fontWeight: FontWeight.w800,
              fontSize: 24,
              fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]);
    });
  }
}

/// Marks content placed on the dark glass of a module hero.
class RetailOnGlass extends ThemeExtension<RetailOnGlass> {
  const RetailOnGlass();
  @override
  RetailOnGlass copyWith() => this;
  @override
  RetailOnGlass lerp(RetailOnGlass? other, double t) => this;
}

class _ChapterLight extends CustomPainter {
  const _ChapterLight(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    for (final (center, color, alpha) in [
      (const Alignment(1.15, -1.25), accent, .46),
      (const Alignment(-1.25, 1.2), const Color(0xFF3D8BFF), .22),
    ]) {
      canvas.drawRect(r, Paint()..shader = RadialGradient(
        center: center, radius: 1.15,
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
      ).createShader(r));
    }
    // Concentric arcs echo the voice motif of the home card.
    final c = Offset(size.width + 8, -18);
    for (final (radius, alpha) in const [(34.0, .5), (56.0, .32), (78.0, .18)]) {
      canvas.drawCircle(c, radius, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = accent.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_ChapterLight old) => old.accent != accent;
}
