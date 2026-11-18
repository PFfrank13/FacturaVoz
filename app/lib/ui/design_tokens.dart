import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Tokens visuales globales. No modifica facturación, licencias ni datos.
abstract final class FvTokens {
  static const Color canvas = Color(0xFFF5F5F7);
  static const Color canvasDark = Color(0xFF000000);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color field = Color(0xFFF3F4F6);
  static const Color fieldDark = Color(0xFF29292B);
  static const Color ink = Color(0xFF111827);
  static const Color inkDark = Color(0xFFF9FAFB);
  static const Color muted = Color(0xFF6B7280);
  static const Color mutedDark = Color(0xFFB6B6BD);
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDark = Color(0xFF34D399);
  static const Color stroke = Color(0xFFE9E9EE);
  static const Color strokeDark = Color(0xFF353539);

  static const double cardRadius = 20;
  static const double sheetRadius = 28;
  static const double fieldRadius = 14;
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

/// Cristal sólo en superficies flotantes; no en todas las celdas del catálogo.
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
    // Si se solicita alto contraste, evitamos transparencia y blur para
    // garantizar legibilidad y reducir trabajo gráfico.
    final highContrast = MediaQuery.highContrastOf(context);
    final background = dark ? FvTokens.surfaceDark : FvTokens.surface;
    final alpha = highContrast ? 1.0 : (dark ? 0.79 : 0.73);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: highContrast ? 0 : blur,
            sigmaY: highContrast ? 0 : blur,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: (dark ? Colors.white : Colors.white)
                    .withValues(alpha: dark ? 0.18 : 0.82),
              ),
              boxShadow: FvTokens.shadow(theme.brightness),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
