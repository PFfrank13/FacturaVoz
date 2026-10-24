import 'package:flutter/material.dart';

/// Sistema de diseño de FacturaVoz.
/// Índigo "tinta" como color de marca, oro "sol" solo para la acción de dictar y el dato clave.
class Brand {
  static const indigo = Color(0xFF2B2F8F);
  static const indigoDeep = Color(0xFF1C2068);
  static const indigoSoft = Color(0xFF9EA3FF);
  static const gold = Color(0xFFD9A21B);
  static const goldDeep = Color(0xFF8A6200);

  static const ok = Color(0xFF16805C);
  static const warn = Color(0xFFB26A00);
  static const bad = Color(0xFFB42318);

  static const lightBg = Color(0xFFF3F4F8);
  static const lightInk = Color(0xFF171A2E);
  static const lightMuted = Color(0xFF626883);
  static const lightLine = Color(0xFFE1E3EC);

  static const darkBg = Color(0xFF0F1226);
  static const darkCard = Color(0xFF181C3A);
  static const darkInk = Color(0xFFEDEEF7);
  static const darkMuted = Color(0xFF9CA1BF);
  static const darkLine = Color(0xFF2A2F55);
}

const _font = 'Inter';

TextTheme _text(Color ink, Color muted) {
  TextStyle s(double size, FontWeight w, {double h = 1.3, double ls = 0, Color? c}) =>
      TextStyle(fontFamily: _font, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c ?? ink);
  return TextTheme(
    displaySmall: s(40, FontWeight.w700, h: 1.1, ls: -1.2),
    headlineMedium: s(28, FontWeight.w700, h: 1.15, ls: -0.6),
    headlineSmall: s(22, FontWeight.w600, h: 1.2, ls: -0.3),
    titleLarge: s(19, FontWeight.w600, ls: -0.2),
    titleMedium: s(16, FontWeight.w600),
    titleSmall: s(14, FontWeight.w600),
    bodyLarge: s(16, FontWeight.w400, h: 1.45),
    bodyMedium: s(14.5, FontWeight.w400, h: 1.45),
    bodySmall: s(12.5, FontWeight.w400, h: 1.4, c: muted),
    labelLarge: s(15, FontWeight.w600),
    labelMedium: s(13, FontWeight.w500),
    labelSmall: s(11.5, FontWeight.w500, c: muted),
  );
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? Brand.darkBg : Brand.lightBg;
  final card = dark ? Brand.darkCard : Colors.white;
  final ink = dark ? Brand.darkInk : Brand.lightInk;
  final muted = dark ? Brand.darkMuted : Brand.lightMuted;
  final line = dark ? Brand.darkLine : Brand.lightLine;
  final primary = dark ? Brand.indigoSoft : Brand.indigo;

  final scheme = ColorScheme(
    brightness: b,
    primary: primary,
    onPrimary: dark ? Brand.darkBg : Colors.white,
    secondary: Brand.gold,
    onSecondary: const Color(0xFF2A1D00),
    error: dark ? const Color(0xFFFF8A7A) : Brand.bad,
    onError: dark ? Brand.darkBg : Colors.white,
    surface: card,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: line,
    outlineVariant: line,
    surfaceContainerHighest: dark ? const Color(0xFF222750) : const Color(0xFFE9EBF4),
    surfaceContainerHigh: dark ? const Color(0xFF1E2346) : const Color(0xFFEEF0F7),
    surfaceContainer: card,
    surfaceContainerLow: card,
    surfaceContainerLowest: card,
    primaryContainer: dark ? const Color(0xFF2B2F6E) : const Color(0xFFE3E5FF),
    onPrimaryContainer: dark ? Brand.indigoSoft : Brand.indigoDeep,
  );

  final radius = BorderRadius.circular(14);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: _font,
    textTheme: _text(ink, muted),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(line),
      enabledBorder: border(line),
      focusedBorder: border(primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      labelStyle: TextStyle(fontFamily: _font, color: muted),
      floatingLabelStyle: TextStyle(fontFamily: _font, color: primary, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: ink,
        side: BorderSide(color: line, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontFamily: _font, fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2A2F55) : Brand.lightInk,
      contentTextStyle: const TextStyle(fontFamily: _font, color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 19, fontWeight: FontWeight.w600, color: ink),
    ),
    listTileTheme: ListTileThemeData(iconColor: muted, textColor: ink),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
  );
}
