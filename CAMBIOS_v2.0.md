# FacturaVoz v2.0 — Informe de cambios

Todo en español simple. Primero lo que cambió para el usuario, luego cómo instalarlo, qué configurar y qué falta
probar. Ninguna función existente se borró: se reordenó, se movió o se ocultó (modo simple, plan, rol).

---

## 1. Qué cambió (en simple)

**La app se ordena según tu negocio.** Al empezar eliges tu tipo de negocio (bodega, restaurante, servicio técnico,
salón, consultorio, taller, mayorista, educación, construcción u otro) y si quieres la app **simple** (4 botones) o
**completa**. Abajo hay como máximo 5 botones y el micrófono al centro; el resto está en **Todas las funciones** y en
el **buscador** (también por voz).

**Clientes de verdad (Ficha 360).** Cada cliente tiene su ficha con mapa, cuánto te debe (facturas + fiados),
puntaje de pago, historial, cotizaciones, trabajos, equipos instalados, notas y fotos. Botones grandes: Facturar,
Cotizar, Cobrar, Agendar y WhatsApp. Se guarda solo mientras escribes. Al escribir un DNI o RUC se completan los
datos (si configuras el proveedor).

**Trabajos y agenda.** Tablero por pasos (arrastrar y soltar), técnico asignado, fotos de antes y después,
materiales que descuentan el inventario, hitos de obra que se facturan con un toque y aviso "voy en camino" por
WhatsApp. Los pasos se cambian a gusto (ej. internet WiFi: Interesado → Visita → Cotizado → Pendiente → En camino →
Instalado → Cobrado).

**Tu equipo con permisos reales.** Invitas por correo y eliges el rol: cajero, vendedor, técnico o finanzas. El
empleado entra con **"Iniciar con Empresa"** y ve una bienvenida con su nombre, empresa y lo que puede hacer. Un
técnico solo ve SUS trabajos: lo impide la base de datos, no solo la pantalla.

**Vender rápido.** Venta rápida con código de barras (cámara o lector), precios por mayor, promociones y cupones;
"del cuaderno a la factura" (foto → venta); carta QR por mesa con comandas en vivo; tienda en línea con categorías,
fotos, carrito, página por producto, recojo/delivery y pedido mínimo; reservas en línea.

**Cobrar y controlar.** Libreta de fiados, caja con cierre del día y reporte por correo, avisos de Yape/Plin
(pegar la notificación), conciliación bancaria con el Excel del banco, "¿Cuánto me queda?" con impuestos estimados
por régimen, ventas por vendedor y comisiones, portal del cliente, encuestas, puntos y cumpleaños, ventas en dólares
con tipo de cambio, API y webhooks.

**Dueño a distancia.** Alertas al instante (anulaciones, descuentos grandes, caja que no cuadra, cobros borrados,
PIN fallido), bitácora que no se puede alterar sin que se note, PIN del dueño para anular, papelera de 30 días con
botón **Deshacer**.

**Copiloto 2.0.** Te propone tarjetas cada día (visitas, fiados vencidos, cumpleaños, cuánto guardar para SUNAT),
te da un **resumen hablado de 30 segundos** y entiende órdenes: "registra un gasto de 50 en gasolina", "anula la
última boleta de Juan" (abre el comprobante para confirmar con PIN), "muéstrame las ventas de ayer", "anota que Rosa
me debe 30". Siempre pide confirmación antes de guardar.

**Impresión.** Tickets de 58/80 mm por Bluetooth (Android primero) o red (IP), con el **logo del negocio** en blanco
y negro, QR SUNAT y "valor resumen". Si no hay impresora: ticket en PDF de rollo (funciona en todo). El PDF A4 ahora
lleva logo, forma de pago real (contado o crédito con cuotas) y tres diseños (clásico, moderno, minimal).

**Licencias con Solvex Hub.** Planes Básico / Pro / Empresa con prueba de 3 días (una por RUC). Lo que el plan no
incluye se oculta y la base de datos lo bloquea. Sin configurar el Hub, la app funciona en **modo desarrollo**.

**Animaciones.** Un solo sistema de movimiento (duraciones y curvas iguales en toda la app), gestos para deslizar,
onda de voz, sacudida en errores y cambios de estado animados. Interruptor **"Animaciones reducidas"** (y se reducen
solas en teléfonos lentos o si el sistema lo pide).

