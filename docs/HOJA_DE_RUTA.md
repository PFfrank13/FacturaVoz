# Hoja de ruta (después de la v3)

## Recomendación de lanzamiento (H)
**Piloto con UN rubro: Servicios técnicos e internet** (o Bodega si tu red de contactos está ahí).
Por qué: es el rubro donde FacturaVoz ya tiene más piezas reales y probadas (tablero, mensualidades, corte por mora,
equipos con serie, cobranza) y donde el dolor (morosos, cortes, técnicos en la calle) se paga solo.
Plan: 5–10 negocios, 30 días, plan Pro con descuento a cambio de opinión semanal. Antes de cobrar el primer sol:
Vercel Pro + Supabase Pro + Groq Developer (ver `COSTOS_Y_ESCALA.md`), política de privacidad publicada y bancos de
datos inscritos (`PRIVACIDAD_Y_TERMINOS.md`).

## Lo que falta para producción (H), en orden
1. **Compilar y probar en un teléfono real** (aquí no hay SDK de Flutter): `flutter pub get`, `flutter analyze`,
   `flutter test`, y `docs/GUIA_PRUEBAS_RUBROS.md`.
2. **Importar el archivo real** `facturas_clientes_migracion_1500.xlsx` en una empresa de prueba (no llegó adjunto;
   se probó con uno sintético idéntico en estructura) y comparar la pantalla final.
3. **Guía de remisión electrónica (GRE)** para mayoristas: emitir desde la app con Greenter/Lycet (hoy se hace en
   SUNAT y se anota el número).
4. **Resumen diario de boletas** y **comunicación de baja** (ver v2).
5. **Libro de Reclamaciones virtual** para FacturaVoz y para cada tienda (Ley 32495).
6. **Sentry/Crashlytics** (gratis) con tu cuenta (ver `OPERACION_PRODUCCION.md`).
7. Pasar las listas grandes de la app a `invoice_page` (cursor de 50 en 50) cuando un negocio pase de ~5 000
   comprobantes (la base ya lo tiene).
8. Tienda: cupones en la web (hoy solo en caja), variantes (talla/color) y galería de varias fotos por producto
   (hoy 1 foto); seguimiento del pedido con estados en vivo (hoy la página del pedido muestra el pedido y su estado
   de cotización).
9. Voz: frases fijas pregeneradas al desplegar (hoy se generan la primera vez que alguien las pide y quedan en caché).
10. Importador: consulta DNI/RUC opcional para completar razones sociales (apagada para no gastar el cupo).

## Pendientes heredados de v2
Lector automático de notificaciones Yape/Plin (Android), widgets de pantalla de inicio, impresoras USB, webhooks
más frecuentes (pg_cron), multisucursal real, mapa grande de técnicos, pagos del plan dentro de la app, pruebas de
widgets.

## Ideas para medir
- Tiempo hasta la primera boleta (< 3 min) y hasta el primer cobro registrado.
- % de negocios que usan la función estrella de su rubro cada semana.
- Preguntas al Copiloto por negocio/día (para dimensionar Groq) y caracteres de voz (ElevenLabs).
