# 6. Impuestos, comprobantes electrónicos y Merchant of Record

> Esto no es asesoría tributaria. Las reglas se tomaron de la Ley del IGV y de informes de SUNAT (fuentes al final), pero **tu contador debe confirmar** el régimen, la inscripción como exportador y el tratamiento de cada tipo de cliente antes de cobrar en serio.

## 6.1 Qué hace el sistema (resumen)

| Cliente | Impuesto | Comprobante | Lo decide |
|---|---|---|---|
| Domiciliado en el Perú con **RUC** | IGV 18 % | **Factura** electrónica | `country = PE`, `doc_type = RUC` |
| Domiciliado en el Perú con **DNI / CE / pasaporte** | IGV 18 % | **Boleta** electrónica | `country = PE` |
| Del extranjero, **Solvex inscrito** en el Registro de Exportadores de Servicios | 0 % (exportación de servicios) | **Factura de exportación** | `country ≠ PE` + ajuste `export_registered` |
| Del extranjero, **Solvex NO inscrito** | IGV 18 % (no califica como exportación) | Factura | `country ≠ PE` sin inscripción |
| Del extranjero, Solvex **inscrito para cobrar el impuesto de ese país** | La tasa de ese país | Factura de exportación por la base | Hay una regla en `tax_rules` para ese país |
| Cobrado por un **Merchant of Record** (Paddle, Lemon Squeezy) | Lo calcula y declara el MoR | Lo emite el MoR al cliente final | `licenses.billing_provider` |
| Solvex en **Nuevo RUS** | No se cobra IGV | Boleta (fuera del Hub) | ajuste `regime = nrus` |

Reglas de oro:

1. **El impuesto se calcula antes de cobrar**, en el servidor, y queda guardado en el cobro: base, impuesto, total, tasa, tratamiento y el motivo.
2. **Con dinero aplicado, el desglose no cambia.** Lo impide la base de datos con triggers, no solo el código.
3. **Por cada pago aprobado, un comprobante** por el monto recibido. Por cada reembolso, una **nota de crédito**.
4. Si el proveedor de comprobantes o SUNAT fallan, **el pago y la licencia siguen**. El comprobante se reintenta solo.

## 6.2 Requisitos legales que el sistema asume

- **IGV 18 %** = 16 % de IGV + 2 % de Impuesto de Promoción Municipal. Está como dato en `tax_rules` (no en el código), con su fecha de vigencia.
- **Exportación de servicios** (Ley del IGV, art. 33, quinto párrafo). Según el informe SUNAT 179-2019, se exige:
  1. servicio prestado a título oneroso, con comprobante anotado en el Registro de Ventas;
  2. exportador domiciliado en el Perú;
  3. usuario **no domiciliado**;
  4. uso, explotación o aprovechamiento **en el extranjero**;
  5. exportador **inscrito previamente en el Registro de Exportadores de Servicios** de SUNAT.

  El Apéndice V (la antigua lista de servicios exportables) fue derogado por la Ley 30641. Si falta la inscripción, el sistema **cobra IGV** al cliente extranjero (operación "venta a no domiciliado que no califica como exportación"). Así no queda un impuesto sin cobrar que SUNAT pueda reclamar después.
- **Régimen.** En el Nuevo RUS no se emiten facturas ni se cobra IGV. Para cobrar IGV y emitir facturas necesitas RER, MYPE Tributario o General. Se cambia en **Configuración → Impuestos**.
- **Comprobante.** En servicios se emite al percibir la retribución, por el monto percibido. Por eso un abono parcial lleva su propio comprobante.
- **Precio al consumidor.** La web y la página de pago muestran el **precio total con IGV** (Código de Protección y Defensa del Consumidor).

**Pendientes para revisar con el contador.** El sistema no los calcula hoy:

- Detracciones en servicios a empresas por encima de S/ 700.
- Retenciones.
- Tipo de cambio para comprobantes en dólares.
- Si tu servicio concreto cumple el requisito de "uso en el extranjero".

## 6.3 Modelo de datos (migración v2)

La migración se aplica sola al iniciar el Hub y conserva todos los datos (`hub/src/db/migrations.js`). Las tablas con un `CHECK` nuevo se reconstruyen con el procedimiento oficial de SQLite: llaves foráneas desactivadas solo durante la migración y `foreign_key_check` antes de confirmar.

