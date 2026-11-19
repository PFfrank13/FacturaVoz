import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Paleta editorial con brillo controlado y color solo donde comunica una acción.
/// No utiliza materiales propietarios de UIKit.
abstract final class FvLuxe {
  static const jade = Color(0xFF087F68);
  static const jadeSoft = Color(0xFFE0F5E9);
  static const blue = Color(0xFF2864A2);
  static const blueSoft = Color(0xFFE6F1FF);
  static const gold = Color(0xFFAD6A23);
  static const goldSoft = Color(0xFFFFEFDA);
  static const lilac = Color(0xFF7461A8);
  static const lilacSoft = Color(0xFFF0EBFD);

  static LinearGradient ambient(Brightness brightness) => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: brightness == Brightness.dark
      ? const [Color(0xFF101C2B), Color(0xFF13252D), Color(0xFF101925)]
      : const [Color(0xFFE8F4FF), Color(0xFFF1F9FB), Color(0xFFF5F7FC)],
    stops: const [0, .50, 1],
  );

  static LinearGradient editorial(Brightness brightness) => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: brightness == Brightness.dark
      ? const [Color(0xFF1A3441), Color(0xFF1C2D46)]
      : const [Color(0xFFDCF5EA), Color(0xFFE7F1FF)],
  );

  static LinearGradient productBackdrop(Brightness brightness) => LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: brightness == Brightness.dark
      ? const [Color(0xFF243648), Color(0xFF192938)]
      : const [Color(0xFFE7F4F3), Color(0xFFF4F8FE)],
  );
}

/// Tokens visuales globales. No modifica facturación, licencias ni datos.
abstract final class FvTokens {
  static const Color canvas = Color(0xFFF2F7FC);
  static const Color canvasDark = Color(0xFF0E1723);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF182432);
  static const Color field = Color(0xFFEBF2F8);
  static const Color fieldDark = Color(0xFF253345);
  static const Color ink = Color(0xFF172337);
  static const Color inkDark = Color(0xFFF5F8FC);
  static const Color muted = Color(0xFF627184);
  static const Color mutedDark = Color(0xFFBEC9D6);
  static const Color emerald = Color(0xFF087F68);
  static const Color emeraldDark = Color(0xFF91DEBF);
  static const Color stroke = Color(0xFFDDE7F1);
  static const Color strokeDark = Color(0xFF344659);

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
          ? const [Color(0xFF202D3B), Color(0xFF182432)]
          : const [Color(0xFFFFFFFF), Color(0xFFF8FBFF)],
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
                const Color(0xFF30475C).withValues(alpha: highContrast ? 1 : .62),
                const Color(0xFF1A2937).withValues(alpha: highContrast ? 1 : .46),
              ]
            : [
                Colors.white.withValues(alpha: highContrast ? 1 : .62),
                const Color(0xFFEAF5FC).withValues(alpha: highContrast ? 1 : .40),
              ],
        ),
        borderRadius: rounded,
        border: Border.all(
          color: dark ? const Color(0xFF7895A8) : Colors.white,
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
