# FacturaVoz — Recuperación del POS tras reinicio (8/11/2026)

## Cambios introducidos

- El POS conserva **antes** de llamar a `fast_checkout_atomic` una copia cifrada de la solicitud original en `flutter_secure_storage`. Incluye `request_id`, usuario, organización, medio de pago, moneda, impuesto, notas y líneas con `product_id`, cantidad y precio.
- Al abrir el POS se comprueba si hay una venta cuyo resultado es incierto. Si existe, **no se muestra un carrito nuevo**; aparece «Recuperar cobro», que utiliza exactamente el mismo método y los mismos datos guardados. No se emite una solicitud con otra clave.
- Durante la recuperación y desde el inicio del primer cobro se bloquean nuevas ventas, edición de artículos, cupones y vaciado del carrito. Fallos de lectura segura bloquean el POS hasta poder comprobar el estado.
- La instantánea se elimina únicamente tras recibir una respuesta de éxito de la operación SQL. Si falla la confirmación o el borrado local, el reintento usa la misma solicitud. La identidad de empresa y cuenta se valida antes del envío.
- Se agregaron pruebas para serialización, recuperación inmutable, SKU ausente, cantidades negativas y datos inválidos.

## Limitaciones reales

- Estas modificaciones **no** sustituyen la migración `20261123_v31_fast_checkout_atomic.sql`; sin ese RPC desplegado, el POS no puede cobrar rápido. No existe ruta alternativa de tres operaciones, ya que produciría inconsistencias.
- La copia cifrada depende del almacenamiento seguro que proporcione cada plataforma. Fallo o indisponibilidad del almacén bloquea venta rápida; no se hace un bypass inseguro.
- En una instalación **anterior** a este cambio, un cobro incierto que ya perdió su identificador al reiniciar no puede reconstruirse retroactivamente; reconciliarlo desde los registros reales del servidor.
- Restaurar el cobro confirma la venta, pero las notas y vínculos de comanda del restaurante siguen requiriendo reconciliación si se cerró el proceso antes de enlazarlos.
- Un test unitario no garantiza que el RPC actual valide la coherencia entre `request_id` y carga enviada, ni demuestra aislamiento entre cajeros o stock concurrente. Eso requiere pruebas de integración y revisión específica del SQL.
- No se verificó compilación Flutter en este entorno ni se aplicaron migraciones, se cambiaron licencias o se desplegó código productivo.

## Comprobación exigida antes de fusionar

1. `cd app && flutter pub get && flutter analyze && flutter test`.
2. En Supabase **staging** aislado, aplicar migraciones en el orden correcto y comprobar `fast_checkout_atomic`, `RLS`, activación Hub, segregación de empresas y controles de stock.
3. Abrir POS con cuenta A/empresa A, preparar una venta y forzar cierre antes de recibir respuesta. Reabrir: recuperar con el mismo `request_id`; confirmar **una sola** factura, **un solo** pago y **un solo** descuento de stock.
4. Repetir con timeout tras commit; después probar cortes antes del commit, cambio de empresa/usuario, permisos revocados, almacenamiento cifrado no disponible y reintento con otro medio de pago.
5. Probar restaurante con comanda registrada y enlace fallido, confirmando reconciliación sin nueva venta ni comanda duplicada.
6. Registrar resultados, revisar logs de errores y preparar procedimiento de reversión. Solo después planificar migración y despliegue de producción.

## Estado remoto observado el 8/11/2026

- Repositorio autorizado: `PFfrank13/FacturaVoz`; rama de trabajo `fix/basic-pos-crash-recovery-20261108`.
- Proyecto Supabase `FacturaVoz`: activo. La lista de migraciones remotas consultada solo incluyó cuatro entradas de tiempo real de 1/11/2026, y no mostró la migración de POS atómico.
- Por lo tanto **no se afirma** que la base de datos productiva esté lista para este flujo. No ejecutar las migraciones históricas en lote sobre clientes reales.
