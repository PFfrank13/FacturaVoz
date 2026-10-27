import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// Sistema de diseño de FacturaVoz.
/// Índigo "tinta" como color de marca, oro "sol" solo para la acción de dictar y el dato clave.
class Brand {
  // Violeta-lavanda sereno (confianza y calma) + coral durazno cálido (invita a actuar).
  static const indigo = Color(0xFF6A62E2);
  static const indigoDeep = Color(0xFF5048C8);
  static const indigoSoft = Color(0xFFB9B4FF);
  static const lilac = Color(0xFF9B8CF5);
  static const gold = Color(0xFFFF9376); // coral durazno (acción de dictar)
  static const goldDeep = Color(0xFFFF6F8E);
  static const onGold = Color(0xFF3B1D2E);

  static const ok = Color(0xFF23956F);
  static const warn = Color(0xFFC57A12);
  static const bad = Color(0xFFD94A5E);

  static const lightBg = Color(0xFFF8F6FD);
  static const lightInk = Color(0xFF26254B);
  static const lightMuted = Color(0xFF77799B);
  static const lightLine = Color(0xFFECE9F7);

  static const darkBg = Color(0xFF14132B);
  static const darkCard = Color(0xFF1E1D3F);
  static const darkInk = Color(0xFFEFEEFB);
  static const darkMuted = Color(0xFFA2A3C6);
  static const darkLine = Color(0xFF2F2E57);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6A62E2), Color(0xFF8E7CF2), Color(0xFFB58BF5)],
  );
  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA77F), Color(0xFFFF7E9A)],
  );

  /// Sombra suave y difusa (nunca dura): da sensación de flotar.
  static List<BoxShadow> softShadow(bool dark, {double a = 0.10}) => [
        BoxShadow(
          color: (dark ? Colors.black : const Color(0xFF6A62E2)).withValues(alpha: dark ? 0.35 : a),
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
    surfaceContainerHighest: dark ? const Color(0xFF2A2954) : const Color(0xFFEFEDFA),
    surfaceContainerHigh: dark ? const Color(0xFF25244A) : const Color(0xFFF3F1FC),
    surfaceContainer: card,
    surfaceContainerLow: card,
    surfaceContainerLowest: card,
    primaryContainer: dark ? const Color(0xFF34336F) : const Color(0xFFEBE9FF),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: line)),
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
      backgroundColor: dark ? const Color(0xFF34336F) : Brand.lightInk,
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
      decoration: BoxDecoration(color: dark ? const Color(0xFF34336F) : Brand.lightInk, borderRadius: BorderRadius.circular(10)),
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
