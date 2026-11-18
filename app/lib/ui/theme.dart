import 'dart:ui' show PointerDeviceKind;

import 'design_tokens.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// Sistema de diseño de FacturaVoz.
/// Edición Enterprise: tinta naval, verde petróleo y ámbar funcional. Tipografía legible y superficies con jerarquía.
/// Radios de esquina (usar estos en pantallas nuevas en vez de números sueltos).
class Radii {
  static const sm = 8.0; // chips, barras de progreso
  static const md = 14.0; // iconos en cuadro, campos
  static const lg = FvTokens.cardRadius; // tarjetas del sistema
  static const xl = FvTokens.sheetRadius; // tarjetas grandes y hojas inferiores
  static const pill = 99.0; // píldoras y botones redondos
}

/// Espacios (múltiplos de 4). Pantallas nuevas: márgenes laterales de 16, separación entre bloques de 12 o 16.
class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Tokens del Design System (Prompt Maestro §11). Modo oscuro = paleta exacta del prompt;
/// modo claro = mismos tonos oscurecidos hasta contraste AA (texto ≥ 4.5:1, íconos ≥ 3:1). Ver docs/reconstruccion/02_DESIGN_SYSTEM.md.
@immutable
class DsColors {
  const DsColors({
    required this.bg, required this.surface, required this.elevated, required this.line,
    required this.ink, required this.muted, required this.primary, required this.onPrimary,
    required this.primaryText, required this.accent, required this.ok, required this.warn, required this.bad,
  });

  final Color bg, surface, elevated, line, ink, muted;
  final Color primary; // relleno de la acción principal
  final Color onPrimary;
  final Color primaryText; // primario usado como TEXTO (enlaces, montos destacados)
  final Color accent; // cian: voz y acciones rápidas
  final Color ok, warn, bad;

  static const dark = DsColors(
    bg: FvTokens.canvasDark, surface: FvTokens.surfaceDark,
    elevated: FvTokens.fieldDark, line: FvTokens.strokeDark,
    ink: FvTokens.inkDark, muted: FvTokens.mutedDark,
    primary: FvTokens.inkDark, onPrimary: FvTokens.ink,
    primaryText: FvTokens.inkDark,
    accent: Color(0xFF60A5FA), ok: FvTokens.emeraldDark,
    warn: Color(0xFFFBBF24), bad: Color(0xFFF87171),
  );

  static const light = DsColors(
    bg: FvTokens.canvas, surface: FvTokens.surface,
    elevated: FvTokens.field, line: FvTokens.stroke,
    ink: FvTokens.ink, muted: FvTokens.muted,
    primary: FvTokens.ink, onPrimary: FvTokens.surface,
    primaryText: FvTokens.ink,
    accent: Color(0xFF2563EB), ok: FvTokens.emerald,
    warn: Color(0xFFB45309), bad: Color(0xFFB91C1C),
  );

  static DsColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class Brand {
  // Compatibilidad: las pantallas antiguas leen Brand; los colores derivan de la identidad Enterprise.
  // Los nuevos componentes usan DsColors.of(context) y roles semánticos para contraste.
  static const indigo = FvTokens.ink;
  static const indigoDeep = FvTokens.ink;
  static const indigoSoft = FvTokens.mutedDark;
  static const lilac = Color(0xFF3185A0);
  static const gold = Color(0xFFF0AC4A);
  static const goldDeep = Color(0xFFAD6416);
  static const onGold = Color(0xFF182B33);

  static const ok = FvTokens.emerald;
  static const warn = Color(0xFF92550D);
  static const bad = Color(0xFFAD3449);

  static const lightBg = FvTokens.canvas;
  static const lightInk = FvTokens.ink;
  static const lightMuted = FvTokens.muted;
  static const lightLine = FvTokens.stroke;

  static const darkBg = FvTokens.canvasDark;
  static const darkCard = FvTokens.surfaceDark;
  static const darkInk = FvTokens.inkDark;
  static const darkMuted = FvTokens.mutedDark;
  static const darkLine = FvTokens.strokeDark;

  // Profundidad sutil en cabeceras y acciones, sin estética púrpura/neón.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF111827), Color(0xFF374151)],
  );
  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF111827), Color(0xFF374151)],
  );

  /// Color propio por función (cada función conserva siempre el mismo; ver featureColor en catalog.dart).
  /// Reducido a tonos de la paleta: menos colores en pantalla.
  static const fnPalette = <Color>[
    Color(0xFF087E74), Color(0xFF2C83A1), Color(0xFF167550),
    Color(0xFFB66D20), Color(0xFFAA5364), Color(0xFF526B84),
  ];

  /// Sombra apenas perceptible (§11: sin sombras duras). En oscuro no hay sombra: separa el borde.
  static List<BoxShadow> softShadow(bool dark, {double a = 0.10}) =>
      dark ? const [] : [BoxShadow(color: const Color(0xFF111827).withValues(alpha: a * 0.4), blurRadius: 24, offset: const Offset(0, 8))];
}

