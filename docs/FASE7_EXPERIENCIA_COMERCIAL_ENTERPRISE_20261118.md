# FacturaVoz · Fase 7, experiencia empresarial para comercialización

Fecha de diseño: 2026-11-18. Alcance de esta entrega: **Flutter (móvil y web)**; no se modifican endpoints Next.js, políticas de base de datos, licencias, stock ni cobros.

## Objetivo

Eliminar la estética púrpura del sistema anterior y crear una interfaz SaaS de caja moderna, reconocible, legible y utilizable durante una jornada completa. Priorizar transacciones reales, claridad y rendimiento antes que animaciones decorativas.

Guías de referencia consultadas:
- Flutter, diseño adaptativo: https://docs.flutter.dev/ui/adaptive-responsive
- Google, roles de color y contraste Material 3: https://developer.android.com/codelabs/m3-design-theming?hl=es-419
- Nielsen Norman Group, diseño de aplicaciones complejas: https://www.nngroup.com/articles/complex-application-design/

## Identidad visual

| Token | Claro | Oscuro | Uso |
| --- | --- | --- | --- |
| Fondo | #F4F7F8 | #0A1520 | Base de la app |
| Tarjeta | #FFFFFF | #12232E | Paneles, formularios y listas |
| Primario | #087E74 | #42CDBA | Acciones de alta prioridad, estados seleccionados |
| Texto primario | #132A36 | #F1F8F7 | Legibilidad |
| Texto secundario | #536A73 | #AFCCCE | Ayuda y metadatos |
| Contorno | #D7E2E5 | #33505A | Separación de superficies |
| Acento cálido | #AD6416 | #F2B75E | Señales discretas, no acciones destructivas |

- La selección del menú lateral Bodega permanece en un **Drawer único**, con fondo #0B0E17 y acento verde petróleo. Se conservan permisos por licencia y rol. Sin BottomNavigationBar duplicada.
- El encabezado comercial de Bodega usa métricas existentes (ventas de hoy/mes, borradores, meta y curva de 14 días) sin generar números simulados. Si no se ha cargado el servidor no se muestra cero engañoso.
- La acción «Nueva venta» conserva exactamente su navegación y seguridad; los módulos tienen iconos diferenciados por función, estados táctiles/hover y espaciado consistente.
- El modo oscuro conserva texto de alto contraste. El sistema respeta reducir animaciones, modo Fácil y selección de tema del usuario.

## Reglas de la aplicación

1. No mostrar funciones bloqueadas en Básico ni acciones que el rol no permite.
2. Las cifras operativas provienen de Supabase; nunca dibujar saldos o porcentajes artificiales.
3. La UI no escribe directamente stock, no omite controles de cobro ni firma comprobantes por sí misma.
4. El usuario debe poder navegar con mouse, teclado o toque sin menús alternativos que compitan por foco.
5. Los colores de estado nunca sustituyen al texto de confirmación o al mensaje de error.
6. Animaciones deben ser cortas y desactivables; no ralentizar caja, búsqueda ni cobros.

## Puertas comerciales

Automáticas: `flutter analyze`, `flutter test`, prueba de temas/contraste, compilación web/APK debug, validación de firma release negativa, backend y Postgres, emulador Android de Bodega.

La publicación de **web Flutter** requiere identificar el proyecto de hosting que sirve la interfaz y una nueva compilación con valores de entorno válidos. La publicación de **Android** requiere keystore release firmado y aceptación en dispositivo físico. No afirmar comercialización completada si falta alguna de estas evidencias. Reutilizar la infraestructura real y nunca crear un proyecto paralelo para saltar controles.

## Fases siguientes para madurez total

- Unificar las pantallas de gestión de clientes, productos, caja y comprobantes con las mismas tarjetas, títulos, estados vacíos y jerarquía de acciones.
- QA exploratorio en anchos 320, 360, 412, 768 y 1440 puntos, texto al 125–145 %, redes lentas y modo claro/oscuro.
- Contrastar tiempos reales de inicio, búsqueda, cobro y sincronización bajo uso simultáneo; no declarar producción lista solo por pasar pruebas unitarias.
