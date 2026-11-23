# FacturaVoz ERP Pro — hoja de ruta viva

Rama de trabajo: `erp-pro` (sale de `main`). Esta hoja la leen las sesiones
automáticas para saber qué sigue. Marca `[x]` al terminar y deja una línea con
lo verificado. No inventes datos ni simules ventas: todo lee y escribe la misma
base de Supabase que el móvil, con RLS del usuario.

## Por qué existe cada bloque (investigación del rubro, 22/11/2026)

- Mermas y vencimientos: ≈ S/ 700 M/año y 1,2–1,5 % de las ventas en el retail
  peruano (ISEG 2025, 19 empresas grandes); la mitad es vencimiento y daño, y
  del resto la mayor parte es robo interno. (La cifra antigua de «7 % en tiendas
  pequeñas» era de 2017 sin metodología: no usarla.) → Vencimientos, mermas, conteos.
- Fiado por cliente con límite, Yape/Plin y boleta por WhatsApp son estándar en
  la competencia (Xelera, ERP Perú). → Igualarlos y superarlos.
- SUNAT: boletas se anulan dentro del resumen diario (≤ 7 días); facturas con
  comunicación de baja (≤ 7 días); después, nota de crédito. → Estado y plazos
  visibles en Comprobantes.
- Operación diaria: arqueo de caja, compras a proveedores, reposición; el
  inventario valorizado es registro tributario. → Caja, Compras, Kardex.

**Investigación completa (23/11/2026):** `docs/INVESTIGACION_RETAIL.md` y notas con
fuentes en `docs/investigacion/`. Toda función nueva debe citar el hallazgo que la
justifica (fila de la tabla «Lista priorizada de funciones»).

## Planes (confirmados en Solvex Hub: S/ 39 / 79 / 179, 2 / 5 / 20 usuarios, 7 días de prueba)

- Básico: vender, cobrar, boletas/facturas, inventario, fiados, caja, reportes básicos.
- Pro («Más recomendado»): Básico + Copiloto IA + módulo estrella del rubro
  (bodega: puntos y cupones) + compras con proveedores y alertas de vencimiento.
- Empresa: Pro + sucursales (5), 20 usuarios, auditoría, roles avanzados,
  integraciones (API/webhooks), dueño a distancia.
Menús y rutas del servidor se filtran por empresa + rubro + plan + rol (ya existe
`moduleAllowed` en `backend/src/lib/erp/access.ts` y `planMatrix` en la app).

## Bloques

### 1. Actualización automática del móvil (OTA)
- [x] App: comprobar `releases/latest/download/android-update.json`, descargar
      el APK con progreso, verificar SHA-256 y abrir el instalador (FileProvider).
- [x] CI: workflow que, con los secretos de firma presentes, compila el APK
      firmado en cada push a `main`, sube la release y el manifiesto
      (`.github/workflows/android-release.yml`).
- [ ] El propietario crea los secretos `ANDROID_KEYSTORE_BASE64`,
      `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` y las
      variables `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL` en GitHub
      (Settings → Secrets and variables → Actions). Sin ellos el workflow se salta.

### 2. ERP web — Comprobantes
- [x] Lista con filtros (tipo, estado SUNAT) y búsqueda por número, cliente, DNI o RUC.
- [x] Detalle: ítems, totales, cliente, estado SUNAT, XML y CDR.
- [x] Representación impresa A4 / ticket 80 / 58 mm compartida con el portal del
      cliente (QR SUNAT nivel Q, valor resumen, aviso de beta o envío pendiente).
- [x] Plazos: «puedes anular hasta …» / «corrígela con nota de crédito».
- [x] Borradores por voz o escritos con el estilo del ERP y errores claros.
- [x] Filtro por rango de fechas y envío por WhatsApp/correo desde el detalle.

### 3. ERP web — Clientes con DNI/RUC
- [x] Alta y edición con consulta DNI/RUC (misma lógica que `/api/lookup`, en
      `lib/lookup.ts`: caché, cupos y avisos de RUC no activo / no habido).
- [x] Ficha: compras, total, frecuencia, deuda de fiado con límite y vencimiento,
      abonos y fiados en la misma libreta del móvil, recordatorio por WhatsApp.
- [x] Filtros: con fiado, vencidos o sobre límite, «no están volviendo».

### 4. ERP web — Operación
- [x] Caja: apertura, ingresos, retiros con motivo, cobros por medio de pago,
      arqueo ciego (el esperado solo lo ve finanzas) e historial por día. El cierre
      usa `lib/dayclose-core.ts`, la misma lógica de `/api/day-close` del móvil.
- [x] Fiados: saldos, abonos, límite por cliente (dentro de Clientes).
- [x] Compras y proveedores: registrar compra (stock, costo, kardex, gasto y
      salida de caja en una transacción `retail_receive`, idempotente), cuentas
      por pagar a proveedores y su pago (`retail_settle`).
