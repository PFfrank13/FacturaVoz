# FacturaVoz Signature Edition

Versión Android 3.4.0 (9). El importe, su período y el siguiente paso de caja ocupan el primer plano. Inter acompaña la operación diaria. DM Serif Text distingue los títulos. Ambas familias se incluyen en la aplicación y funcionan sin conexión.

## Diseño

En Inicio, el ábaco de cristal acompaña las ventas del mes. La campana superior izquierda abre los avisos del plan y, para quienes tienen permiso, las alertas del negocio. El indicador se actualiza al recibir una alerta o marcarla como leída. La barra inferior flota sobre el contenido durante el desplazamiento y reserva espacio para leer el último comprobante. [Inicio](../../app/tool/previews/signature/navegacion-390.png) · [Notificaciones](../../app/tool/previews/signature/notificaciones-390.png) · [Inicio desplazado](../../app/tool/previews/signature/inicio-scroll-390.png)

Caja, Inventario, Comprobantes, Compras, Fiados y Reportes usan seis composiciones originales de 352 × 352 píxeles con fondo transparente. Se incluyen como WebP locales. La caja registradora, los paquetes, la impresora, la carretilla, el libro y el ábaco identifican cada módulo junto con su nombre. Los gráficos y las cifras proceden de los datos del negocio.

- **Inicio y reportes.** El importe del período, la tendencia y la meta tienen espacios distintos. Las cifras usan números tabulares. El gráfico diario indica su máximo en la moneda del informe y admite movimiento reducido. [Carbon Design System, gráficos](https://carbondesignsystem.com/data-visualization/chart-types/)
- **Catálogo.** Las seis imágenes de muestra son composiciones originales generadas para esta edición y exportadas como WebP de 512 × 512. La galería las identifica como muestras. Una ficha real utiliza la foto del negocio o un monograma. Cambiar de producto invalida la petición de la imagen anterior. Las dimensiones de la miniatura determinan la resolución de decodificación. [Google Merchant Center, imágenes de producto](https://support.google.com/merchants/answer/6324350)
- **Navegación y lectura.** Papel marfil, verde bosque y superficies opacas sostienen texto, gráficos y formularios. El material translúcido se limita a controles y navegación. El alto contraste activa una superficie sólida. El POS adapta el destino de la animación de añadir al carrito según la disposición visible. [Apple, materiales](https://developer.apple.com/design/human-interface-guidelines/materials) · [Apple, iconos](https://developer.apple.com/design/human-interface-guidelines/icons)
- **Movimiento.** El retorno de controles usa un resorte amortiguado. La selección, el cambio de cantidad y las confirmaciones conservan sus callbacks. El ajuste del sistema para reducir animaciones se aplica a la respuesta táctil, al traslado de producto y a las transiciones de los reportes. [Flutter, accesibilidad](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
- **Dependencias.** La versión evaluada de `liquid_glass_widgets` (1.19.0) requiere Flutter 3.41. El proyecto declara compatibilidad desde 3.35. Se usa el filtro de desenfoque del SDK con un límite independiente por plataforma. Los archivos de fuente y sus licencias se distribuyen dentro del paquete. [Flutter, rendimiento de renderizado](https://docs.flutter.dev/perf/best-practices) · [DM Serif Text y licencia OFL](https://github.com/google/fonts/tree/main/ofl/dmseriftext)

Se instalaron las seis guías pedidas. La guía HIG de dickwu se conserva localmente como `apple-design-hig` porque comparte su nombre de instalación con la de Emil Kowalski. El proyecto reúne los criterios aplicados en sus componentes compartidos y en las capturas de esta edición.

## Evidencia visual

| Vista | Captura Flutter |
| --- | --- |
| Inicio y navegación, teléfono pequeño, oscuro, texto al 140 % | [320 × 720](../../app/tool/previews/signature/navegacion-320.png) |
| Inicio y navegación, escritorio | [1280 × 850](../../app/tool/previews/signature/navegacion-1280.png) |
| Venta rápida con fotografía de muestra | [390 × 844](../../app/tool/previews/signature/pos-muestra-390.png) |
| Inventario con artículos sin foto | [390 × 844](../../app/tool/previews/signature/productos-390.png) |
| Caja, comprobantes, reportes | [Caja](../../app/tool/previews/signature/caja-320.png) · [Comprobantes](../../app/tool/previews/signature/comprobantes-320.png) · [Reportes](../../app/tool/previews/signature/reportes-768.png) |
| Android, emulador independiente | [Plan Básico](../../app/tool/previews/android/plan-basico.png) · [Plan Empresa](../../app/tool/previews/android/plan-empresa.png) · [Carrito](../../app/tool/previews/android/carrito.png) · [Efectivo](../../app/tool/previews/android/efectivo.png) |

La suite de rutas monta los constructores del catálogo con un negocio de prueba en memoria. Captura 91 vistas a 390 dp. Once de ellas se ejecutan también a 320, 768 y 1280 dp. Los temas oscuros corresponden a 320 y 768 dp. Se reproducen el filtro, la búsqueda, la adición y la edición de cantidades en móvil y escritorio. El emulador ejecuta por separado seis escenarios de Android con datos de prueba.

La revisión de imágenes y las pruebas táctiles permitieron corregir un precio truncado, títulos partidos con letra ampliada, fotos heredadas al reutilizar una fila y botones de alta duplicados. La confirmación del pago queda al pie del área visible, por encima del teclado.

### Reproducción desde `app/`

```shell
flutter analyze
flutter test
flutter test test/visual/signature_preview.dart tool/visual_preview.dart tool/visual_checkout_preview.dart --update-goldens
```

El flujo de CI exporta las imágenes para inspección. Los PNG documentan el estado final de cada vista. El movimiento y las acciones se comprueban en pruebas de interacción. [Galería completa](../../app/tool/previews/signature/) · [Pruebas de integración Android](../../app/integration_test/bodega_emulator_smoke_test.dart)

## Entrega

El proceso de firma del repositorio verifica el APK y el AAB contra la huella del certificado histórico y registra sus SHA-256 en `app/build/fase5-release-evidence.json`. El emulador y los datos de ejemplo cubren la interfaz. La aceptación en un teléfono comercial, la impresión física, la confirmación bancaria, el CDR de SUNAT, la medición de rendimiento en hardware y la publicación en una tienda requieren sus respectivos entornos. [Procedimiento de distribución del proyecto](../FASE5_BODEGA_RELEASE_FISICO_20261117.md)
