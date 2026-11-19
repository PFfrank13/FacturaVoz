---
name: facturavoz-ios-luxe
description: "Skill de diseño Flutter para FacturaVoz: construir un POS tipo iPhone con diseño editorial, vidrio sobrio, controles accesibles, animaciones físicas y rendimiento verificable."
---
# FacturaVoz · iOS Luxe Flutter UI

Esta skill es LOCAL del repositorio y opera sobre código real Flutter. No ejecuta instaladores, API externas o cambios de producción por sí sola.

## Reglas obligatorias
1. Antes de cambiar estilo, localizar widget concreto en `app/lib/screens/`, widget compartido en `app/lib/ui/` y contrato funcional.
2. Estilo del producto: editorial comercial minimalista, fondos suaves azul hielo y jade, vidrio de una capa en navegación, tarjetas sólidas con fotografías amplias. Prohibido agregar degradados brillantes indiscriminados, íconos emoji, blur por fila o datos de ventas inventados.
3. Reutilizar `FvTokens`, `FvLuxe`, `RetailVisual`, `FvGlassSurface`, `FvPosProductCard`, `RetailPremiumBottomDock`; no duplicar temas ni crear segundo menú.
4. Acciones principales con contraste WCAG AA ≥4.5:1. Área táctil recomendada ≥44x44 dp. Verificar fuentes escaladas, alto contraste, etiquetas semánticas, lector de pantalla y `MediaQuery.disableAnimationsOf`.
5. Animación con propósito: 150–300 ms para microinteracciones y navegación, `Curves.easeOutCubic` para salida suave, `Curves.easeOutBack` sólo para elementos pequeños. Animar opacidad/transformaciones; evitar re-layout y tickers permanentes.
6. Material translúcido únicamente en barras y controles flotantes. `BackdropFilter` siempre recortado; preferir gradiente de profundidad sobre filtros caros; reducir transparencia en alto contraste. Nunca vidrio sobre vidrio.
7. POS y caja: precios con `FontFeature.tabularFigures()`, botones de pago con estados claros; no simular pago real, no alterar callbacks, stock, impuestos, licencias, backend o RLS.
8. Fotografías: usar fotos del negocio y `StorageImage`/caché; si faltan, fallback tipográfico elegante. Un ejemplo visual jamás se guarda como inventario por defecto.
9. Respuesta móvil 320/390 dp y tablet/PC 768/1024 dp; scroll horizontal sólo para filtros/carruseles indicados; sin overflow ni duplicación de navegación.
10. Para cada pantalla modificada: pruebas de widgets, `flutter analyze`, `flutter test`, Android emulator y captura REAL de widgets/Android, señalando fixtures. No fusionar con CI rojo.

## Criterios de salida
- Respeta prioridades: accesibilidad, tacto, rendimiento, consistencia, responsive, tipografía, movimiento, formularios y navegación.
- Render real de Flutter y documentación de diferencias con conceptos. La exactitud visual se verifica en el dispositivo del usuario.
- Ningún `// TODO` introducido ni reportar una versión firmada sin distribución real.

## Referencias verificadas (no dependencias instaladas)
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/materials
- Flutter rendering/performance: https://docs.flutter.dev/perf/best-practices
- Flutter animation: https://docs.flutter.dev/ui/widgets/animation
- Reglas de referencia y popularidad: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill (MIT)
- Flutter específico: https://github.com/TheSimpleApp/flutter-app-skills

La skill es de elaboración propia basada en estos criterios; no representa la instalación íntegra de las bibliotecas upstream.