- [x] Inventario: kardex por producto (compras y ventas con stock resultante).
- [x] Inventario: vencimientos por lote y mermas con motivo (v3.6, aprobada y aplicada el 23/11/2026). Antes: **Requiere decisión
      del propietario:** una migración nueva (tablas de lotes y mermas) que debe
      aplicarse en producción con el procedimiento de seguridad.

### 5. ERP web — Panel y diseño
- [x] Inicio con ventas del día y del mes, comparación con los mismos días del
      mes pasado, ticket promedio, ritmo de ventas por hora, productos estrella y
      «Para resolver hoy» (SUNAT, stock bajo, fiados vencidos, deuda a
      proveedores, caja), todo con datos reales y según plan y rol.
- [x] Diseño premium coherente con el móvil (skill frontend-design). Hecho (23/11: también reportes, plan, configuración, equipo y listas):
      inicio, acceso, comprobantes, clientes, caja, compras y cobros. Falta:
      cotizaciones, equipo, reportes, plan y configuración (aún con tabla genérica).

### 7. Según la investigación del rubro (orden de prioridad)
Fuente: `docs/INVESTIGACION_RETAIL.md`, «Las cinco siguientes» y tabla de 24 funciones.
- [x] Conciliación Yape/Plin (fila 1): en Android, leer solo las notificaciones de
      Yape, Plin y bancos (permiso opcional y declarado, procesado en el teléfono),
      avisar por voz, registrar el cobro y emparejarlo con la venta; cuadre por medio
      al cierre. iOS no lo permite: decirlo en la venta. Revisar Ley 29733 y la
      política de Google Play antes de publicar.
- [x] Venta suelta y por peso en Básico (fila 2): presentaciones unidad/paquete/
      caja/kilo con conversión de stock (costal → kilos).
- [x] Lotes, vencimientos y mermas con motivo (filas 3–4): **una sola migración,
      requiere aprobación del propietario.** El plan Pro ya promete alertas de
      vencimiento: es la deuda comercial más urgente.
- [x] Turnos por cajero con fondo, sangrías, entrega de turno, cierre ciego por
      cajero, PIN de supervisor y bitácora (filas 5 y 7), sobre la caja actual.
      Hecho en v3.8c (turno con fondo y cierre ciego, diferencia solo para finanzas, bitácora
      en audit); el PIN de supervisor para anular ya existía en el móvil.
- [x] Pedido sugerido multiproveedor (fila 6), en Compras web con la venta real; falta llevarlo al Copiloto del móvil.
- [x] Correcciones fiscales chicas: ICBPER (bolsa a S/ 0,50 fuera de la base del
      IGV, fila 13) y tope del NRUS por ventas **y compras** (fila 14, `taxes.dart`).
- [x] Después: multisucursal real con stock por local (fila 22). Hecho en v3.8d: cada local es
      una empresa con su stock; módulo «Sucursales» con panel consolidado y traslados atómicos. Hasta entonces el
      plan Empresa no debe venderse con «5 sucursales» como argumento central.

### 6. Móvil — pulido
- [x] Inicio de sesión con el nuevo diseño (campos con fondo, barra de estado legible sobre la foto, enlaces agrupados). El asistente de primera vez no se revisó en pantalla: requiere crear una cuenta nueva.
- [x] Transición carrito → cobro sin mezcla de pantallas (la hoja termina de cerrarse y el cobro entra con fundido opaco).

## Registro
- 22/11/2026: ERP con edición de productos y foto, verificado móvil ↔ ERP en
  vivo contra Supabase local; producción en `factura-voz-two.vercel.app`.
- 23/11/2026: Comprobantes web verificados contra Supabase local (lista, detalle,
  A4, ticket, XML, CDR, borrador). La impresión del ERP reutiliza la del portal
  público (`buildPrintDoc` + `ReceiptPrint`), leída con la sesión del usuario (RLS).
- 23/11/2026: OTA móvil (bloque 1, ítem App) revisada y verificada: la descarga
  reutiliza el APK ya verificado, cierra el archivo antes de borrarlo si se corta
  la conexión y acepta una carpeta de prueba. `flutter analyze` sin avisos,
  `flutter test` 514 OK (10 en `app_updater_test.dart`: hash correcto, APK
  manipulado, HTTP 404, aviso y «Más tarde»), `flutter build apk --debug` OK
  (Kotlin + FileProvider compilan). No probado en dispositivo. Bloque 1 ítem 3
  depende del propietario (secretos en GitHub).
- 23/11/2026: Clientes web con DNI/RUC, ficha, libreta de fiado y WhatsApp,
  verificado contra Supabase local (RUC en caché, alta, abono de S/ 12.40).