### Clientes
```sql
doc_type  TEXT CHECK (doc_type IN ('RUC','DNI','CE','PAS','EXT'))   -- EXT: Tax ID / NIT / RFC / VAT del país del cliente
country   TEXT NOT NULL DEFAULT 'PE'                                -- residencia fiscal ISO 3166-1: decide el impuesto
region    TEXT                                                       -- estado/provincia (impuestos subnacionales)
CHECK (doc_type <> 'RUC' OR country = 'PE')                          -- quien tiene RUC está domiciliado
```

### Planes y licencias (suscripciones)
```sql
plans.tax_mode       'incluido' | 'mas_impuesto'   -- ¿el precio ya trae IGV o se le suma?
licenses.tax_mode    (se copia del plan; editable por Finanzas)
licenses.billing_provider        'hub' | 'paddle' | 'lemonsqueezy' | 'stripe'   -- quién cobra
licenses.external_subscription_id, licenses.external_customer_id               -- vínculo con el MoR
UNIQUE (billing_provider, external_subscription_id)
```

### Cobros (`invoices`): desglose congelado
```sql
list_price_cents   -- precio ingresado (antes de aplicar el modo)
subtotal_cents     -- base imponible (valor de venta)
tax_cents          -- IGV / IVA / VAT
amount_cents       -- TOTAL cobrado  (subtotal + tax = amount, lo exige un trigger)
tax_rate_bp        -- tasa en puntos básicos (1800 = 18 %)
tax_treatment      -- gravado | exportacion | no_sujeto | impuesto_extranjero | mor
tax_operation      -- venta_interna | exportacion | no_domiciliado | nrus | extranjero | mor
tax_code, tax_label, tax_country, tax_note   -- regla aplicada y por qué (evidencia)
fiscal_doc         -- factura | boleta | ninguno
bill_to_enc        -- datos del adquirente al emitir (cifrados AES-256-GCM)
external_ref       -- id de la transacción del MoR
currency           -- PEN por defecto; los cobros del MoR guardan su moneda
```
Triggers: `invoices_tax_sum_*` (base + impuesto = total) e `invoices_tax_frozen` (con pagos, saldo aplicado o cerrado, no cambia ningún monto, tasa, tratamiento ni moneda).

### Pagos
```sql
method   ... | 'mor'         -- nuevo medio: cobrado por un Merchant of Record
provider TEXT                -- culqi | paddle | lemonsqueezy | stripe | NULL (manual)
currency                     -- la del cobro
```

### Reglas de impuesto (`tax_rules`)
```sql
country, region, code ('PE-IGV'), label ('IGV'), rate_bp (1800), customer_kind (todos|empresa|persona),
valid_from, valid_to, active, note
```
Si cambia el IGV, se crea la nueva tasa con su fecha y la anterior se cierra sola el día previo. Una regla para otro país significa **"Solvex está inscrito para cobrar ese impuesto allí"**.

### Comprobantes electrónicos (`fiscal_documents`)
```sql
kind              factura | boleta | nota_credito
series, number    UNIQUE (series, number) — correlativo por serie, nunca se reutiliza
invoice_id, payment_id, client_id
related_id        comprobante que corrige una nota de crédito (CHECK: solo las notas lo tienen)
note_reason       catálogo SUNAT 09: '01' anulación de la operación · '06' devolución total
operation         venta_interna | exportacion | no_domiciliado | nrus
subtotal_cents, tax_cents, total_cents (CHECK suma), tax_rate_bp, currency
customer_enc      datos del adquirente cifrados
status            pendiente → enviado → aceptado | rechazado | error
attempts, next_attempt_at, last_error, sunat_code, sunat_description, hash, qr, pdf_url, xml_url, cdr_url
```
Índices únicos: un comprobante vivo por pago y una nota de crédito por comprobante. Triggers: no se borra, y una vez emitido no cambian sus montos, su número ni sus datos.

### Avisos de pasarelas (`gateway_events`)
Se agregaron `payload_enc` (copia cifrada del aviso), `attempts` y `last_error`. La llave primaria es la idempotencia: `proveedor:id_del_evento`.

## 6.4 Cálculo antes de cobrar (`hub/src/services/tax.js`)

Montos en céntimos enteros y tasas en puntos básicos. El redondeo es al céntimo, mitad hacia arriba. **Nunca se usan decimales flotantes para dinero.**