const _font = 'Inter';

TextTheme _text(Color ink, Color muted) {
  TextStyle s(double size, FontWeight w, {double h = 1.3, double ls = 0, Color? c}) =>
      TextStyle(fontFamily: _font, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c ?? ink);
  return TextTheme(
    displaySmall: s(40, FontWeight.w700, h: 1.1, ls: -1.0),
    headlineMedium: s(28, FontWeight.w700, h: 1.15, ls: -0.5),
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
  final ds = dark ? DsColors.dark : DsColors.light;
  final bg = ds.bg;
  final card = ds.surface;
  final ink = ds.ink;
  final muted = ds.muted;
  final line = ds.line;
  final primary = ds.primary;

  final scheme = ColorScheme(
    brightness: b,
    primary: primary,
    onPrimary: ds.onPrimary,
    secondary: ds.accent,
    onSecondary: dark ? ds.bg : Colors.white,
    tertiary: ds.ok,
    error: ds.bad,
    onError: dark ? ds.bg : Colors.white,
    surface: card,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: line,
    outlineVariant: line,
    surfaceContainerHighest: ds.elevated,
    surfaceContainerHigh: ds.elevated,
    surfaceContainer: card,
    surfaceContainerLow: card,
    surfaceContainerLowest: card,
    primaryContainer: dark ? FvTokens.fieldDark : FvTokens.field,
    onPrimaryContainer: dark ? FvTokens.inkDark : FvTokens.ink,
  );

  final radius = BorderRadius.circular(FvTokens.fieldRadius);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SoftPageTransitions(),
      TargetPlatform.iOS: SoftPageTransitions(),
      TargetPlatform.windows: SoftPageTransitions(),
      TargetPlatform.macOS: SoftPageTransitions(),
      TargetPlatform.linux: SoftPageTransitions(),
      TargetPlatform.fuchsia: SoftPageTransitions(),
    }),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FvTokens.sheetRadius))),
    ),
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: _font,
    textTheme: _text(ink, muted),
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.5),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: line.withValues(alpha: dark ? 0.55 : 0.35))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? FvTokens.fieldDark : FvTokens.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: border(primary, 1.4),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      labelStyle: TextStyle(fontFamily: _font, color: muted),
      floatingLabelStyle: TextStyle(fontFamily: _font, color: ds.primaryText, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        elevation: 0,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: ink,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ds.primaryText,
        textStyle: const TextStyle(fontFamily: _font, fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? ds.elevated : ds.ink,
      contentTextStyle: const TextStyle(fontFamily: _font, color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 19, fontWeight: FontWeight.w600, color: ink),
    ),
    listTileTheme: ListTileThemeData(iconColor: muted, textColor: ink),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Colors.white : muted),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? primary : line),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: line),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, color: ink),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: radius)),
        side: WidgetStateProperty.all(BorderSide(color: line)),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: primary, selectionColor: primary.withValues(alpha: 0.25), selectionHandleColor: primary),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? ds.elevated : ds.ink, borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontFamily: _font, color: Colors.white, fontSize: 12.5),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
  );
}

/// Transición de página suave: la nueva pantalla entra deslizándose y apareciendo,
/// la anterior retrocede un poco. Respeta "reducir animaciones" del sistema.
class SoftPageTransitions extends PageTransitionsBuilder {
  const SoftPageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final back = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.06, 0)).animate(back),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.92).animate(back),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.0, 0.06), end: Offset.zero).animate(curve),
          child: FadeTransition(opacity: curve, child: child),
        ),
      ),
    );
  }
}


/// Desplazamiento con rebote suave en todas las plataformas y arrastre con ratón en web.
class PremiumScrollBehavior extends MaterialScrollBehavior {
  const PremiumScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.trackpad};

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
