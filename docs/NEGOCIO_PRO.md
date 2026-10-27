# FacturaVoz v1.1 · "Negocio Pro"

Esta versión convierte FacturaVoz de "app para emitir comprobantes" en **el copiloto financiero del pequeño negocio peruano**:
cotiza, cobra, controla gastos y stock, y responde por voz. Todo sigue la regla de la casa: **coste cero fijo**
(Supabase, Vercel Hobby, Groq y Resend en plan gratis; Mercado Pago solo cobra comisión por venta aprobada).

---

## 1. Qué hay de nuevo

### Frente A · Experiencia premium
| Qué | Dónde |
|---|---|
| **Dock de cristal flotante** con 4 pestañas (Inicio · Cotizar · Cobrar · Negocio) y micrófono central. Toque = dictar factura; **mantener presionado = Copiloto**. Cambio de pestaña con fundido + escala, estado conservado, el dock se esconde con el teclado y "atrás" vuelve a Inicio. | `screens/shell.dart` |
| **Sistema de movimiento** reutilizable: `Haptics` (tap, éxito, error con patrones distintos), `PremiumRoute` (transición en eje Z), `FadeThrough`, `Shimmer` (brillo que recorre los esqueletos), `showSuccess` (check animado que se dibuja), `ProgressRing`, `DualBars`, `SegmentBar`, `MetricTile`, `PulseDot`, `AiOrb` (orbe que respira y reacciona a tu voz). Todo respeta "Reducir animaciones". | `ui/motion.dart` |
| `Pressable` ahora rebota con resorte (elasticOut) al soltar; los esqueletos de carga usan shimmer. | `ui/widgets.dart` |
| **Avisos del día** en Inicio: pagos reportados por confirmar, deudas vencidas (y a quién cobrar primero), lo que vence esta semana, ritmo vs. el mes pasado y stock por agotarse. Un toque lleva a la acción. | `home.dart`, `finance.dart` |

### Frente B · Módulos de negocio
| Módulo | Cómo funciona |
|---|---|
| **Cotizaciones** | Se dictan igual que una factura ("Cotización para Corpax: 3 sillas a 150"). Se envían por WhatsApp como **enlace web** (`/cotizacion/<token>`): el cliente la ve en su celular y toca **Aceptar** (deja su nombre). La app lo celebra **en vivo** (Realtime) y te llega un correo. Luego **Convertir en factura** = 1 toque (eliges contado o crédito 7/15/30 días). Cero redigitación: la función SQL `convert_quote` copia cliente, líneas, impuesto y notas en una transacción. Tasa de cierre y monto "en negociación" en la cabecera. |
| **Cobros integrados** | Cada factura emitida tiene **enlace de cobro** (`/pagar/<token>`) con saldo, **Yape/Plin/CCI con botón Copiar** y, si conectas tu cuenta, **pago con tarjeta por Mercado Pago** (el webhook registra el cobro solo y marca la factura como pagada). Si el cliente paga por Yape/Plin, toca **"Ya pagué"** y a ti te llega el aviso para **confirmar con un toque**. |
| **Motor de cobranza** | Cron diario de Vercel (`/api/cron/collections`, 9:00 Lima): busca facturas al crédito por vencer o vencidas de las empresas que lo activaron y envía el recordatorio por correo con el enlace de pago. El tono sube por etapas (amable → vence hoy → vencida → firme → final). Cada etapa se envía **una sola vez** (`reminder_log`). Además, recordatorio por **WhatsApp con un toque** desde Cobranza (incluye el enlace de pago). |
| **Rentabilidad** | Pestaña "Negocio": ganancia del mes (ventas − gastos **sin IGV**), margen, cobrado vs. pagado (**flujo de caja real**), variación vs. mes anterior, 6 meses de ventas vs. gastos, en qué se va el dinero, **IGV estimado del mes** (IGV de ventas − crédito fiscal de compras). |
| **Escáner con IA** | Foto de una factura/boleta de papel → Groq Vision extrae proveedor, RUC, serie-número, fecha, ítems, subtotal, IGV, total y sugiere categoría → **Guardar como gasto** o **"Es una venta mía: digitalizarla"** (abre la factura ya llena con el cliente y las líneas). |

