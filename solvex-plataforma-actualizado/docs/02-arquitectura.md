# 2. Arquitectura de Solvex Hub

## Piezas

```
                    ┌──────────────────────────── Solvex Hub (Node 22+, sin dependencias) ───────────────────────────┐
  Sitio web  ──────▶│ /v1/public/*   solicitudes · catálogo · pedir enlace de pago · libro de reclamaciones          │
  (estático)        │                                                                                                 │
  Cliente   ──────▶│ /p/<token>      página de pago (Culqi o reporte de Yape/transferencia)                         │
                    │                                                                                                 │
  Culqi     ──────▶│ /webhooks/culqi/<secreto>   (se confirma consultando la API de Culqi)                          │
                    │                                                                                                 │
  Equipo    ──────▶│ /panel  + /api/admin/*   sesión + 2FA + roles + CSRF + auditoría  ◀── tiempo real (SSE)       │
  Solvex            │                                                                                                 │
                    │  SQLite (datos personales cifrados) · bitácora encadenada · programador cada minuto            │
                    └───────┬───────────────────────────────────────────────┬────────────────────────────────────────┘
                            │ webhook firmado (HMAC + token Ed25519)        ▲ consulta cada 5 min (clave de API)
                            ▼                                               │
            Barbería SaaS (Laravel)  ·  Restaurante  ·  Sistemas a medida  ·  Productos instalables (/v1/activate)
```

Cada **producto** (barbería, restaurante, a medida, instalable) es independiente: tiene sus planes y sus **instancias** (despliegues). Una instancia SaaS aloja muchos negocios; cada negocio es una **licencia** identificada por `tenant_ref` (el slug de la barbería).

## Modelo de datos (resumen)

| Tabla | Para qué |
|---|---|
| `clients` | Clientes de Solvex. Documento, contacto, correo, celular, dirección y notas **cifrados**; RUC/DNI único por índice ciego. |
| `products`, `plans` | Catálogo. Planes por días, meses, años o pago único; precio, implementación, prueba, gracia, funciones/límites. |
| `instances` | Despliegues de un producto: URL del webhook, hash de la clave de API, secreto del webhook cifrado, IPs permitidas. |
| `licenses` | Cliente × producto × plan. Copia el precio y periodo del plan (cambiar el plan no altera licencias vivas). Fechas de vigencia y gracia en UTC; zona horaria propia. |
| `license_grants` | Cada extensión o reverso de vigencia, con motivo (solo inserción). |
| `license_events` | Línea de tiempo de estados (solo inserción). |
| `invoices` | Cobros internos con enlace de pago secreto; una sola renovación viva por ciclo (índice único). |
| `payments` | Pagos; el mismo número de operación no entra dos veces; un pago cerrado no se edita ni se borra (triggers). |
| `credits` | Saldo a favor (solo inserción). |
| `outbox`, `deliveries` | Eventos hacia los productos y sus entregas con reintentos. |
| `notifications` | Cola de correos y WhatsApp (destinatario y contenido cifrados). |
| `leads`, `tickets`, `expenses`, `complaints` | Comercial, soporte, finanzas, Libro de Reclamaciones. |
| `users`, `sessions` | Equipo: scrypt, TOTP cifrado, códigos de respaldo (hash), sesiones (hash del token). |
| `audit_log` | Bitácora encadenada con HMAC, solo inserción. |

## Estados de una licencia

```
            activar (prueba)            vence (sin gracia en prueba)
 pendiente ─────────────────▶ prueba ──────────────────────────────┐
     │  primer cobro pagado                                          ▼
     └──────────────▶ activa ──vence──▶ gracia ──termina la gracia──▶ suspendida (auto)
                        ▲                 │                              │
                        └─────── pago ────┴────────── pago ──────────────┘   (reactivación automática)

 suspendida (manual): solo la levanta una persona; un pago extiende fechas pero no la levanta.
 cancelada: baja; no se reactiva con pagos (el dinero va a saldo a favor y se avisa).
```

