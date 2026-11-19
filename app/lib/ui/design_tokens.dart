import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Tokens visuales globales. No modifica facturación, licencias ni datos.
abstract final class FvTokens {
  static const Color canvas = Color(0xFFF5F5F7);
  static const Color canvasDark = Color(0xFF0A0A0C);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF161618);
  static const Color field = Color(0xFFF0F0F2);
  static const Color fieldDark = Color(0xFF242427);
  static const Color ink = Color(0xFF111114);
  static const Color inkDark = Color(0xFFF5F5F7);
  static const Color muted = Color(0xFF626268);
  static const Color mutedDark = Color(0xFFACACB3);
  static const Color emerald = Color(0xFF317B65);
  static const Color emeraldDark = Color(0xFF85C4AC);
  static const Color stroke = Color(0xFFE4E4E8);
  static const Color strokeDark = Color(0xFF333337);

  static const double cardRadius = 22;
  static const double sheetRadius = 30;
  static const double fieldRadius = 16;
  static const double mobileBreakpoint = 700;
  static const double cartBreakpoint = 900;
  static const double desktopCartWidth = 320;

  static const Duration micro = Duration(milliseconds: 170);
  static const Duration transition = Duration(milliseconds: 260);

  static bool isWide(double width) =>
      width.isFinite && width >= mobileBreakpoint;

  /// Calculado sobre el ancho útil DESPUÉS de rail y panel de carrito.
  static int productColumns(double width) {
    if (!width.isFinite || width <= 0 || width < mobileBreakpoint) return 2;
    if (width < 860) return 3;
    if (width < 1100) return 4;
    return 5;
  }

  static List<BoxShadow> shadow(Brightness brightness) =>
      brightness == Brightness.dark
          ? const []
          : const [BoxShadow(
              color: Color(0x0C101014),
              blurRadius: 24,
              offset: Offset(0, 8),
            )];

  static Color positive(Brightness brightness) =>
      brightness == Brightness.dark ? emeraldDark : emerald;
}

/// Superficies sólidas para tarjetas: sensación de profundidad sin desenfocar
/// cada fila. Comparte el aspecto entre todos los módulos y mantiene FPS.
abstract final class FvSurfaces {
  static BoxDecoration card(ThemeData theme, {
    Color? color,
    double radius = FvTokens.cardRadius,
  }) {
    final dark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: color,
      gradient: color == null ? LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
          ? const [Color(0xFF242427), Color(0xFF161618)]
          : const [Color(0xFFFFFFFF), Color(0xFFFCFCFD)],
      ) : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? const Color(0xFF343438) : const Color(0xFFE8E8EB),
        width: .9,
      ),
      boxShadow: FvTokens.shadow(theme.brightness),
    );
  }
}

/// Cristal acotado a navegación, controles flotantes y cabeceras.
/// Evita el blur completamente si el usuario activa alto contraste.
/// No afirma reproducir el material nativo Liquid Glass de UIKit.
class FvGlassSurface extends StatelessWidget {
  const FvGlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = FvTokens.sheetRadius,
    this.blur = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final rounded = BorderRadius.circular(radius);
    final layer = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
            ? [
                const Color(0xFF38383E).withValues(alpha: highContrast ? 1 : .62),
                const Color(0xFF18181C).withValues(alpha: highContrast ? 1 : .53),
              ]
            : [
                Colors.white.withValues(alpha: highContrast ? 1 : .74),
                const Color(0xFFF5F5F8).withValues(alpha: highContrast ? 1 : .61),
              ],
        ),
        borderRadius: rounded,
        border: Border.all(
          color: dark ? const Color(0xFF5B5B62) : Colors.white,
          width: 1,
        ),
        boxShadow: FvTokens.shadow(theme.brightness),
      ),
      child: Padding(padding: padding, child: child),
    );
    final sigma = blur.clamp(0.0, 20.0).toDouble();
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: rounded,
        child: highContrast || sigma == 0
          ? layer
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: layer,
            ),
      ),
    );
  }
}