### El arsenal exclusivo (lo que ninguna app de la tienda tiene junto)
1. **Copiloto de voz bidireccional.** Una sola frase sirve para *preguntar* ("¿cuánto gané este mes?", "¿quién me debe más?", "¿qué se me acaba?") o para *ordenar* ("cotiza a Corpax 3 sillas a 150", "gasté 80 soles en gasolina", "cobra a los morosos"). Responde en pantalla con cifras clave **y en voz alta** (texto a voz en el dispositivo, gratis) y te deja a un toque de la acción. La IA solo ve un **resumen agregado** de la empresa (RPC `business_snapshot`, con RLS), nunca DNI/RUC ni correos de clientes.
2. **Conciliación por foto (Yape/Plin/banco).** Yape y Plin no tienen API para negocios pequeños; FacturaVoz lo resuelve leyendo la **captura de la constancia**: extrae monto, pagador y n.º de operación y **propone la factura correcta** (monto exacto del saldo + similitud de nombre tolerante a "Juan P. Pere*"). Un toque registra el cobro.
3. **Score de crédito por cliente (A/B/C/D).** Calculado de su historial real (días promedio de atraso, deuda vencida, peor atraso). Aparece **al elegir "Al crédito"** con un consejo concreto ("Pide 50 % de adelanto") y en cada deuda de Cobranza.
4. **Predicción de cobro + proyección de caja a 5 semanas.** Para cada factura se estima la fecha probable de pago según cómo paga ese cliente; se pondera por la probabilidad de su score y se resta tu ritmo de gasto de los últimos 90 días. Si una semana quedarías en negativo, te avisa con anticipación.
5. **Radar de quiebre de stock.** Stock opcional por producto que **se descuenta solo al emitir** (trigger en la base de datos). Con la velocidad de venta de los últimos 30 días predice "Cable HDMI se acaba en ~4 días".
6. **"Ya pagué" del cliente final + confirmación en vivo.** El circuito completo de cobro sin pasarela: enlace → cliente paga por Yape → avisa → tú confirmas → la factura se marca pagada y el score del cliente se actualiza.
7. **Cotización con aceptación del cliente en vivo** y conversión en 1 toque, con aviso por correo y celebración en la app.
8. **IGV estimado del mes** con crédito fiscal de los gastos escaneados: el pequeño negocio sabe cuánto le tocará pagar antes de que llegue el contador.

---

## 2. Cómo integrarlo (en este orden)

### 2.1 Supabase
1. SQL Editor → ejecuta **`backend/supabase/migrations/20261101_negocio_pro.sql`** (idempotente; requiere las migraciones 20261027–20261031).
2. Database → Replication: verifica que `quotes` y `payment_claims` estén en la publicación `supabase_realtime` (la migración las agrega si existe).
3. Advisors → Security: debe seguir sin errores.

> La migración también corrige un detalle previo: la fecha de emisión por defecto de las facturas era la de **UTC** (después de las 19:00 en Lima salía con fecha de mañana). Ahora usa la hora de Lima.

### 2.2 Vercel (backend)
Variables nuevas (Settings → Environment Variables):

| Variable | Obligatoria | Para qué |
|---|---|---|
| `SECRETS_KEY` | Sí, si usarás Mercado Pago | Cifra el token de Mercado Pago de cada empresa. `openssl rand -base64 32`. **No la cambies después** (los tokens guardados dejarían de abrirse). Marca "Sensitive". |
| `CRON_SECRET` | Sí, para la cobranza automática | Ya existía para importaciones; ahora también protege `/api/cron/collections`. |
| `PUBLIC_BASE_URL` | Recomendada | `https://factura-voz-two.vercel.app` (enlaces en correos y webhook de Mercado Pago). |
| `VISION_MODEL` | No | Por defecto `qwen/qwen3.8-27b` (modelo con visión vigente en Groq). |
| `COLLECTIONS_DAILY_LIMIT` | No | Tope de correos de cobranza por corrida (80 por defecto; Resend gratis = 100/día). |

Luego: reemplaza `backend/` → `git push` → Vercel redepliega. `vercel.json` ya incluye el segundo cron (diario).

Pruebas rápidas:
```
curl -i https://TU-API/cotizacion/abc        # 200 con "Enlace no válido" (página pública, no redirige a /login)
curl -i -X POST https://TU-API/api/assistant # 401
curl -i https://TU-API/api/cron/collections  # 401 sin CRON_SECRET
```

### 2.3 App Flutter
```
cd app
flutter pub get                      # nuevas dependencias: image_picker, flutter_tts
dart run tool/post_create.dart       # agrega permisos de cámara/fotos (iOS) y consulta de voz (Android 11+)
flutter analyze && flutter test      # incluye test/finance_test.dart (10 pruebas nuevas)
flutter run --no-enable-impeller --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=...
```
El comando de compilación no cambia.

### 2.4 Correo (Resend)
La cobranza automática y los avisos de cotización aceptada/pago reportado usan Resend. **Sin dominio verificado** Resend solo
entrega a tu propio correo; para escribir a tus clientes verifica tu dominio y define `RESEND_FROM`.

### 2.5 Mercado Pago (opcional, por empresa)
En la app: Ajustes → **Cobros y recordatorios** → Tarjeta con Mercado Pago → pegar el **Access Token de producción** (`APP_USR-…`).
El servidor lo valida contra Mercado Pago, lo **cifra** (AES-256-GCM) y nunca lo devuelve a la app.

---