### Errores corregidos que reportaste
| Problema | Causa | Arreglo |
|---|---|---|
| Importar .xlsx/.csv daba **42501** | En proyectos nuevos de Supabase las tablas no tienen permisos por defecto (faltaba `GRANT` en `import_jobs` y otras) | Migración 20261104 da los permisos exactos; además ahora se leen **.xlsx reales** (no solo CSV) |
| Inicio "Facturado S/ 232,802.20" vs Negocio "Ventas S/ 0.00" | Inicio sumaba **borradores** (y con IGV); Negocio solo emitidas y sin IGV | Una sola regla en el servidor (`sales_summary`): solo emitidas/cobradas, sin rechazadas ni anuladas. Inicio muestra con IGV y avisa los borradores aparte; Negocio, sin IGV (lo dice en pantalla) |
| "Escanear" y "Preguntar" se partían en dos líneas | Botones con texto largo en 1/3 de pantalla | Botones compactos de una línea que se achica |
| El micrófono tapaba "Plan de rescate con IA" | El aviso estaba al final de la tarjeta | El aviso va arriba y la lista tiene espacio para el dock |
| "Caja negativa" sin ventas | La proyección no distinguía "sin datos" | Estado vacío: "cuando registres tus primeras ventas…" |
| Número F-2026-0023 vs F001-00000023 | El primero es el **número interno**; el segundo, el de **SUNAT** | El comprobante muestra grande el número SUNAT y aclara cuál es el interno |
| Rechazo de SUNAT reutilizaba el mismo número | La reserva devolvía el número rechazado | Un número rechazado se archiva y se usa uno nuevo (20261105) |

---

## 2. Auditoría SUNAT (Paso 0)

- **Cómo se emite:** la app guarda la venta → el servidor (Vercel) arma el comprobante UBL 2.1 y lo envía con
  **Lycet/Greenter** directamente al servicio de SUNAT del contribuyente (SEE-Del contribuyente, con su certificado y
  usuario SOL). No pasa por un OSE/PSE. Boletas y facturas se envían una por una (`invoice/send`).
- **CDR:** la constancia de recepción de SUNAT se guarda con el comprobante (`fiscal_documents.cdr`); el XML y el
  CDR se pueden descargar desde el portal del cliente.
- **Estados:** venta `draft / sent / paid`; comprobante `pending / accepted / rejected / error`. Solo `accepted`
  es válido. Los códigos 2000–3999 son rechazo (no válido; se archiva el número), los 0100–1999 y errores de red
  quedan en `error` para reintentar.
- **Numeración:** serie de 4 caracteres (`F001` facturas, `B001` boletas) y correlativo de 8 dígitos
  (`F001-00000023`). El número `F-2026-0023` es interno y nunca va a SUNAT.
- **Representación impresa (PDF A4 y ticket):** emisor (razón social, RUC, dirección), título del comprobante,
  serie-número, fecha, cliente con RUC/DNI, detalle, op. gravada/exonerada/inafecta, IGV, total, **importe en letras**,
  forma de pago (contado o crédito con cuotas), **valor resumen**, leyenda de representación impresa y **código QR**.
- **QR:** según el Anexo N.° 6 (Aspectos técnicos, num. 6.4) de la RS 097-2012/SUNAT modificada por la
  RS 113-2018/SUNAT: 10 campos separados por "|" — RUC | tipo | serie | número | IGV | total | fecha | tipo doc.
  adquirente | número doc. adquirente | **valor resumen** — con **corrección de errores nivel Q**. Corregido en la app
  (PDF y ticket) y en la página pública (antes el último campo iba vacío).
- **Pendiente** (en la hoja de ruta): resumen diario de boletas y comunicación de baja.

---

## 3. Qué reemplazar e instalar (en orden)

1. **Copia la carpeta completa** sobre tu proyecto (no borres nada tuyo: solo se agregan y reemplazan archivos).
2. **Supabase → SQL Editor**, ejecuta en este orden (cada una es idempotente: se puede volver a correr; ninguna usa DROP):
   1. `backend/supabase/migrations/20261104_fase0_permisos_app.sql` — permisos (arregla 42501) y `sales_summary`
   2. `20261105_sunat_marca.sql` — números rechazados, logo/diseño del PDF, Storage privado `org-media`
   3. `20261106_crm.sql` — ficha 360, trabajos, agenda, fotos, plantillas
   4. `20261107_equipo_roles.sql` — roles, invitaciones, permisos por rol en la base de datos
   5. `20261108_tienda_productos.sql` — código de barras, fotos, categorías, tienda/carta
   6. `20261109_modulos_dinero.sql` — fiados, caja, bitácora, alertas, PIN, papelera, promos, cupones, puntos, banco, avisos, comisiones, dólares
   7. `20261110_modulos_conexion.sql` — portal, reservas, API, webhooks, encuestas, avisos del día
   8. `20261111_licencias.sql` — licencias Solvex Hub (empieza en modo desarrollo: no bloquea nada)
   9. `20261112_servicios.sql` — caché DNI/RUC, eventos del Hub, reporte diario, régimen tributario, limpieza
