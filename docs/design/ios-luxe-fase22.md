# FacturaVoz — Sistema Luxe (Fase 22)

Estado: diseño implementado en Flutter en una rama revisable. No es UIKit ni una actualización móvil distribuida.

## Principios visuales
- Superficies editoriales claras (#F2F7FC) y contraste sin negro puro.
- Color funcional único para acciones (#087F68, blanco contraste >4.5:1); azul, lila y ámbar señalan información distinta.
- Vidrio traslúcido en capas de navegación: AppBar y dock. El catálogo, importes, gráficos y tablas permanecen nítidos.
- Barra y dock sin paquetes shader exigentes; BackdropFilter limitado por ClipRRect y RepaintBoundary.
- Transiciones y estados que responden a MediaQuery.disableAnimationsOf; cambio de pestaña con desplazamiento mínimo y fundido.
- Animación de contador del carrito por AnimatedSwitcher; superficies pulsables con FvTactileScale.
- Tipografía Inter incluida por el proyecto (licencia conservada).
- Fotos reales del inventario preservadas; catálogo sin fotos usa inicial tipográfica, fotos demo solo ilustrativas.

## Bibliotecas y fuentes auditadas
- Flutter SDK Animation widgets: https://docs.flutter.dev/ui/widgets/animation
- Performance Flutter: https://docs.flutter.dev/perf/best-practices
- BackdropFilter/BackdropGroup: https://api.flutter.dev/flutter/widgets/BackdropGroup-class.html
- Apple HIG Material: https://developer.apple.com/design/human-interface-guidelines/materials
- flutter_animate (analizado, NO instalado porque el motor de movimiento existente satisface los casos sin dependencia): https://pub.dev/packages/flutter_animate
- glass_mt (analizado, NO instalado porque advierte coste GPU): https://pub.dev/packages/glass_mt

## Contrato de entrega
Sin cambios al backend, RLS, permisos, stock, emisión de comprobantes, flujos financieros ni firmas.
Cada pantalla se valida con pruebas Flutter y smoke de Android. El CI exporta previews de widgets
reales con datos de prueba explícitos, NO capturas autenticadas de Solvex.
