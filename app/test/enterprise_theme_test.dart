import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/ui/theme.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final higher = a > b ? a : b;
  final lower = a < b ? a : b;
  return (higher + 0.05) / (lower + 0.05);
}

void main() {
  test('identidad comercial elimina el violeta del sistema compartido', () {
    expect(DsColors.light.primary, const Color(0xFF111827));
    expect(DsColors.dark.primary, const Color(0xFFF9FAFB));
    expect(DsColors.light.bg, const Color(0xFFF5F5F7));
    expect(DsColors.dark.bg, Colors.black);
    expect(Brand.heroGradient.colors,
        [const Color(0xFF111827), const Color(0xFF374151)]);
    expect(Brand.coralGradient.colors.first, const Color(0xFF111827));
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