3. **git push** → Vercel redepliega el backend (5 crons diarios en `vercel.json`; el plan Hobby permite hasta 100 diarios).
4. **App:** `cd app` → `flutter pub get` → `dart run tool/post_create.dart` (agrega permisos de cámara, ubicación y
   Bluetooth a Android/iOS) → `flutter analyze` → `flutter test` → tu comando de siempre:
   `flutter run --no-enable-impeller --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=… --dart-define=API_BASE_URL=…`
   (versión 2.0.0+4; `--dart-define=GOOGLE_LOGIN=true` solo si activas Google en Supabase).

## 4. Variables de entorno nuevas (Vercel)
Todas opcionales: si faltan, la función se apaga con un mensaje claro (nada se rompe). Ver `backend/.env.example`.
| Variable | Para qué |
|---|---|
| `SOLVEX_HUB_URL`, `SOLVEX_INSTANCE_ID`, `SOLVEX_API_KEY`*, `SOLVEX_WEBHOOK_SECRET`*, `SOLVEX_PUBLIC_KEYS`, `SOLVEX_PLANS_URL` | Licencias (sin ellas: modo desarrollo). Guía: `docs/SOLVEX_HUB.md` |
| `DOC_API_DNI_URL`, `DOC_API_RUC_URL` (con `{n}`), `DOC_API_TOKEN`* | Consulta DNI (RENIEC) / RUC (SUNAT) con caché de 180/15 días y límite de 60 por hora por usuario |
| `FX_API_URL` (con `{date}`/`{currency}`), `FX_API_TOKEN`* | Tipo de cambio para ventas en dólares (si falta, se escribe a mano) |
\* marcar como *Sensitive*. Ya existentes y necesarias: `SUPABASE_SERVICE_ROLE_KEY`, `GROQ_API_KEY`, `CRON_SECRET`,
`RESEND_API_KEY` (correo del cierre de caja y reporte diario). **Recuerda rotar el `CRON_SECRET`** que compartiste antes en el chat.

## 5. Qué configurar
1. Migraciones (punto 3). 2. Variables de Vercel que quieras usar (punto 4). 3. Solvex Hub: producto, planes de
`docs/facturavoz-planes.json`, instancia y webhook (`docs/SOLVEX_HUB.md`). 4. Proveedor DNI/RUC (opcional).
5. En la app: logo y diseño (Ajustes → Logo y comprobantes), impresora (Ajustes → Impresora), tipo de negocio,
PIN del dueño y reporte diario. 6. Webhooks más frecuentes (opcional): `pg_cron` + `pg_net` (ver 20261112).

## 6. Qué NO se pudo verificar (sé honesto con esto antes de publicar)
- **La app Flutter no se compiló aquí** (este entorno no tiene el SDK de Dart/Flutter ni acceso para descargarlo).
  Se revisó a mano y con un verificador de sintaxis propio; las APIs de paquetes nuevos se usaron en su forma
  estable más común. **Corre `flutter analyze` y `flutter test` primero**: si algo no compila, suele ser una línea
  (versión de un paquete) y se corrige rápido.
- Paquetes nuevos sin probar en dispositivo: `mobile_scanner`, `print_bluetooth_thermal` (ticketeras reales),
  `flutter_map`/OpenStreetMap, `geolocator`, `quick_actions`, `permission_handler`.
- Envío real a SUNAT (beta/producción), impresoras térmicas reales, audio del dictado y lectura de fotos con IA en
  un teléfono, correos de Resend, el proveedor DNI/RUC y de tipo de cambio (no elegido aún), Solvex Hub en un
  servidor real (sí se probó de punta a punta en local: prueba, idempotencia, RUC repetido, sincronización y webhook firmado).
- En iPhone: impresión Bluetooth solo con impresoras BLE compatibles; no se probó.

**Sí se verificó:** las 9 migraciones en PostgreSQL 16 con y sin privilegios por defecto (como Supabase nuevo) y su
re-ejecución; 7 guiones de prueba de seguridad y reglas (`backend/supabase/tests`); tipado del backend; 73 pruebas
del backend (5 archivos); 55 pruebas del Hub (incluye 7 nuevas de la prueba gratis); el QR leído por un lector real (OpenCV).

