# 3. Integrar un producto con Solvex Hub

Guía para cualquier sistema nuevo (barbería, restaurante, a medida). Para la barbería en Laravel ya está el kit listo: `integraciones/laravel-barberia/LEEME.md`. Para Node: `integraciones/node/solvex-license.js`.

## Conceptos

| Término | Qué es |
|---|---|
| Producto | Un sistema que vende Solvex (Barbería, Restaurante...). Se crea en el panel, sin programar. |
| Plan | Precio y periodo (mensual, trimestral, anual, pago único), días de prueba y de gracia, funciones/límites. |
| Instancia | Un despliegue del producto (ej. "Barbería SaaS · producción"). Tiene su clave de API y su secreto de webhook. |
| Licencia | Un negocio usando un producto. En SaaS se identifica con `tenant_ref` (el slug del negocio en tu sistema). |
| Token | Respuesta firmada (Ed25519) con el estado de una licencia. Tu sistema solo cree lo que trae un token válido. |

## Contenido del token

```json
{
  "iss": "solvex-hub", "aud": "ins_...", "sub": "lic_...", "jti": "tok_...", "iat": 1760900000, "nbf": 1760899940, "exp": 1761159200,
  "lic": "LIC-00012", "tenant": "don-corte", "product": "BARBERIA", "plan": "MENSUAL",
  "status": "gracia", "mode": "warning", "suspension": null,
  "auto_cut": true, "period_end": "2026-11-19T04:59:59.999Z", "grace_end": "2026-11-24T04:59:59.999Z", "cut_at": "2026-11-24T04:59:59.999Z",
  "features": { "max_branches": 1, "max_barbers": 6, "online_payments": true },
  "message": "Pago pendiente. El servicio se suspenderá el 23 de noviembre de 2026 si no se registra el pago.",
  "pay_url": "https://hub.solvex.pe/p/...."
}
```

Verificación obligatoria, en este orden: formato `cabecera.contenido.firma` → `alg = EdDSA` y `typ = slx-license+jwt` (rechaza cualquier otro, incluido `none`) → firma con la llave pública → `iss = solvex-hub` → `aud = tu instancia` → `nbf`/`exp` con ±2 min de tolerancia → descarta tokens con `iat` menor al último aplicado.

Decisión local: si `mode` es `full`/`warning`, `auto_cut` es `true` y ya pasó `cut_at` (o `grace_end`), trata el negocio como `restricted` aunque no te haya llegado aviso.

## Qué hacer en cada modo

| Modo | Personal | Dueño | Web pública | Mensaje |
|---|---|---|---|---|
| `full` | Normal | Normal | Normal | — |
| `warning` | Normal | Normal + aviso con `pay_url` | Normal | `message` |
| `restricted` | Bloqueado | Solo pagar, exportar datos y salir | Sin reservas nuevas; las citas ya pagadas siguen visibles y cancelables | `message` + botón `pay_url` |
| `blocked` | Bloqueado | Pantalla "aún no activado" | Sin reservas | `message` |

## API para instancias

Autenticación: `Authorization: Bearer slxk_xxxxxxxx_<secreto>` (opcionalmente restringida por IP).

| Método y ruta | Respuesta |
|---|---|
| `GET /v1/instance/licenses` | `{ server_time, next_poll_seconds, licenses: [{ tenant_ref, license_code, token }] }` |
| `GET /v1/instance/licenses/:tenant_ref` | `{ tenant_ref, license_code, token }` o `404 SIN_LICENCIA` (trátalo como no habilitado) |
| `POST /v1/instance/heartbeat` | `{ version, tenants }` → registra "visto por última vez" |
| `POST /v1/instance/trials` | Prueba gratis autoservicio (ver abajo) → `201 { created: true, tenant_ref, license_code, token }` · `200 { created: false, … }` si ese `tenant_ref` ya tenía licencia · `409 PRUEBA_USADA` si el documento ya usó su prueba en este producto |
| `GET /.well-known/solvex-license-keys.json` | Llaves públicas vigentes y anunciadas (`kid`, `pem`, `raw_b64`) |

### Prueba gratis autoservicio (`POST /v1/instance/trials`)

