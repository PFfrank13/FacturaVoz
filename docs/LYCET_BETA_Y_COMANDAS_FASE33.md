# FacturaVoz v3.1 / Fase 33+ — Lycet Beta y comandas de caja guardadas

## A. Cómo comprobar Lycet con SUNAT Beta

1. **No uses un RUC real en producción para estas pruebas.** Configura una instalación de pruebas separada. SUNAT Beta valida la estructura XML y no concede validez tributaria; no reemplaza una prueba real de producción ni un proceso formal de habilitación.
2. **Desde Windows, sin VPS:** instala Docker Desktop con WSL2 y Git Bash; lee `docs/LOCAL_DOCKER.md`. Abre Git Bash, entra a `infra/lycet`, ejecuta `./bootstrap.sh local` (solo una vez) y `docker compose up -d --build`. `curl http://localhost:8080/health` debe devolver `ok`.
3. **Exponer HTTPS temporal:** en otra consola `docker run --rm cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://host.docker.internal:8080`. Copia la URL HTTPS temporal. No cierres la consola del túnel.
4. **Para VPS/Oracle:** sigue `infra/lycet/INSTALACION.md`, ejecuta `./bootstrap.sh` (sin `local`), configura dominio, puertos 80/443, `docker compose up -d --build` y valida `https://DOMINIO/health`.
5. **Smoke test del ZIP:** con Bash, en `infra/lycet`, `LYCET_URL=https://DOMINIO LYCET_API_KEY=CLAVE_GENERADA ./smoke-beta.sh`. El script registra el RUC de ejemplo 20000000001 con credenciales Beta MODDATOS y envía una factura a SUNAT Beta. Revisa `success: True` y el código de CDR; si falla, ejecuta `docker compose logs --tail=100 lycet`. No compartas el token por chat.
6. **Prueba dentro de FacturaVoz:** configura en Vercel `LYCET_URL` y `LYCET_API_KEY` como secretos de backend, redepliega y entra a Ajustes → Facturación electrónica → entorno Beta. Usa empresa de pruebas, valida emisión de factura, boleta, nota de crédito y operación exonerada, y la descarga/almacenamiento de XML y CDR. Revisa fallos de RUC, totales, impuestos y duplicados.
7. **Producción:** comprueba por separado la afiliación vigente SEE, certificado del emisor, usuario SOL secundario, series, régimen y obligaciones con contador/SUNAT. Nunca reutilices el RUC ficticio ni las credenciales de pruebas en producción.

Documentación pública: https://orientacion.sunat.gob.pe/12-pautas-servicio-beta y https://github.com/giansalex/lycet.

## B. Comandas desde caja: corrección instalada en este ZIP

**Nueva migración obligatoria:** `backend/supabase/migrations/20261122_v31_comandas_caja_persistentes.sql`.

Ejecutar desde Supabase SQL Editor **después de todas las migraciones hasta `20261121_v31_tiempo_real_2.sql`**. Si ya estás en producción, realiza un respaldo de base antes de aplicarla y revisa las políticas RLS/roles en una copia de staging.

- `PosScreen(tableMode: true)` registra el pedido mediante `create_pos_kitchen_order` (una transacción en PostgreSQL), con nombre de mesa, para llevar, platos, cantidad, precios y notas por plato.
- Se utiliza la infraestructura ya existente de pedidos QR: `quotes`, `quote_items`, `kitchen_status` (`nuevo` → `preparando` → `listo` → `entregado`), por lo que aparece en Comandas y Mesas.
- `pos_request_id` evita duplicados por doble toque o reintentos de red; las notas de cada plato están en `quote_items.kitchen_note`.
- Imprimir falla **sin deshacer el pedido**. Reimprimir y emitir precuenta no registran otros pedidos. Un pedido guardado permanece congelado en POS hasta tocar **Nuevo pedido**.
- Cobrar después de guardar vincula la venta al pedido con `link_pos_kitchen_invoice` (sin cambiar su estado de preparación).
- La RPC comprueba que el usuario sea miembro de la empresa y que su rubro sea `restaurante`. La separación de empresas se conserva en RLS de lectura de `quotes` y `quote_items`.

### Prueba manual sin impresora

1. En una **empresa con rubro restaurante**, Mesas → Tomar pedido → Mesa 4 → selecciona dos platos → Ver detalle → anota «sin cebolla» en uno.
2. Pulsa **Guardar y comanda**. Debe informar «Pedido COT-… guardado en Comandas». Puedes cancelar el diálogo de PDF: el pedido ya debe existir.
3. Cierra POS: en Mesas/Comandas debe verse el pedido con mesa 4, cantidad y nota de cocina. Avanza `nuevo` → `preparando` → `listo` → `entregado`.
4. Antes de cerrar POS, pulsa **Reimprimir** varias veces y **Precuenta**: **solo debe haber un registro** para ese pedido. Puedes comprobarlo también con la consulta de abajo.
5. En POS, pulsa **Nuevo pedido** para añadir otra ronda. Debe crear un pedido distinto, no reemplazar el anterior.
6. Repite sin mesa (para llevar); debe aparecer en Comandas, no en la cuadrícula de mesas.
7. Cambia a otra empresa y comprueba que el pedido no aparezca allí.
8. Prueba sin internet al guardar: la app no debe mostrar «Comanda enviada a cocina» si no se guardó; al recuperar conexión reintenta **el mismo** pedido. No crees otro mientras el primero esté pendiente.
9. Verifica Cobrar y Más opciones para confirmar el vínculo pedido/venta. El sistema **no convierte una comanda ni una precuenta en comprobante SUNAT** por sí mismo.

Consulta de diagnóstico (solo lectura; ejecutar en Supabase SQL Editor con acceso de administrador):

```sql
select q.id, q.org_id, q.number, q.table_label, q.fulfillment,
       q.kitchen_status, q.pos_request_id, q.invoice_id, q.created_at,
       count(i.id) as platos
from public.quotes q
left join public.quote_items i on i.quote_id = q.id
where q.pos_request_id is not null
group by q.id
order by q.created_at desc
limit 30;
```

### Estado de verificación

Código y migración preparados, pero **no ejecutados contra tu Supabase** y **sin compilación Flutter**, porque esta entrega no cuenta con SDK de Flutter/Dart ni acceso a tu proyecto remoto. Revisa `flutter pub get`, `flutter analyze`, `flutter test` y prueba dispositivos/impresora antes de usar en producción.
