# FacturaVoz ERP Pro — hoja de ruta viva

Rama de trabajo: `erp-pro` (sale de `main`). Esta hoja la leen las sesiones
automáticas para saber qué sigue. Marca `[x]` al terminar y deja una línea con
lo verificado. No inventes datos ni simules ventas: todo lee y escribe la misma
base de Supabase que el móvil, con RLS del usuario.

## Por qué existe cada bloque (investigación del rubro, 22/11/2026)

- Mermas y vencimientos son la mayor pérdida del retail peruano (≈ S/ 700 M/año;
  ≈ 7 % de ventas en tiendas pequeñas). → Vencimientos, mermas, conteos.
- Fiado por cliente con límite, Yape/Plin y boleta por WhatsApp son estándar en
  la competencia (Xelera, ERP Perú). → Igualarlos y superarlos.
- SUNAT: boletas se anulan dentro del resumen diario (≤ 7 días); facturas con
  comunicación de baja (≤ 7 días); después, nota de crédito. → Estado y plazos
  visibles en Comprobantes.
- Operación diaria: arqueo de caja, compras a proveedores, reposición; el
  inventario valorizado es registro tributario. → Caja, Compras, Kardex.

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
- [ ] Filtro por rango de fechas y envío por WhatsApp/correo desde el detalle.

### 3. ERP web — Clientes con DNI/RUC
- [ ] Alta con consulta DNI/RUC (`/api/lookup`, la misma del móvil).
- [ ] Ficha: compras, deuda de fiado, límite.

### 4. ERP web — Operación
- [ ] Caja: apertura, movimientos, arqueo ciego, historial.
- [ ] Fiados: saldos, abonos, límite por cliente.
- [ ] Compras y proveedores: registrar compra, actualizar stock y costo.
- [ ] Inventario: vencimientos, mermas, kardex.

### 5. ERP web — Panel y diseño
- [ ] Inicio con ventas del día/mes, ticket promedio, top productos, stock bajo,
      fiados por cobrar (datos reales).
- [ ] Diseño premium coherente con el móvil (skill frontend-design).

### 6. Móvil — pulido
- [ ] Inicio de sesión y asistente de primera vez con el nuevo diseño.
- [ ] Transición carrito → cobro sin mezcla de pantallas.

## Registro
- 22/11/2026: ERP con edición de productos y foto, verificado móvil ↔ ERP en
  vivo contra Supabase local; producción en `factura-voz-two.vercel.app`.
- 23/11/2026: Comprobantes web verificados contra Supabase local (lista, detalle,
  A4, ticket, XML, CDR, borrador). La impresión del ERP reutiliza la del portal
  público (`buildPrintDoc` + `ReceiptPrint`), leída con la sesión del usuario (RLS).