**Regla de oro:** el estado se **calcula** con las fechas en cada consulta (`effective()`), y el programador solo registra el cambio y avisa. Si el servidor estuvo apagado, al volver todo responde bien.

Modo que recibe el producto: `full` (activa/prueba), `warning` (gracia), `restricted` (suspendida/cancelada: solo pagar o exportar), `blocked` (pendiente).

## Reglas de vigencia

- Un ciclo mensual que empieza el 19 cubre hasta el 18 del mes siguiente, a las 23:59:59 de la zona de la licencia. El **día ancla** evita que las fechas se corran (31 → 28/29 en febrero → 31 en marzo).
- Pago estando activa, en prueba o en gracia: el ciclo nuevo **continúa** desde el fin del anterior.
- Pago estando suspendida: el ciclo nuevo **empieza el día del pago** (configurable: "continuar").
- Pago parcial: no extiende; se acumula. Pago de más: saldo a favor que se aplica solo al siguiente cobro.
- Anular o reembolsar un pago: se revierte exactamente la vigencia que dio.

## Tiempo real hacia los productos

1. El cambio de la licencia y el evento se guardan **en la misma transacción** (patrón outbox): nunca hay uno sin el otro.
2. El despachador envía el webhook al instante: cuerpo con `Solvex-Timestamp` y `Solvex-Signature: v1=HMAC-SHA256(secreto, ts.cuerpo)`, y dentro el **token Ed25519** con el estado completo.
3. Reintentos: 30 s, 1, 2, 5, 10, 20, 30 min, 1, 2, 4, 8, 12 h. Las entregas viejas de la misma licencia se reemplazan (el token nuevo trae el estado final).
4. El producto además consulta cada 5 minutos (`/v1/instance/licenses`).
5. El token vence en ≤ 72 h y **nunca después del corte**, así que el producto corta a tiempo aunque no le llegue nada.

## Capas de seguridad

| Capa | Medida |
|---|---|
| Red | Hub en `127.0.0.1` detrás de Caddy/Nginx con HTTPS; opcional lista de IPs y Cloudflare Access para el panel. |
| HTTP | CSP estricta, HSTS, `X-Frame-Options: DENY`, `nosniff`, sin CORS en la API del panel, límite de tamaño, tiempo límite. |
| Identidad | scrypt, 2FA TOTP obligatorio con anti-repetición, códigos de respaldo, bloqueo por cuenta, sesiones con rotación, inactividad 30 min, máximo 10 h. |
| Autorización | Roles en el servidor; acciones delicadas con confirmación 2FA (10 min). Cuatro ojos para pagos (opcional). |
| Datos | AES-256-GCM por campo con AAD (tabla, columna, fila), índice ciego HMAC, `secure_delete`, respaldos cifrados con otra llave. |
| Integridad | Triggers de solo inserción, pagos cerrados inmodificables, bitácora encadenada con HMAC verificable. |
| Integraciones | Clave de API por instancia (solo hash), IPs permitidas, webhooks firmados, tokens Ed25519 con `aud`, SSRF bloqueado. |
| Público | Enlaces de pago de 256 bits, respuestas que no revelan si un cliente existe, trampas para robots, límites por IP. |

## Decisiones

- **Node 22+ sin dependencias** en lugar de Express + paquetes: menos superficie de ataque y nada que actualizar de terceros. El código existente de cobros ya era Node.
- **Separado de la barbería (Laravel)**: si un producto se compromete, no compromete las licencias ni los cobros de los demás.
- **SQLite**: un archivo, transacciones ACID, respaldos simples; sobra para cientos de clientes. Todo el SQL está en los servicios por si se migra a PostgreSQL.
- **Comprobantes SUNAT fuera del Hub**: los recibos del Hub son internos. La boleta/factura electrónica se emite con un OSE/PSE (siguiente fase: integración automática al aprobar un pago).
