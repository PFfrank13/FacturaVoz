# FacturaVoz — dirección visual y componentes

## Punto de partida

Se inspeccionó `app/assets/branding/facturavoz_mark.png`: comprobante/micrófono, índigo, violeta y señal cian. Se conserva esa identidad reconocible; no se crea una marca paralela. La nueva web evita degradados de gran superficie: usa tinta oscura, papel cálido y el violeta existente para acciones. El tema móvil original se conserva para no alterar cientos de pantallas sin revisión.

## Tokens

| Uso | Web | Flutter existente |
|---|---|---|
| Tinta | `#17183C` | `Brand.lightInk` |
| Acción | `#5948DB` | `Brand.indigo` |
| Señal/foco | `#007C91` | Cian de marca, con contraste según superficie |
| Papel | `#F5F5F0` | `Brand.lightBg`, actualmente más frío |
| Texto secundario | `#595F79` | `Brand.lightMuted` |
| Línea | `#DCDDE3` | `Brand.lightLine` |
| Éxito/advertencia/error | No nuevos códigos arbitrarios en datos | `Brand.ok`, `Brand.warn`, `Brand.bad` |

El papel web es una variante de escritorio; no se ha completado una migración de tokens compartidos. Flutter usa Inter local. Web mantiene tipografía del sistema para las superficies nuevas y los recursos Geist existentes del layout. Unificar fuentes locales y optimizadas es pendiente explícito.

Escala de espacio: 4/8/12/16/24/32/48. Controles de al menos 44 px. Radios: 8 para controles, 12 para tablas, 20 para acceso. Importes/conteos con números tabulares. Sin animación ornamental; skeleton respeta `prefers-reduced-motion` y Flutter conserva su soporte de reducir movimiento.

## Patrones implementados

- **Acceso:** composición editorial y formulario con etiquetas persistentes, validación, estado pendiente y mensajes de red.
- **Navegación de empresa:** nombre y sector visibles; selección explícita de empresa; lista filtrada por derechos; navegación horizontal en pantallas pequeñas.
- **Pulso operativo:** cifras separadas por líneas, no una parrilla de tarjetas con gráficas ficticias. Cada cifra identifica qué cuenta y enlaza al módulo.
- **Tabla:** encabezados ordenables por teclado, `aria-sort`, región desplazable, filas legibles, búsqueda etiquetada y paginación del servidor.
- **Formulario:** nombres de campos claros, límites, estado de guardado y mensaje de resultado. Sin operaciones destructivas añadidas.
- **Actividad móvil:** lista vertical de tareas reales, barra de estado y fecha legible; no imágenes dentro de tareas operativas.
- **Error/vacío:** textos distintos para ausencia de datos, permisos y fallos de consulta. No convertir fallos en cero ventas.

## Referencias y fotografía

Se intentó abrir las cuatro referencias visuales del prompt; la herramienta devolvió recursos sin contenido visual legible. No se afirma haberlas analizado visualmente ni se copiaron sus recursos.

`app/assets/photos/README.md` identifica `mini_market.webp` como generada. El origen/licencia de las demás imágenes no está suficientemente documentado ahí. Se conservaron los recursos existentes para respetar el trabajo previo; no se reutilizaron en la nueva web como fotografías auténticas. Falta el inventario completo de autor, URL original, licencia, fecha de verificación, permiso de distribución y tamaños optimizados por imagen.

## Revisión realizada

Pantalla de acceso local observada en navegador: escritorio y anchura móvil efectiva de 375 px, sin desbordamiento horizontal. Componente móvil WorkQueue probado a 320 y 768 px con escala de texto 1.6. Esto no sustituye una revisión visual completa de los nueve negocios ni de las rutas autenticadas.
