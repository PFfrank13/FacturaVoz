import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Tokens visuales globales. No modifica facturación, licencias ni datos.
abstract final class FvTokens {
  static const Color canvas = Color(0xFFF2F5F8);
  static const Color canvasDark = Color(0xFF070B12);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF191E26);
  static const Color field = Color(0xFFF0F3F7);
  static const Color fieldDark = Color(0xFF242C37);
  static const Color ink = Color(0xFF101C2B);
  static const Color inkDark = Color(0xFFF7FAFF);
  static const Color muted = Color(0xFF526274);
  static const Color mutedDark = Color(0xFFBEC8D5);
  static const Color emerald = Color(0xFF087F67);
  static const Color emeraldDark = Color(0xFF47D7B1);
  static const Color stroke = Color(0xFFDDE4EC);
  static const Color strokeDark = Color(0xFF3B4755);

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
              color: Color(0x0A111827),
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
          ? const [Color(0xFF222B35), Color(0xFF171D26)]
          : const [Color(0xFFFFFFFF), Color(0xFFF8FAFD)],
      ) : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? const Color(0xFF3D4A59) : const Color(0xFFDDE5ED),
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
                const Color(0xFF354152).withValues(alpha: highContrast ? 1 : .88),
                const Color(0xFF19222E).withValues(alpha: highContrast ? 1 : .86),
              ]
            : [
                Colors.white.withValues(alpha: highContrast ? 1 : .90),
                const Color(0xFFEDF5FB).withValues(alpha: highContrast ? 1 : .83),
              ],
        ),
        borderRadius: rounded,
        border: Border.all(
          color: dark ? const Color(0xFF637184) : Colors.white,
          width: 1,
        ),
        boxShadow: FvTokens.shadow(theme.brightness),
      ),
      child: Padding(padding: padding, child: child),
    );
    final sigma = blur.clamp(0.0, 18.0).toDouble();
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
