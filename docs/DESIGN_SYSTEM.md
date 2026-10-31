# Sistema de diseño de FacturaVoz (v3.1)

Auditoría hecha sobre `app/lib` (64 pantallas, 33 componentes en `ui/`). Cifras contadas en el código, no estimadas.

## Auditoría
| Área | Estado | Dato |
|---|---|---|
| Colores | Bien centralizados | 43 colores sueltos (`Color(0x…)`) fuera de `ui/theme.dart`; los más en `home.dart` (8) y `catalog.dart` (8). Antes de v3.1 la paleta por función estaba duplicada en `catalog.dart`: ahora vive en `Brand.fnPalette`. |
| Radios | Disperso | ~100 usos de `BorderRadius.circular(n)` con valores sueltos (28, 18, 14, 99, 20, 16, 8, 22…). Se agregó `Radii` (sm 8 · md 14 · lg 18 · xl 28 · pill 99). |
| Espacios | Disperso | ~500 `EdgeInsets` con números sueltos. Se agregó `Gap` (4/8/12/16/24). |
| Tipografía | Mixto | `Inter` fijada en `theme.dart`; 106 `TextStyle(fontFamily: 'Inter')` y 91 `fontSize` sueltos en pantallas: preferir `Theme.of(context).textTheme`. |
| Componentes | Completos | Tarjeta (`SoftCard`), botón (`GradientButton`), píldora (`StatusPill`), esqueletos, vacíos, animaciones con respeto a "reducir movimiento". |
| Estados | Bien | Cargando (esqueleto), vacío (`EmptyState`), error (texto + reintentar), bloqueado (candado + "Disponible en el plan X"). |

**Qué se aplicó ahora (sin tocar lo que funciona):** `Brand.fnPalette`, `Radii`, `Gap`, y los accesos del Inicio usan tokens. Las pantallas viejas NO se migraron en bloque (riesgo sin poder compilar aquí): se migran al tocarlas.

## Tokens
- **Color**: `Brand.indigo/indigoDeep/lilac` (marca), `Brand.gold/goldDeep` (coral = acción de dictar), `ok/warn/bad` (semánticos), `lightBg/lightInk/lightMuted/lightLine` y `dark*` (tema), `heroGradient`, `coralGradient`, `fnPalette` (12 colores, uno fijo por función: `featureColor(id)`).
- **Radio**: `Radii.sm/md/lg/xl/pill`. **Espacio**: `Gap.xs…xl`. **Sombra**: `Brand.softShadow(dark)` (difusa, nunca dura).
- **Movimiento**: `Motion.d(context, Motion.fast)` (se apaga con "reducir movimiento"), `Reveal`, `CountUp`, `Pressable`.

## Componentes (los que más se usan)
| Componente | Cuándo | Variantes / estados | Accesibilidad |
|---|---|---|---|
| `SoftCard` | Agrupar contenido | padding configurable | contenedor, sin rol |
| `GradientButton` | Acción principal de la pantalla (1 por pantalla) | normal · `busy` (cargando) · `onPressed: null` (desactivado) | texto + icono; objetivo ≥ 48 px |
| `FilledButton` / `.tonal` | Acción secundaria dentro de formularios | normal · desactivado | estándar Material |
| `StatusPill` | Estado (Pagada, Vencida, Casero…) | `PillTone` neutral · ok · warn · bad · info | punto de color **+ texto** (no depende solo del color) |
| `Money` / `CountUp` | Cifras de dinero; el contador sube al aparecer | tamaño y peso | cifras tabulares |
| `QuickAction` | Acceso rápido del Inicio | color por función, insignia numérica | `Semantics(button)` |
| `EmptyState` / `SkeletonCard` / `SkeletonList` | Vacío / cargando | — | texto claro |
| `Reveal` | Entrada escalonada (máx. 8 elementos) | `index`, `dy` | respeta "reducir movimiento" |

## Reglas
1. Una acción principal por pantalla; el resto, secundarias.
2. Nunca una cifra a medias: esqueleto hasta tener el dato del servidor.
3. Lo que no incluye el plan se muestra con candado y dice en qué plan está; lo que el rol no permite no se muestra.
4. Cuadrículas con alto fijo (`mainAxisExtent` escalado con `textScalerOf`), nunca `childAspectRatio` con texto dentro (causa del "Bottom overflowed").
5. Color propio por función; el color nunca es el único portador de significado.
6. Pantallas nuevas: `Radii`, `Gap` y `Theme.of(context).textTheme`; no números ni `fontFamily` sueltos.

## Próximos pasos sugeridos
- Migrar a `Radii`/`Gap` las 5 pantallas con más valores sueltos al tocarlas (Inicio, Catálogo, Productos, Rentabilidad, Bloqueo).
- Probar con letra grande (Modo Fácil + tamaño de fuente del sistema al 200 %) en Inicio, POS y Fiados.
- Contraste: `fnPalette` usa tonos 600 (más oscuros) para que el texto blanco encima se lea; falta medir cada uno con una herramienta de contraste (WCAG AA) en el teléfono.
