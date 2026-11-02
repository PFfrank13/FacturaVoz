import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// Sistema de diseño de FacturaVoz.
/// Azul petróleo + menta editorial, fotografía contextual y coral sutil. Nada de dorados decorativos.
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

class Brand {
  // Violeta-lavanda sereno (confianza y calma) + coral durazno cálido (invita a actuar).
  static const indigo = Color(0xFF087E94);
  static const indigoDeep = Color(0xFF0D5268);
  static const indigoSoft = Color(0xFF7CE1D7);
  static const lilac = Color(0xFF51B9C3);
  static const gold = Color(0xFFEF8872); // coral durazno (acción de dictar)
  static const goldDeep = Color(0xFFE96E75);
  static const onGold = Color(0xFF2B2434);

  static const ok = Color(0xFF23956F);
  static const warn = Color(0xFFC57A12);
  static const bad = Color(0xFFD94A5E);

  static const lightBg = Color(0xFFF4F8F8);
  static const lightInk = Color(0xFF122A39);
  static const lightMuted = Color(0xFF667B86);
  static const lightLine = Color(0xFFDCE8EA);

  static const darkBg = Color(0xFF071B28);
  static const darkCard = Color(0xFF102A39);
  static const darkInk = Color(0xFFEFF8F8);
  static const darkMuted = Color(0xFFB0D1D4);
  static const darkLine = Color(0xFF234351);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF09283D), Color(0xFF0C6075), Color(0xFF17A49F)],
  );
  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA77F), Color(0xFFFF7E9A)],
  );

  /// Color propio por función (cada función conserva siempre el mismo; ver featureColor en catalog.dart).
  static const fnPalette = <Color>[
    Color(0xFF4F46E5), Color(0xFF0284C7), Color(0xFF059669), Color(0xFFD97706), Color(0xFFDC2626), Color(0xFFDB2777),
    Color(0xFF7C3AED), Color(0xFF0D9488), Color(0xFFEA580C), Color(0xFF65A30D), Color(0xFF0891B2), Color(0xFFC026D3),
  ]; // tonos 600: el texto/icono blanco encima se lee bien

  /// Sombra suave y difusa (nunca dura): da sensación de flotar.
  static List<BoxShadow> softShadow(bool dark, {double a = 0.10}) => [
        BoxShadow(
          color: (dark ? Colors.black : const Color(0xFF087E94)).withValues(alpha: dark ? 0.35 : a),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];
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
    onSecondary: Brand.onGold,
    error: dark ? const Color(0xFFFF8A7A) : Brand.bad,
    onError: dark ? Brand.darkBg : Colors.white,
    surface: card,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: line,
    outlineVariant: line,
    surfaceContainerHighest: dark ? const Color(0xFF204354) : const Color(0xFFE3F2F1),
    surfaceContainerHigh: dark ? const Color(0xFF19394A) : const Color(0xFFECF5F5),
    surfaceContainer: card,
    surfaceContainerLow: card,
    surfaceContainerLowest: card,
    primaryContainer: dark ? const Color(0xFF174D59) : const Color(0xFFE0F6F2),
    onPrimaryContainer: dark ? Brand.indigoSoft : Brand.indigoDeep,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: line.withValues(alpha: 0.58))),
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
      backgroundColor: dark ? const Color(0xFF174D59) : Brand.lightInk,
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
      decoration: BoxDecoration(color: dark ? const Color(0xFF174D59) : Brand.lightInk, borderRadius: BorderRadius.circular(10)),
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
