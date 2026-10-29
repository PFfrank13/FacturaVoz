# Rendimiento (A2/A3) — métricas antes / después

Medido en Postgres 16 local con **10 000 comprobantes** (25 079 líneas, 6 000 cobros) en una empresa, como usuario
autenticado (con RLS). Script: `backend/supabase/tests/bench_v3.sql`.

| Consulta | Antes | Después |
|---|---|---|
| Ventas del mes (Inicio) | 1 203 ms (suma de líneas por comprobante) | **10 ms** (`sales_summary`, totales guardados) |
| Ventas de todo el historial | 6 214 ms | **31 ms** |
| Resumen del Copiloto (`business_snapshot`) | 9 317 ms | **340 ms** |
| Página de 50 comprobantes (`invoice_page`) | 15 ms | **5 ms** |
| Serie mensual de un año (gráfico) | 664 ms | **12 ms** |

Qué se hizo:
- **Totales guardados** en cada comprobante (base, IGV, total), mantenidos por disparador; una sola regla de ventas.
- **RLS rápida**: las políticas calculaban "¿es miembro? ¿es técnico? ¿licencia?" una vez **por fila**; ahora una
  vez **por consulta** (mismas reglas; todas las pruebas de roles dan idéntico).
- Índices: `(org_id, issue_date, currency)` con columnas incluidas, pendientes por vencer, cobros por fecha,
  clientes por RUC/DNI, líneas por comprobante.
- Copiloto: contexto en paralelo, respuesta en **tiempo real** (palabra por palabra), modelo más rápido.
- App: cifra del mes pedida al servidor **en paralelo** con la lista y **esqueleto** hasta tenerla (nunca un
  número a medias); recargas en vivo con espera de 450–600 ms (debounce); enlaces firmados de imágenes
  reutilizados (caché); cada pestaña en `RepaintBoundary`; listas paginadas (100 + "ver más"); la base ya ofrece `invoice_page` (cursor) para pasar las listas grandes a páginas de 50 (Hoja de ruta).
- Tienda: página generada en el servidor y renovada cada 2 min (ISR), imágenes perezosas.

No medido aquí (sin teléfono ni SDK de Flutter en este entorno): tiempo de arranque y cuadros por segundo de la app.
Para medirlos: `flutter run --profile` y DevTools → Performance (meta: arranque < 2 s, sin cuadros > 16 ms al
desplazar Inicio y Comprobantes).
