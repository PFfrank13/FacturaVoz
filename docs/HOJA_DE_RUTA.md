# Hoja de ruta (después de la v2.0)

Lo que queda pendiente, en orden de impacto. Cada punto dice POR QUÉ no entró y qué haría falta.

## Primero (antes de vender a muchos clientes)
1. **Compilar y probar en un teléfono real** la app v2.0 (ver "Qué NO se pudo verificar" en `CAMBIOS_v2.0.md`):
   `flutter pub get`, `flutter analyze`, `flutter test`, y la guía de 15 minutos (`docs/GUIA_PRUEBAS_15MIN.md`).
2. **Resumen diario de boletas a SUNAT**: hoy cada boleta se envía sola (envío individual por `sendBill`, que SUNAT
   acepta). Para volúmenes altos conviene el *Resumen Diario* (`sendSummary` + consulta de ticket). Hay que
   implementarlo en el servidor con Lycet/Greenter y probarlo en beta.
3. **Comunicación de baja** de facturas (además de la nota de crédito que ya existe), para anular el mismo día.
4. **Proveedor DNI/RUC y tipo de cambio**: elegir uno con plan gratuito o de bajo costo, poner sus URL/token en
   Vercel (`DOC_API_*`, `FX_API_*`) y confirmar el formato de respuesta (la app ya acepta varios formatos comunes).

## Después
5. **Lector automático de notificaciones de Yape/Plin (Android)**: requiere un `NotificationListenerService`
   nativo y el permiso especial "Acceso a notificaciones". Hoy funciona copiando y pegando (2 toques).
6. **Widgets de la pantalla de inicio** (ventas del día, botón de dictar): requieren código nativo
   (Android `AppWidgetProvider`, iOS WidgetKit) y un paquete como `home_widget`. Hoy hay **atajos del ícono**.
7. **Impresoras USB conectadas al teléfono** (OTG) e impresión directa desde la web: hoy se usa el ticket en PDF.
8. **Envío de webhooks más frecuente**: en el plan Hobby de Vercel los crons corren una vez al día. Opción gratuita
   ya preparada: `pg_cron` + `pg_net` en Supabase llamando a `/api/cron/webhooks` (configurar `dispatch_url` y
   `cron_secret` en `private.app_config`, ver migración 20261112).
9. **Multisucursal real** (series por local, stock por almacén). Hoy: varias empresas por cuenta.
10. **Mapa grande** con todos los clientes/trabajos del día y ruta sugerida para técnicos.
11. **Pagos en línea del plan** dentro de la app (hoy se abre `pay_url` del Hub en el navegador).
12. **Pruebas de widgets** de cada pantalla nueva (hoy hay pruebas de lógica y del sistema de movimiento).

## Ideas para medir
- Tiempo desde abrir la app hasta emitir la primera boleta (meta: < 3 minutos).
- % de dueños que activan el modo simple y cuántos lo apagan después.
- Uso de "Para hoy" y del resumen hablado del copiloto.