```text
función cotizar(cliente, precio, modo, fecha):
    ajustes ← Configuración → Impuestos
    igv ← tax_rules vigente para PE en esa fecha          # 18 % hoy
    si ajustes.regimen = "nrus":
        trato ← { no_sujeto, 0 %, boleta }
    si no, si cliente.pais = "PE":
        trato ← { gravado, igv, factura si RUC; si no, boleta }
    si no, si existe tax_rules vigente para cliente.pais (y región):
        trato ← { impuesto_extranjero, esa tasa, factura de exportación }
    si no, si ajustes.inscrito_exportador:
        trato ← { exportacion, 0 %, factura de exportación }
    si no:
        trato ← { gravado, igv, operación no_domiciliado, factura }

    tasaIncluida ← (régimen nrus ? 0 : igv)               # el precio "incluido" trae el IGV peruano
    si modo = "incluido":
        base ← redondear(precio × 10000 / (10000 + tasaIncluida))
        impuesto ← (trato.tasa = tasaIncluida) ? precio − base : redondear(base × trato.tasa / 10000)
    si no:                                                  # "mas_impuesto"
        base ← precio
        impuesto ← redondear(base × trato.tasa / 10000)
    devolver { base, impuesto, total: base + impuesto, trato, motivo }
```

Ejemplos (verificados en las pruebas):

| Precio del plan | Modo | Cliente | Base | Impuesto | Total |
|---|---|---|---|---|---|
| S/ 150 | incluido | Perú (RUC) | 127.12 | 22.88 | **150.00** (factura) |
| S/ 100 | más impuesto | Perú (DNI) | 100.00 | 18.00 | **118.00** (boleta) |
| S/ 150 | incluido | EE. UU., inscrito | 127.12 | 0.00 | **127.12** (exportación) |
| S/ 150 | incluido | EE. UU., no inscrito | 127.12 | 22.88 | **150.00** (IGV) |

**Cuándo se calcula y recalcula:**

- **Al emitir el cobro**: renovaciones automáticas, alta, cobro manual.
- **Mientras no entre dinero**, se recalcula al abrir el enlace de pago, justo antes del cargo con tarjeta y al editar el país o el documento del cliente. Si el total cambió mientras el cliente tenía la página abierta, el cargo se detiene y le pide recargar: nunca se cobra un monto distinto del mostrado.
- **Con un abono**, queda fijo.

## 6.5 Del pago al comprobante (`hub/src/services/einvoice.js`)

```text
al aprobar un pago (misma transacción de base de datos):
    si la emisión está activa y el cobro no es de un MoR:
        partes ← proporción del pago sobre el cobro      # completo = exacto; parcial = proporcional
        número ← siguiente correlativo de la serie        # F001 / B001
        cliente ← copia cifrada de sus datos actuales
        si faltan datos (p. ej. dirección en una factura) → estado "error" con mensaje claro
        si no → estado "pendiente"
programador (cada minuto) y aviso inmediato:
    para cada pendiente:
        si es reintento → primero CONSULTAR al proveedor (¿ya lo tiene?) → si sí, se toma
        si no → ENVIAR
        aceptado | enviado (esperando SUNAT, se consulta cada 10 min) | rechazado (alerta)
        falla de red / 5xx → reintento con espera: 1, 2, 5, 10, 30, 60, 120, 240, 360 min
        dato inválido → "error" (se corrige al cliente y se pulsa Reintentar: conserva el número)
al reembolsar o anular un pago:
    nota de crédito (06 devolución total | 01 anulación) por el total del comprobante
    se envía solo cuando SUNAT aceptó el original
```

**Proveedor.** Lo tienes en `hub/src/gateways/einvoice.js`, con la misma interfaz para todos. Nubefact viene listo, mapeado según su Manual de integración JSON:

| Campo | Valor |
|---|---|
| `tipo_de_comprobante` | 1 factura · 2 boleta · 3 nota de crédito |
| `sunat_transaction` | 1 venta interna · 2 exportación · 29 no domiciliado que no califica como exportación |
| `cliente_tipo_de_documento` | 6 RUC · 1 DNI · 4 CE · 7 pasaporte · 0 no domiciliado |
| `tipo_de_igv` | 1 gravado · 16 exportación |
| `unidad_de_medida` | ZZ (servicio) |
| `codigo_unico` | `serie-número`, para que el proveedor rechace duplicados |

**Antes de producción.** Nubefact pide emitir desde tu sistema, con la ruta y token de **DEMO**, una factura, una boleta, una exportación, una nota de crédito y sus consultas. En la exportación se envía `porcentaje_de_igv: 0` y el valor en `total_inafecta`, según el ejemplo publicado de su API. **Compáralo con su "ejemplo 6" de la cuenta DEMO** y, si difiere, solo se ajusta `toNubefact()`.

**Panel → Cobros y pagos → Comprobantes:**