## 3. Verificación manual sugerida
1. Dicta una cotización → Enviar al cliente → abre el enlace en otro celular → Aceptar → la app muestra "¡X aceptó!" → Convertir en factura (crédito 15 días) → la factura aparece con vencimiento.
2. Emite/marca como enviada → "Enviar enlace de cobro" → en el enlace toca "Ya pagué" (Yape) → en Cobranza aparece → Confirmar → la factura pasa a Pagada.
3. Usuario de OTRA empresa: no puede ver cotizaciones, enlaces ni pagos reportados ajenos (probado a nivel SQL con RLS, ver §5).
4. Producto con stock 10 → vende 4 y emite → stock 6. Ajuste "Entrada 30" → 36.
5. Escanea una boleta de compra → Guardar como gasto → aparece en Negocio con su IGV como crédito fiscal.
6. Copiloto: "¿quién me debe más?" (respuesta hablada) y "gasté 50 soles en movilidad" (abre el gasto prellenado).
7. Captura de Yape de un pago real → Cobranza → "Conciliar captura de pago" → propone la factura correcta.

---

## 4. Tap-to-Pay (cobrar con tarjeta acercándola al celular): evaluación de viabilidad

**Conclusión: hoy NO es viable implementarlo dentro de FacturaVoz por cuenta propia; sí es viable como alianza.**

- Leer tarjetas por NFC en el teléfono (SoftPOS) exige ser o integrarse con un **adquirente/procesador certificado**
  (estándar PCI MPoC/CPoC, certificación de kernel EMV contactless, atestación del dispositivo). No hay un SDK abierto y gratuito
  que una app independiente pueda usar sin contrato.
- En Perú ya existen soluciones de los adquirentes: por ejemplo, **Niubiz VendeMás** convierte el celular en POS gratis
  (cobros contactless, QR de Yape/Plin, links de pago); y Mercado Pago ofrece "Point Tap" en otros países de la región.
  Ninguno publica un SDK de autoservicio para terceros: la integración requiere acuerdo comercial.
- **Camino recomendado (por fases):**
  1. *Ya implementado:* enlace de pago con tarjeta vía Mercado Pago Checkout Pro (el cliente paga desde SU celular) + conciliación automática.
  2. *Corto plazo:* botón "Cobrar con POS del celular" que abra la app del adquirente con el monto (si exponen deep link) y luego
     concilia con la foto de la constancia (ya implementado).
  3. *Alianza:* propuesta a Niubiz/Izipay/Mercado Pago como "partner ISV" para su SDK SoftPOS. FacturaVoz aporta volumen de comercios
     y la facturación electrónica integrada; es el argumento comercial.

---

## 5. Seguridad y calidad (cómo se verificó)
- **Base de datos:** la migración se ejecutó sobre una réplica local de PostgreSQL 16 con roles y `auth.uid()` como en Supabase,
  aplicando `schema.sql` y TODAS las migraciones en orden (dos veces: idempotente). Se probaron como usuarios reales con RLS:
  crear y convertir cotización (y que convertir dos veces devuelve la misma factura), bloqueo de estados forzados, enlace de cobro
  solo para facturas emitidas, pago reportado → cobro → factura pagada, webhook idempotente (no duplica), aislamiento total entre
  empresas, candidatos de cobranza (y que no repite etapas), descuento de stock al emitir, snapshot de la IA, score de pago y upserts
  tal como los genera PostgREST.
- **Backend:** 54 pruebas (15 nuevas: cifrado, escáner, copiloto, cobranza, Mercado Pago, extracción de JSON) y verificación de tipos
  estricta de rutas y páginas.
- **App:** `test/finance_test.dart` cubre score, antigüedad, predicción de pago, proyección de caja, rentabilidad, avisos y conciliación.
  ⚠️ No se pudo ejecutar `flutter analyze` en el entorno de construcción (sin SDK de Flutter): ejecútalo antes de publicar y
  reporta cualquier aviso para corregirlo al instante.
- Todas las tablas nuevas tienen RLS e índice en cada FK; las funciones `SECURITY DEFINER` viven en `private` con `search_path = ''`.
- Las páginas públicas solo se abren con un token de 64 hex (244 bits de azar) y muestran lo que ya figura en el comprobante.
- La IA nunca recibe documentos de identidad ni correos; el texto del usuario y las fotos se tratan como **datos**, no instrucciones.

## 6. Limitaciones conocidas (decisiones tomadas)
- El stock se descuenta por **nombre exacto** del producto (las líneas de factura no guardan el id del producto). Al anular con nota
  de crédito el stock no se repone automáticamente: usa "Registrar entrada".
- La proyección de caja no conoce tu saldo bancario: muestra el **flujo neto** esperado desde hoy.
- El IGV estimado es **referencial** (no considera percepciones, retenciones ni regímenes especiales).
- Las cotizaciones no se editan una vez creadas: se duplican ("Duplicar como nueva").