## 7. Seguridad (resumen)
- RLS en **todas** las tablas nuevas; permisos por rol en la base de datos (políticas restrictivas), no en la pantalla.
- Funciones `SECURITY DEFINER` solo en el esquema `private` con `search_path = ''`; las públicas son envoltorios.
- Ninguna clave en la app: DNI/RUC, Groq, Hub, Resend y tipo de cambio solo en Vercel. La app usa la clave pública de Supabase.
- Fotos y logo en Storage **privado** por empresa (enlaces firmados temporales); el logo solo lo cambian administradores.
- Licencias: token Ed25519 verificado en el servidor (emisor, audiencia, fechas), webhook HMAC con anti-repetición,
  tokens viejos ignorados, guardia en la base de datos (aunque alguien salte la app).
- API pública: claves con hash SHA-256 (se muestran una vez), permisos por alcance, 120 llamadas/min, 402 si el plan venció.
- Antifraude: bitácora encadenada con hash, alertas, PIN con bloqueo tras 5 intentos.

## 8. Reglas de oro cumplidas y decisiones tomadas (la opción más segura)
- No se borró ninguna función; Cotizaciones pasó de pestaña a "Vender" y sigue igual. Google/Apple quedan ocultos (no borrados) hasta `GOOGLE_LOGIN=true`.
- No se tocó el escáner de comprobantes (`screens/scan.dart` ni su backend): los avisos de fecha antigua, RUC del
  comprador distinto y textos a mano se muestran en la hoja de confirmación del gasto, leyendo la última lectura.
- Un solo producto: no hay panel web aparte (las páginas públicas son para el cliente final).
- Producto en la tienda: exige **foto**, y **código de barras** si es producto (no servicio). Se puede apagar "mostrar en tienda".
- Tasa de IGV: no se agregaron tasas especiales no verificadas (solo 18 % y 0 % como atajos; se puede escribir otra).
- Impuestos: siempre "estimado, confírmalo con tu contador".
- Restaurante/carta y reservas usan los mismos pedidos y agenda (sin tablas paralelas).
- Lo que necesita código nativo (lector automático de notificaciones, widgets de pantalla, USB) quedó en `docs/HOJA_DE_RUTA.md`, con alternativa funcionando hoy.

## 9. Documentos nuevos
`docs/MAPA_DE_FUNCIONES.md` · `docs/HOJA_DE_RUTA.md` · `docs/GUIA_PRUEBAS_15MIN.md` · `docs/SOLVEX_HUB.md` ·
`docs/facturavoz-planes.json` · `backend/supabase/tests/LEEME.md` · Hub: `docs/03-integracion-productos.md`
(endpoint de prueba gratis) e `integraciones/node/solvex-license.js` (`requestTrial`).

## 10. Archivos
**Nuevos (app):** `lib/{access,business_templates,models_v2,xlsx_reader}.dart`, `lib/logic/*` (DNI/RUC, impuestos,
precios, avisos, banco, escáner, ESC/POS, buscador, puntaje), `lib/services/{v2_api,v2_repo,location,quick_launch}.dart`,
`lib/services/print/*`, `lib/ui/{barcode_scanner,mini_map}.dart`, pantallas `catalog, sell_hub, clients_hub,
client_profile, jobs, team, fiados, cash_day, taxes, owner_control, trash, promos, bank_recon, notices, api_access,
surveys, kitchen, notebook, pos, branding, store_v2, settings_v2, license_gate, welcome_employee, business_setup,
employee_login`, pruebas `test/{logic_v2,motion_v2,xlsx_reader}_test.dart`.
**Modificados (app):** main, app_state, import_logic, models_pro, shell, home, profit, collections, invoice_detail,
new_invoice, assistant, settings, products, expenses, orgs, store, profile_form, login, import_screen,
services/pdf_builder, ui/motion, pubspec.yaml, tool/post_create.dart.
**Backend:** migraciones 20261104–20261112 y pruebas SQL; rutas `api/{lookup,fx,notebook,transcribe,day-close,
license/trial,solvex/webhook,cron/solvex-sync,cron/webhooks,cron/daily,v1/*,public/{doc,survey,book,order}}`;
páginas `portal, comprobante, encuesta, reservar, tienda/[slug]/p/[id]`; `lib/{solvex,doclookup,fx,taxes,notebook,
dayclose,apikey,webhooks,qr,publicdocs}.ts`; modificados `lib/{assistant,publicdata}.ts`, `api/assistant`,
`api/fiscal/note` (PIN), `middleware.ts`, `vercel.json`, `.env.example`, `tests/v2.test.ts`, `scripts/e2e-solvex-hub.cjs`.