- filtros por estado y mes;
- PDF del proveedor;
- botón Reintentar;
- **Registro de ventas del mes en CSV** para el contador. Las notas de crédito restan.

En **Inicio** aparecen el "IGV del mes" y los comprobantes con problemas.

## 6.6 Escalar a otros países

Hay tres caminos, de menos a más automático:

1. **Exportación desde el Perú (lo que tienes hoy).** Te inscribes como exportador y cobras 0 % de IGV a clientes del extranjero. El cliente paga el impuesto de su país por su cuenta (en muchos países B2B, por "reverse charge"). Es lo más simple y sirve para empresas.
2. **Inscribirte en otros países.** Por ejemplo, IVA digital en Chile, Colombia o México, o el régimen OSS de la UE. Agregas la regla en **Configuración → Impuestos → Nueva tasa** y el Hub cobra ese impuesto a clientes de ese país. Solo conviene donde ya tengas volumen: cada inscripción trae declaraciones mensuales.
3. **Merchant of Record (MoR).** Paddle o Lemon Squeezy venden en su nombre, calculan el impuesto según la ubicación del comprador (IP, país de la tarjeta y dirección), lo cobran y lo declaran en cada país. Te pagan el neto. Es el camino para vender a consumidores en muchos países sin inscribirte en ninguno.
   - **Stripe Tax** solo **calcula**: no te libera de inscribirte ni de declarar.
   - Stripe no aparece hoy entre los países donde puede registrarse una empresa peruana (sí Brasil y México). Usarlo exigiría una empresa en otro país, como una LLC en EE. UU.
   - Por eso el adaptador listo es para Paddle y Lemon Squeezy. Confirma con cada uno que aceptan vendedores del Perú y cómo te pagan.

**Cómo se reparte el trabajo:** el Hub sigue cobrando a clientes del Perú por Culqi, con boleta o factura, y el MoR a clientes del extranjero. Cada licencia dice quién la cobra (`billing_provider`).

**Contabilidad con MoR:** el cliente final le compra al MoR, y Solvex le presta el servicio al MoR. A ese MoR se le emite **una factura de exportación por cada liquidación** (por ejemplo, mensual), no una por cada venta. Por eso el Hub no emite comprobantes para los pagos con `method = 'mor'`.

## 6.7 Webhooks de un Merchant of Record

**Dirección:** `POST https://hub.solvex.pe/webhooks/mor/paddle` (o `/lemonsqueezy`). Se activa al poner `PADDLE_WEBHOOK_SECRET` o `LEMONSQUEEZY_WEBHOOK_SECRET` en el `.env`.

### Estructura recomendada (implementada en `hub/src/services/mor.js`)

```text
1. Leer el cuerpo CRUDO (sin interpretar) — la firma se calcula sobre los bytes exactos.
2. Verificar la firma con comparación en tiempo constante:
     Paddle:        Paddle-Signature: ts=…;h1=…   HMAC-SHA256(secreto, ts + ":" + cuerpo); rechaza si ts tiene más de 5 min
     Lemon Squeezy: X-Signature: hex(HMAC-SHA256(secreto, cuerpo))
   Sin firma válida → 401 y queda en la auditoría.
3. Normalizar a un evento interno único (el resto del sistema no conoce a Paddle ni a Lemon Squeezy):
     payment | refund | chargeback | payment_failed | subscription_linked | subscription_canceled | ignored
4. Idempotencia: INSERT en gateway_events con llave "proveedor:id_evento". Si ya existía → 200 "duplicado".
5. Guardar el aviso cifrado y procesarlo en UNA transacción.
6. Responder:
     200  aplicado / duplicado / ignorado / rechazado por regla de negocio (no tiene sentido reintentar)
     503  "reintenta luego" (p. ej. un reembolso que llegó antes que su pago); se borra la marca de idempotencia
     500  error inesperado; también se borra la marca para que el reintento del MoR se procese
```

### Mapeo de eventos

| Interno | Paddle Billing | Lemon Squeezy | Qué hace el Hub |
|---|---|---|---|
| `payment` | `transaction.completed` | `subscription_payment_success` (y `order_created` solo si el checkout trae `solvex_kind=unico`) | Registra un cobro `mor` con base, impuesto y total del MoR, aprueba el pago y extiende la licencia |
| `refund` / `chargeback` | `adjustment.created/updated` con `action` refund/chargeback y `status` approved | `subscription_payment_refunded`, `order_refunded` | Revierte el pago y la vigencia; si el reembolso es parcial, alerta sin tocar la licencia |
| `payment_failed` | `transaction.payment_failed`, `subscription.past_due` | `subscription_payment_failed` | Avisa al equipo. El MoR reintenta; si no paga, la licencia entra en gracia y se corta sola |
| `subscription_linked` | `subscription.created/activated/updated` | `subscription_created/updated` | Vincula los ids externos a la licencia |
| `subscription_canceled` | `subscription.canceled` | `subscription_cancelled/expired` | Avisa. La licencia sigue hasta su vencimiento |