- 23/11/2026: Caja web verificada en local: apertura S/ 50, esperado S/ 62.40
  (incluye abono de fiado en efectivo), cierre ciego con faltante de S/ 2.40
  bloqueado sin motivo y guardado con motivo.
- 23/11/2026: Compras web verificadas en local: 12 × Arroz a S/ 3.80 «por
  pagar» (stock 20 → 32, costo actualizado) y pago en efectivo posterior.
- 23/11/2026: Kardex en la ficha del producto (solo dueño/administrador, como
  exige RLS), verificado con la compra local (+12 → 32).
- 23/11/2026: Inicio rediseñado (skill frontend-design): una frase con la venta
  del día y el ritmo por hora como elemento principal; verificado en escritorio
  y a 375 px con ventas locales de prueba.
- 23/11/2026: Acceso web con el mismo tema del ERP (aurora y cristal, claro y
  oscuro) y pasos «recibe el código» → «escríbelo».
- 23/11/2026 (sesión automática): Comprobantes con filtro por fechas (Todo / Hoy /
  7 días / Este mes / desde–hasta, leído por el servidor con `?desde=&hasta=`,
  hasta 366 días; aviso si se llega al tope de 300) y «Enviar al cliente» en el
  detalle: enlace privado `/comprobante/<token>` (el mismo `invoice_portal_link`
  del botón «Enlace» del móvil, con RLS del usuario), WhatsApp con el celular del
  cliente o eligiendo chat, correo con `mailto:` desde el correo del propio
  negocio (sin coste de Resend ni PDF adjunto) y «Copiar enlace». Verificado:
  `tsc` OK, eslint sin errores (2 avisos previos de `<img>`), `vitest` 214 OK
  (nuevas: `erp-receipt-share.test.ts` y rangos/mensajes en `erp-receipts.test.ts`).
  **No verificado en el navegador:** no se pudo arrancar la vista previa local en
  esta ejecución; conviene probar el envío con Supabase local.
- 23/11/2026 (sesión automática): Cobros rediseñado (bloque 5, ítem sigue abierto):
  mes a mes con `?mes=YYYY-MM` (nunca futuro), cobrado del mes, cobro promedio,
  % de pagos digitales, reparto por medio, barras día a día con el mejor día,
  búsqueda por comprobante/cliente/DNI/RUC/nota, filtro por medio y lista agrupada
  por día con subtotal. Lee `payments` + comprobante y cliente con RLS del usuario
  (límite 500 por mes, con aviso); cobros en otra moneda no se mezclan. En vivo
  con `LiveRefresh` (payments está en `supabase_realtime`). Lógica pura en
  `lib/erp/payments.ts`. Verificado: `tsc` OK, eslint sin errores (2 avisos
  previos de `<img>`), `vitest` 220 OK (nueva: `erp-payments.test.ts`, 6 casos).
  **No verificado en el navegador:** no se autorizó arrancar la vista previa local.
- 23/11/2026: Investigación del rubro en cinco frentes (bodegas, minimarkets y
  supermercados, SUNAT y mercado, competencia, proveedores y pagos) con fuentes;
  informe en `docs/INVESTIGACION_RETAIL.md`. Se añade el bloque 7 y se corrige la
  cifra de merma.
- 23/11/2026: Bloque 7 según la investigación. Migraciones v3.6 (lotes, vencimientos, mermas; compras por kilo) y
  v3.7 (unidad KGM) probadas en local y aplicadas en producción con el propietario. Web: vencimientos y mermas en
  Inventario, fecha de vencimiento en Compras, pedido sugerido por proveedor, aviso en Inicio, productos por kilo,
  módulos «Puntos de clientes» y «Precios y promociones», cuadre por cajero en Caja. Móvil: Vencimientos y mermas,
  merma con motivo en lugar de la salida sin motivo, vencimiento al recibir compras, venta por kilo o por monto,
  lector nativo de avisos Yape/Plin (probado en emulador: captura el Yape e ignora lo que no es pago) con «Yape
  recibido» en el cobro. NRUS: el tope cuenta compras. Pendiente: ICBPER (toca el XML de SUNAT, probar en beta),
  turnos con fondo y entrega por cajero con PIN, multisucursal con stock por local, cupones en el plan Pro de bodega
  (hoy los cupones van con «precios»).
- 23/11/2026: Pendientes cerrados. v3.8a (cupones también en el Pro de bodega), v3.8b (ICBPER dentro del precio
  de la bolsa, sin cambiar el total; probado en pruebas unitarias del XML, no enviado aún a SUNAT beta),
  v3.8c (turnos de caja por cajero) y v3.8d (sucursales y traslados), aplicadas en producción y verificadas.
  Avisos de seguridad de Supabase previos y ajenos a estos cambios: protección de contraseñas filtradas apagada y
  tres funciones SECURITY DEFINER en public (audit_verify, create_pos_kitchen_order, link_pos_kitchen_invoice).
