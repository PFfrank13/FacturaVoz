# Design System FacturaVoz (Prompt Maestro §11)

Código: `app/lib/ui/theme.dart` (tokens + tema), `app/lib/ui/ds.dart` (componentes).

## Colores

| Token | Oscuro (paleta del prompt) | Claro (AA) | Uso |
|---|---|---|---|
| bg | `#0B1024` | `#F6F7FC` | Fondo de pantalla |
| surface | `#151B34` | `#FFFFFF` | Tarjetas, listas, barra de acción |
| elevated | `#202947` | `#EEF0F8` | Hojas, menús, avisos |
| line | `#2C3557` | `#D7DBEA` | Bordes de 1 px (en lugar de sombras) |
| ink | `#F6F7FC` | `#0B1024` | Texto principal |
| muted | `#ADB7D1` | `#4F5873` | Texto secundario |
| primary | `#6957F5` (índigo) | `#4C3BD7` (violeta) | Relleno de la acción principal |
| primaryText | `#A99DFF` | `#4C3BD7` | Primario usado como texto (enlaces, montos) |
| accent | `#17B8D4` (cian) | `#0E7C91` | Voz y acciones rápidas |
| ok / warn / bad | `#26B887` / `#F0B34A` / `#F16D79` | `#13795A` / `#8A5300` / `#B42336` | Estados |

Contrastes calculados (WCAG 2.1):

| Par | Contraste | Mínimo |
|---|---|---|
| ink sobre bg (oscuro) | 17.6 : 1 | 4.5 |
| muted sobre surface (oscuro) | 8.5 : 1 | 4.5 |
| muted sobre elevated (oscuro) | 7.1 : 1 | 4.5 |
| blanco sobre primary `#6957F5` | 4.9 : 1 | 4.5 |
| primaryText `#A99DFF` sobre surface | 7.2 : 1 | 4.5 |
| ok / warn / bad sobre surface (oscuro) | 6.7 / 9.1 / 5.8 : 1 | 3 (íconos) · 4.5 (texto) |
| ink sobre bg (claro) | 17.6 : 1 | 4.5 |
| muted sobre blanco (claro) | 7.1 : 1 | 4.5 |
| violeta `#4C3BD7` sobre blanco y blanco sobre violeta | 7.2 : 1 | 4.5 |
| ok / warn / bad (claro) sobre blanco | 5.4 / 6.3 / 6.5 : 1 | 4.5 |

`#6957F5` como **texto** sobre el fondo oscuro da 3.8 : 1 (no llega a 4.5), por eso existe `primaryText`.

**Compatibilidad.** Las pantallas antiguas usan las constantes `Brand.*` en ambos modos. Se reasignaron a la paleta
nueva con tonos medios que dan ≥ 3 : 1 sobre ambos fondos (íconos y chips). Las 12 tonalidades por función
(`fnPalette`) se redujeron a 6 tonos de la paleta. Los 79 usos de degradados quedan casi planos (dos tonos vecinos) y
`GradientButton` pasó a relleno sólido: nada se rompe y desaparece el exceso visual. `softShadow` ya no dibuja sombra
en modo oscuro y es mínima en el claro (se separa con bordes de 1 px).

## Espacio, radios y texto
- Espacios: `Gap` 4 · 8 · 12 · 16 · 24. Márgenes laterales 16.
- Radios: `Radii` 8 · 14 · 18 · 28 · píldora. Tarjetas = 18 (antes 24).
- Tipografía Inter; cuerpo 14.5–16, secundaria 12.5. Nada se dibuja con una altura fija que corte texto:
  los botones usan **altura mínima** (52–56) y crecen con letra grande.

## Componentes (`ds.dart`)
| Componente | Regla del prompt que resuelve |
|---|---|
| `DsActionBar` | Acción principal **siempre visible** abajo; respeta área segura y teclado; no se superpone (va en `bottomNavigationBar`). |
| `DsStat` + `DsStatGrid` | Indicadores en 2 columnas (4 en tablet) con `Wrap`: nunca se enciman en teléfonos chicos; la cifra se reduce en vez de desbordar. |
| `DsSection` | Jerarquía clara (título marcado como encabezado para lectores de pantalla). |
| `DsRow` | Fila tocable de 56 px mínimo, 2 líneas máximo. |
| `DsStatus` | Estado con **ícono + texto**, nunca solo color. |
| `DsStateView` | Carga · vacío · error con **Reintentar** (siempre una salida). |
| `DsLocked` | Función bloqueada por plan o rol: se ve el motivo y no navega a una pantalla que la base rechazaría. |

## Reglas de pantalla
1. Una acción principal por pantalla (`DsActionBar` o el botón principal de Inicio).
2. Sin scroll anidado: una sola lista por pantalla; los indicadores usan `Wrap`, no listas horizontales.
3. Hojas inferiores solo para una decisión corta (nivel 4); pantallas completas van como página (nivel 3).
4. Transiciones: `SoftPageTransitions` respeta "reducir animaciones" del sistema.

## Aplicado en esta fase
Tema global (todas las pantallas), `GradientButton`, `SoftCard`, Inicio por rol (`role_home.dart`), Caja
(`cash_day.dart`), comparación de planes (`plan_compare.dart`). Pendiente: migrar pantalla por pantalla los 257 colores
sueltos a `DsColors.of(context)`.