**Trampa de Lemon Squeezy:** por el primer pago de una suscripción envía `order_created` **y** `subscription_payment_success`. Si se cuentan los dos, se extiende dos veces. El adaptador ignora `order_created` salvo en compras únicas marcadas.

### Seguridad del vínculo con la licencia

- El checkout del MoR debe llevar **`solvex_license = LIC-00012`**: en Paddle como `customData`, en Lemon Squeezy como `checkout[custom][solvex_license]`.
- Un aviso **solo mueve una licencia configurada para ese proveedor** (Panel → licencia → Editar → *Quién cobra*). Si la licencia ya está vinculada a una suscripción, el aviso debe traer **la misma**. Así nadie puede "pagar" una licencia ajena desde otro checkout.
- Si el MoR cobró menos que el precio de la licencia (misma moneda), el equipo recibe una alerta.
- Los avisos fuera de orden se toleran: la idempotencia es por id de transacción, y un reembolso sin su pago responde 503.

## 6.8 Puesta en marcha

1. **Con tu contador:** confirma el régimen y, si venderás al extranjero, inscríbete en el **Registro de Exportadores de Servicios**. Luego ajusta **Configuración → Impuestos**.
2. **SUNAT:** debes ser **emisor electrónico**. Nubefact te guía con la afiliación como OSE/PSE.
3. **Nubefact:** crea la cuenta, activa la API y copia la ruta y el token de **DEMO** al `.env`:
   ```
   EINVOICE_PROVIDER=nubefact
   NUBEFACT_URL=https://api.nubefact.com/api/v1/…
   NUBEFACT_TOKEN=…
   ```
4. Reinicia el Hub.
5. En **Configuración → Comprobantes electrónicos**, revisa las series y activa la emisión. Pide confirmación con tu código 2FA.
6. Emite el set de prueba que pide Nubefact (sección 6.5) y revisa cada PDF.
7. Cambia a la ruta y token de **producción**.
8. En cada cliente, completa la **razón social y la dirección fiscal**: son obligatorias para facturar. Si faltan, el comprobante queda "con error" hasta que las completes.

## 6.9 Límites actuales (honestos)

- Los comprobantes del Hub se emiten **solo en soles**. Un pago en otra moneda que no sea de un MoR genera una alerta para emitirlo a mano: falta el tipo de cambio SBS.
- No se calculan detracciones, retenciones ni percepciones.
- Los reembolsos son **totales**. Un reembolso parcial de un MoR se marca para revisión manual.
- El débito automático con tarjeta guardada en Culqi todavía no está implementado. El modelo ya lo admite, con `billing_provider` e ids externos.

## Fuentes

- [SUNAT · Informe 179-2019: requisitos de la exportación de servicios (art. 33 Ley del IGV)](https://www.sunat.gob.pe/legislacion/oficios/2019/informe-oficios/i179-2019-7T0000.pdf)
- [Cámara de Comercio de Lima · Los cuatro regímenes tributarios](https://lacamara.pe/radiografia-de-los-cuatro-regimenes-tributarios-vigentes/?print=pdf)
- [Nubefact · ¿Cómo integro mi sistema?](https://eventos.nubefact.com/preguntas/nubefact-api/integracion/como-integro-mi-sistema-a-nubefact-y-tiene-algun-costo-adicional) y [manual de integración](https://ayuda.nubefact.com/preguntas/nubefact-api/integracion/donde-encuentro-el-manual-de-integracion)
- [Paddle · Verificación de firma de webhooks](https://developer.paddle.com/webhooks/signature-verification)
- [Paddle · Evento adjustment.updated (reembolsos y contracargos)](https://developer.paddle.com/webhooks/adjustments/adjustment-updated)
- [Lemon Squeezy · Tipos de eventos de webhook](https://docs.lemonsqueezy.com/help/webhooks/event-types) y [firma de solicitudes](https://docs.lemonsqueezy.com/help/webhooks/signing-requests)
- [Stripe · Países disponibles](https://stripe.com/es/global)
