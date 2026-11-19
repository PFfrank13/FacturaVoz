---
name: facturavoz-flutter
description: "Diseñar y modificar pantallas Flutter/Dart de FacturaVoz: formularios, navegación comercial, POS táctil y accesibilidad."
---

# facturavoz-flutter

## Archivos de entrada
- [app/lib/screens/pos.dart](../../../app/lib/screens/pos.dart)
- [app/lib/screens/new_invoice.dart](../../../app/lib/screens/new_invoice.dart)
- [app/lib/screens/business_setup.dart](../../../app/lib/screens/business_setup.dart)
- [app/lib/ui/theme.dart](../../../app/lib/ui/theme.dart)
- [app/lib/services/live.dart](../../../app/lib/services/live.dart)
- [app/test/pos_checkout_layout_test.dart](../../../app/test/pos_checkout_layout_test.dart)

## Trabajo
Usa tokens y componentes existentes. Mantén Cobrar visible con teclado y dock; verifica teléfono/tablet y texto ampliado. Usa productos/servicios/ambos, sin reescribir business_type histórico del Hub. Preserva UUID ante respuesta incierta; P2001 permite revisar el ticket porque corresponde a rollback explícito. No prometas persistencia del carrito tras cerrar la app hasta implementarla. Lee pubspec.yaml antes de elegir APIs; consulta docs.flutter.dev y dart.dev para APIs dudosas.

## Aceptación
flutter analyze --no-pub y pruebas de widgets pertinentes desde app. Comprueba loading/error/reintento y ausencia de overflow. APK solo con entorno validado, sin credenciales privadas en dart-define.
