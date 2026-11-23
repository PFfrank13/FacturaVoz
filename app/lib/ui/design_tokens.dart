import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// Paleta editorial con brillo controlado y color solo donde comunica una acción.
/// No utiliza materiales propietarios de UIKit.
abstract final class FvLuxe {
  static const editorialFont = 'DM Serif Text';
  static const forest = Color(0xFF103F38);
  static const parchment = Color(0xFFF8F7F1);
  static const mintInk = Color(0xFFA6E2CD);

  static double glassSigma(TargetPlatform platform, double requested) {
    final limit = kIsWeb ? 6.0 : platform == TargetPlatform.iOS ? 18.0 : 10.0;
    return requested.clamp(0.0, limit);
  }

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
      ? const [Color(0xFF0A1B2C), Color(0xFF07111F), Color(0xFF0D0F22)]
      : const [Color(0xFFDDF7EE), Color(0xFFEFF5FC), Color(0xFFF8EEF2)],
    stops: const [0, .50, 1],
  );

  static LinearGradient editorial(Brightness brightness) => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: brightness == Brightness.dark
      ? const [Color(0xFF1A3441), Color(0xFF1C2D46)]
      : const [Color(0xFFE1EFE7), parchment],
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
  static const Color canvas = Color(0xFFF2F6FB);
  static const Color canvasDark = Color(0xFF060B14);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF101B2C);
  static const Color field = Color(0xFFE8EFF7);
  static const Color fieldDark = Color(0xFF17253B);
  static const Color ink = Color(0xFF0D1B2E);
  static const Color inkDark = Color(0xFFF3F8FF);
  static const Color muted = Color(0xFF55657A);
  static const Color mutedDark = Color(0xFFAEBDD1);
  static const Color emerald = Color(0xFF087F68);
  static const Color emeraldDark = Color(0xFF5BEBBE);
  static const Color stroke = Color(0xFFDAE4EF);
  static const Color strokeDark = Color(0xFF24344D);

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
              color: Color(0x091B332A),
              blurRadius: 14,
              offset: Offset(0, 3),
            )];

  static Color positive(Brightness brightness) =>
      brightness == Brightness.dark ? emeraldDark : emerald;
}

/// Superficies sólidas para tarjetas: sensación de profundidad sin desenfocar
/// cada fila. Comparte el aspecto entre todos los módulos y mantiene FPS.
abstract final class FvSurfaces {
  /// A glass pane without backdrop blur: over the aurora a blur adds nothing
  /// visible, so lists of cards stay fast while matching the liquid glass.
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
          ? const [Color(0xB31A2A42), Color(0x9E0D1828)]
          : const [Color(0xE6FFFFFF), Color(0xB8FFFFFF)],
      ) : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? const Color(0x2EFFFFFF) : Colors.white,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x66000000) : const Color(0x1A1B3550),
          blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 10),
        ),
      ],
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
  Widget build(BuildContext context) => FvLiquidGlass(
    radius: radius,
    padding: padding,
    blur: blur * 1.6,
    child: child,
  );
}
