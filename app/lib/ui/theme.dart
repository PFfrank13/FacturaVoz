import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// Sistema de diseño de FacturaVoz.
/// Índigo nocturno, violeta eléctrico y cian suave. Fotografía contextual realista; sin dorados decorativos.
/// Radios de esquina (usar estos en pantallas nuevas en vez de números sueltos).
class Radii {
  static const sm = 8.0; // chips, barras de progreso
  static const md = 14.0; // iconos en cuadro, campos
  static const lg = 18.0; // tarjetas pequeñas
  static const xl = 28.0; // tarjetas grandes y hojas inferiores
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
    bg: Color(0xFF0B1024), surface: Color(0xFF151B34), elevated: Color(0xFF202947), line: Color(0xFF2C3557),
    ink: Color(0xFFF6F7FC), muted: Color(0xFFADB7D1),
    primary: Color(0xFF6957F5), onPrimary: Color(0xFFFFFFFF), primaryText: Color(0xFFA99DFF),
    accent: Color(0xFF17B8D4), ok: Color(0xFF26B887), warn: Color(0xFFF0B34A), bad: Color(0xFFF16D79),
  );

  static const light = DsColors(
    bg: Color(0xFFF6F7FC), surface: Color(0xFFFFFFFF), elevated: Color(0xFFEEF0F8), line: Color(0xFFD7DBEA),
    ink: Color(0xFF0B1024), muted: Color(0xFF4F5873),
    primary: Color(0xFF4C3BD7), onPrimary: Color(0xFFFFFFFF), primaryText: Color(0xFF4C3BD7),
    accent: Color(0xFF0E7C91), ok: Color(0xFF13795A), warn: Color(0xFF8A5300), bad: Color(0xFFB42336),
  );

  static DsColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class Brand {
  // Compatibilidad: las pantallas antiguas usan estas constantes en ambos modos. Son tonos medios de la paleta
  // que dan ≥ 3:1 sobre fondo claro y oscuro (íconos, chips). Pantallas nuevas: DsColors.of(context).
  static const indigo = Color(0xFF6957F5);
  static const indigoDeep = Color(0xFF4C3BD7);
  static const indigoSoft = Color(0xFFA99DFF);
  static const lilac = Color(0xFF7B6CF6);
  static const gold = Color(0xFF1399B0); // cian para dictado y accesos esenciales
  static const goldDeep = Color(0xFF0E7C91);
  static const onGold = Color(0xFFFFFFFF);

  static const ok = Color(0xFF1F9D73);
  static const warn = Color(0xFFB97E14);
  static const bad = Color(0xFFE04F5F);

  static const lightBg = Color(0xFFF6F7FC);
  static const lightInk = Color(0xFF0B1024);
  static const lightMuted = Color(0xFF4F5873);
  static const lightLine = Color(0xFFD7DBEA);

  static const darkBg = Color(0xFF0B1024);
  static const darkCard = Color(0xFF151B34);
  static const darkInk = Color(0xFFF6F7FC);
  static const darkMuted = Color(0xFFADB7D1);
  static const darkLine = Color(0xFF2C3557);

  // §11 "no abusar de degradados": los 79 usos existentes quedan casi planos (dos tonos vecinos de la marca).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF202947), Color(0xFF2A2F66)],
  );
  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6957F5), Color(0xFF5E4CEB)],
  );

  /// Color propio por función (cada función conserva siempre el mismo; ver featureColor en catalog.dart).
  /// Reducido a tonos de la paleta: menos colores en pantalla.
  static const fnPalette = <Color>[
    Color(0xFF6957F5), Color(0xFF1399B0), Color(0xFF1F9D73), Color(0xFF4C3BD7), Color(0xFFB97E14), Color(0xFF5B6B8C),
  ];

  /// Sombra apenas perceptible (§11: sin sombras duras). En oscuro no hay sombra: separa el borde.
  static List<BoxShadow> softShadow(bool dark, {double a = 0.10}) => dark
      ? const []
      : [BoxShadow(color: const Color(0xFF0B1024).withValues(alpha: a * 0.5), blurRadius: 12, offset: const Offset(0, 3))];
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
    primaryContainer: dark ? const Color(0xFF2A2F66) : const Color(0xFFE9E6FF),
    onPrimaryContainer: dark ? ds.primaryText : const Color(0xFF2A1FA0),
  );

  final radius = BorderRadius.circular(16);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    splashFactory: InkSparkle.splashFactory,
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
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
      systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: line)),
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
      floatingLabelStyle: TextStyle(fontFamily: _font, color: ds.primaryText, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