Para productos SaaS donde el cliente se registra solo (por ejemplo FacturaVoz): la instancia pide la prueba en nombre
del cliente y recibe el token firmado al instante. Reglas de seguridad:

- Cuerpo validado: `tenant_ref` (1–100, `[A-Za-z0-9._:-]`), `doc_type` (`RUC` | `DNI`), `doc_number` (RUC con dígito
  verificador válido; DNI de 8 dígitos), `business_name` (2–160), `email` y `phone` opcionales, `plan_code` opcional.
- **Una prueba por documento y producto** (`409 PRUEBA_USADA`, queda en auditoría). Repetir la llamada con el mismo
  `tenant_ref` es idempotente (no crea otra licencia).
- Si no se envía `plan_code`, se usa el plan activo más alto del producto que tenga días de prueba.
- Límites: 60 pruebas por hora por instancia y 120 por hora por IP. Todo queda en la bitácora (`licencia.prueba_autoservicio`).
- Al vencer la prueba la licencia pasa sola a `restricted` (o `blocked` tras la gracia) con el `pay_url` del plan.

```js
const r = await fetch(HUB + '/v1/instance/trials', {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + API_KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ tenant_ref: orgId, doc_type: 'RUC', doc_number: '20100070970', business_name: 'Mi Bodega SAC' }),
});
```

## Webhooks

`POST` a la URL configurada en la instancia, con:

```
Content-Type: application/json
Solvex-Event-Id: evt_...
Solvex-Timestamp: 1760900000
Solvex-Signature: v1=<hex HMAC-SHA256(secreto, timestamp + "." + cuerpo_crudo)>

{ "id": "evt_...", "type": "license.updated", "created_at": "...", "sent_at": "...",
  "data": { "license_code": "LIC-00012", "tenant_ref": "don-corte", "token": "<token firmado>" } }
```

Tipos: `license.updated` (cualquier cambio, incluido "retirada de esta instancia", que llega con `status: cancelada`) y `ping` (prueba). Responde `2xx` en menos de 10 s; si no, se reintenta hasta ~28 h. Verifica la firma con el **cuerpo crudo**, rechaza si el timestamp tiene más de 5 min y guarda `id` para no procesar dos veces.

## Productos instalables (en la computadora del cliente)

```
POST /v1/activate  { "license_key": "SLX-XXXXX-XXXXX-XXXXX-XXXXX", "fingerprint": "<huella del equipo>", "label": "Caja 1" }
POST /v1/refresh   { "license_key": "...", "fingerprint": "..." }
→ { "license_code": "LIC-00031", "token": "..." }   (aud = "onprem", fp = sha256("fp:" + huella))
```

El límite de equipos se define en la licencia; un equipo se puede revocar desde el panel. Guarda el token en disco y úsalo sin conexión hasta su `exp`.

## Plantillas de WhatsApp para aprobar en Meta

Categoría **Utilidad**, idioma `es`. El Hub envía la plantilla `slx_<nombre>` con las variables en este orden:

| Plantilla | Texto sugerido |
|---|---|
| `slx_recordatorio` | Hola {{1}}, tu servicio {{2}} vence el {{3}}. La renovación es de {{4}}. Paga aquí: {{5}} |
| `slx_enlace_pago` | Hola {{1}}, tu enlace de pago para {{2}} por {{3}}: {{4}} |
| `slx_gracia` | Hola {{1}}, tu servicio {{2}} venció. Se suspenderá el {{3}} si no se registra el pago de {{4}}. Paga aquí: {{5}} |
| `slx_suspension` | Hola {{1}}, tu servicio {{2}} fue suspendido por falta de pago. Tus datos se conservan. Al pagar ({{3}}) se reactiva al instante: {{4}} |
| `slx_reactivacion` | Hola {{1}}, recibimos tu pago. Tu servicio {{2}} está activo hasta el {{3}}. |
| `slx_pago_recibido` | Hola {{1}}, recibimos tu pago de {{2}} por {{3}}. Vigente hasta: {{4}}. Recibo: {{5}}. |
| `slx_pago_rechazado` | Hola {{1}}, no pudimos validar tu pago de {{2}} para {{3}}. Motivo: {{4}}. |

Solo se envían si el cliente tiene celular registrado y aceptó recibir avisos (consentimiento en el contrato).
