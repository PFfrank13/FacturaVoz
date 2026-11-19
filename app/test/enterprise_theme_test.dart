import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/theme.dart';
import 'package:facturavoz/ui/design_tokens.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final higher = a > b ? a : b;
  final lower = a < b ? a : b;
  return (higher + 0.05) / (lower + 0.05);
}

void main() {
  test('identidad comercial elimina el violeta del sistema compartido', () {
    expect(DsColors.light.primary, FvTokens.ink);
    expect(DsColors.dark.primary, FvTokens.inkDark);
    expect(DsColors.light.bg, FvTokens.canvas);
    expect(DsColors.dark.bg, FvTokens.canvasDark);
    expect(Brand.heroGradient.colors,
        [const Color(0xFF18181B), const Color(0xFF54545B)]);
    expect(Brand.coralGradient.colors.first, const Color(0xFF18181B));
  });

  test('acciones y textos esenciales cumplen contraste AA en ambos modos', () {
    for (final c in [DsColors.light, DsColors.dark]) {
      expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5),
          reason: 'Texto sobre la acción principal');
      expect(_contrast(c.ink, c.surface), greaterThanOrEqualTo(4.5),
          reason: 'Texto principal sobre tarjetas');
      expect(_contrast(c.muted, c.surface), greaterThanOrEqualTo(4.5),
          reason: 'Metadatos y ayuda operativa');
    }
  });

  test('Material 3 expone el mismo esquema de colores para widgets estándar', () {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.colorScheme.primary, DsColors.light.primary);
    expect(dark.colorScheme.onPrimary, DsColors.dark.onPrimary);
    expect(light.scaffoldBackgroundColor, DsColors.light.bg);
  });
}
