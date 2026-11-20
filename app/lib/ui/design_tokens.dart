import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';

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
      ? const [Color(0xFF101C2B), Color(0xFF13252D), Color(0xFF101925)]
      : const [Color(0xFFF0F5F3), Color(0xFFF5F7F6), parchment],
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

/// Líneas de grabado inspiradas en la impresión de comprobantes.
class FvEngraving extends CustomPainter {
  const FvEngraving(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width * .94, size.height * .04);
    canvas.rotate(-.56);
    final pen = Paint()
      ..color = color
      ..strokeWidth = .9
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 15; i++) {
      canvas.drawOval(Rect.fromCenter(
        center: Offset.zero, width: 42 + i * 11, height: 94 + i * 14,
      ), pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FvEngraving oldDelegate) => color != oldDelegate.color;
}

/// Tokens visuales globales. No modifica facturación, licencias ni datos.
abstract final class FvTokens {
  static const Color canvas = Color(0xFFF5F6F2);
  static const Color canvasDark = Color(0xFF101B1D);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF1B282A);
  static const Color field = Color(0xFFEDF2EF);
  static const Color fieldDark = Color(0xFF283738);
  static const Color ink = Color(0xFF172337);
  static const Color inkDark = Color(0xFFF5F8FC);
  static const Color muted = Color(0xFF627184);
  static const Color mutedDark = Color(0xFFBEC9D6);
  static const Color emerald = Color(0xFF087F68);
  static const Color emeraldDark = Color(0xFF91DEBF);
  static const Color stroke = Color(0xFFDAE3DD);
  static const Color strokeDark = Color(0xFF384A49);

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
          ? const [Color(0xFF223032), Color(0xFF1B282A)]
          : const [Color(0xFFFFFFFF), Color(0xFFFBFCF9)],
      ) : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? FvTokens.strokeDark : FvTokens.stroke,
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
    final sigma = FvLuxe.glassSigma(theme.platform, blur);
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
