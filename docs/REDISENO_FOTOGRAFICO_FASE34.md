# FacturaVoz · Fase 34 — identidad visual y fotografía realista

## Qué se modificó

- Rediseño de la paleta general: violeta profundo, marfil frío, coral moderado y contraste accesible en dark mode.
- Identidad visual propia: logo PNG de alta resolución con factura y micrófono; reemplaza el ícono genérico en pantalla de carga, accesos y estados vacíos.
- Acceso: fotografía ambiental de minimarket, con superposición oscura para mantener la legibilidad y evitar texto sobre fondos confusos.
- Selección de rubro: tarjeta fotográfica para **Bodega** y tarjetas con pictogramas para los demás rubros; no se aplica la misma imagen a rubros incorrectos.
- Inicio de Bodega: banner editorial con fotografía, sin botones innecesarios ni dependencia de red.
- POS sin productos de Bodega: estado vacío desplazable con contexto fotográfico. El catálogo conserva exclusivamente las fotos que el dueño sube; no asignamos fotos inventadas a productos concretos.
- Facturas A4: línea de acento, jerarquía tipográfica, emisor y comprobante, datos del cliente, tabla con filas alternadas, total destacado y pie fiscal legible. Conserva el RUC, QR, hash, leyendas y los datos fiscales originales.
- Ajustes de branding: nombres y descripciones de las plantillas PDF actualizados.
- Continuidad: incluye la Fase 33 con **comandas de caja persistentes** y migración `20261122_v31_comandas_caja_persistentes.sql`.

## Origen y uso de la imagen

`app/assets/photos/mini_market.webp` es un **recurso sintético generado con acabado fotográfico** para la imagen ambiental de la marca. No corresponde a un comercio real y no debe utilizarse como fotografía de productos o evidencia de un cliente.

No se incorporaron logos, fotografías reales de terceros ni identidades de clientes. Para otros rubros se mantuvieron pictogramas exclusivos, evitando mostrar fotografías de bodegas en restaurantes, talleres, salones o consultorios. Para una galería auténtica de nueve rubros deben aportarse fotografías propias o recursos con derechos verificados.

## Archivo de logo

- `app/assets/branding/facturavoz_mark.png` (1024 x 1024)
- `app/assets/branding/facturavoz_icon.png` (512 x 512, útil para generar iconos launcher)

El ZIP no tiene el proyecto nativo completo de Android/iOS. El icono del lanzador deberá configurarse al generar las carpetas nativas; no confundir el recurso de Flutter con el icono del APK.

## Base de datos

Este rediseño no requiere migraciones SQL nuevas. Se conserva la migración 20261122 del paquete anterior para comandas persistentes. **No ejecutes SQL adicional solo para instalar colores, fotos del login o logos de la app.**

## Pruebas obligatorias

1. `cd app && flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. Comprobar inicio de sesión y selección de rubro en pantalla pequeña con el teclado visible.
5. Comprobar modo claro y oscuro, fotografías locales (sin internet) y logo.
6. Abrir Bodega sin productos, con productos sin foto y con fotos subidas por el dueño.
7. Crear una factura A4 con más de 20 líneas y probar impresión a papel/archivo. Verificar número, IGV, RUC, QR y notas.
8. Validar en Supabase las comandas persistentes en la migración 20261122 y la separación por empresa.

**Limitación de validación:** en el entorno de edición no hay ejecutables `flutter` ni `dart`. La comprobación realizada es estática; no se puede asegurar compilación, impresión ni aceptación SUNAT sin pruebas en un dispositivo y un backend de prueba.
