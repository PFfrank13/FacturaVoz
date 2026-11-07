# Primera venta sobre la restauración real — 7 noviembre 2026

Continuación de `4ebe380`, sin repetir el respaldo ni modificar Supabase alojado.

## Implementación y evidencia

- `backend/scripts/test-restored-pos.mjs` clona la restauración verificada dentro
  del contenedor sin red ni volúmenes. Ensaya v31 checkout, recepción y la nueva
  propuesta `backend/supabase/local/retail_checkout.sql` en una transacción.
- Solo crea/activa usuarios y licencias sintéticos dentro de esa copia local.
  Compara usuarios, organizaciones, membresías, licencias, eventos, productos,
  facturas, pagos y objetos Storage anteriores. Sus datos quedan idénticos;
  las funciones de licencia también se comparan y permanecen idénticas.
- Nueva venta: arroz a 10, cantidad 2, IGV 18%, total 23.60. Una factura y un
  pago; stock 10→8; caja 23.60. COMMIT real y nueva conexión confirman persistencia.
- Misma UUID: recupera la misma factura sin segundo pago. Sin stock: rollback
  de factura, pago, stock e identificador. Segunda empresa: acceso denegado por RLS.
- Precio cambia a 11: nuevo ticket con precio 10 se rechaza sin escritura.
  La UUID de la venta ya confirmada sigue recuperando 23.60.
- Última ejecución con comparaciones ampliadas: base privada
  `retail_restore_1794072724190`, salida 0. No publicar ni exportar esta copia:
  también contiene datos históricos privados.

## UI real y HTTP local

`node backend/scripts/serve-retail-lab.mjs retail_restore_1794072622927`
sirve en `http://127.0.0.1:3102`. Usa el componente real PointOfSale y lecturas
reales para inventario, historial y caja. No es el viejo harness de mocks.
La identidad es sintética fija: NO representa una sesión Supabase Auth real.
No permite URLs DB, SQL arbitrario ni elegir usuario/empresa por HTTP. Solo
escucha loopback y rechaza peticiones de otros orígenes. No se despliega a Vercel.

`node backend/scripts/test-retail-lab-http.mjs` aprobado sobre esa base:
dos peticiones concurrentes, misma UUID → una venta adicional de 11.80,
historial 2, stock 7, caja acumulada 35.40. Precio desactualizado, stock
insuficiente, cantidad con precisión excesiva y origen ajeno rechazados;
el estado persistido no cambia tras rechazos. Esta prueba no pulsa botones en
un navegador: cubre HTTP→RPC→PostgreSQL→consulta posterior.

## Web y Flutter

SQL valida precio/impuesto y bloquea productos en orden estable dentro de la
transacción. Código P2001 identifica exclusivamente rechazo tras consultar la
idempotencia. Web y Flutter permiten revisar ese ticket; conservan UUID ante
timeouts, errores de autorización o respuestas inciertas.

- Backend: 173 pruebas aprobadas; ESLint, TypeScript y build Next aprobados.
- Flutter: analyze sin incidencias; 9 pruebas de checkout/layout/dinero/recepción
  aprobadas. Cambios en errors.dart, services/repo.dart y screens/pos.dart.
- No APK de tienda funcional certificada: falta validar Auth, interfaz y flujo
  móvil conectado. No se distribuye una APK con endpoints ficticios como funcional.

## Puertas abiertas

1. Navegador de Work deshabilitado. Se solicitó habilitarlo para inspección visual
   y acceso del propietario al Preview. No se ha demostrado sesión real,
   selección de empresa ni dashboard autenticado en el despliegue.
2. Revisar política de promociones/mayoreo/cupones Flutter: el guard nuevo exige
   precio de catálogo y rechazaría descuentos del cliente. Es una propuesta local,
   no un cambio listo para activar sobre todas las instalaciones existentes.
3. Falta persistencia durable del carrito Flutter y reconciliación tras reinicio.
4. Diferenciar en persistencia pagos digitales manuales, pendientes y confirmados
   por proveedor; el laboratorio usa efectivo y no simula confirmación bancaria.
5. Probar cierre de caja, devoluciones, jornada completa y servicios reales
   Auth/Storage/Realtime. PostgreSQL aislado no sustituye esas pruebas.
6. Preparar migración compatible revisada; no ejecutar ciegamente historial SQL.
   No hubo escrituras de prueba ni DDL en Supabase remoto.
7. Vercel conserva secretos productivos no exportables. El respaldo integral de
   servicios sigue sin certificar una eliminación; no se plantea borrar recursos.

Sin cambios a Hub, AWS, Caddy, web corporativa, main ni promoción a producción.
