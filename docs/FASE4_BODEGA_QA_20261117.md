# FacturaVoz — Fase 4 · Validación operativa de Bodega/Tienda

Fecha base: 2026-11-17. Rama: `fix/bodega-fase4-operaciones-seguras-20261117`.
Alcance: **Bodega/Tienda**, planes Básico/Pro/Empresa, roles reales y flujos existentes.
No modificar lógica de licencias del Hub, RLS, tablas de producción ni otros rubros.

## Criterio de salida de ingeniería

- CI backend: `npm ci`, `npm ls --omit=dev --all`, TypeScript, ESLint, auditoría estricta de producción, pruebas y build Next.js.
- CI PostgreSQL: migraciones desde cero y upgrade de producción, pruebas SQL.
- CI Flutter: análisis, tests, compilación web y APK debug (NO es versión firmada).
- CI Android: prueba de interfaz en emulador API 35, sin datos ni credenciales reales.
- No fusionar si un control obligatorio falla. No declarar aprobados servicios externos usando mocks.

## Matriz de aceptación y evidencia

| Área | Contrato que debe mantenerse | Evidencia automatizada actual | Límite |
| --- | --- | --- | --- |
| Navegación/planes | Un Drawer único; BASIC sin Copiloto/candados; Pro/Empresa sin duplicados; permisos por rol | `bodega_plan_matrix_fase3_test.dart`, `navigation_contract_test.dart`, `bodega_emulator_smoke_test.dart` | Validación UX con usuarios reales pendiente |
| POS y carrito | Carrito editable, cantidades, cobro visible, subtotal/IGV, sin cobro de carrito vacío | `retail_pos_cart_test.dart`, `retail_checkout_visual_test.dart`, `retail_pos_cart_test.dart` | Lectores de código físicos pendientes |
| Cobro | Efectivo insuficiente bloqueado; vuelto en céntimos; Yape/Plin/tarjeta confirmación manual sin afirmar validación bancaria | `pos_payment_test.dart`, widget tests y smoke Android | Validación bancaria real pendiente |
| Cobro resiliente | Solicitud persistida antes de RPC; mismo request ID ante corte/red; **no escribir bajo otra empresa/usuario** aunque cambie la sesión en un `await` | `pending_checkout_test.dart`, `operation_scope_fase4_test.dart`; guardias en `pos.dart` | Prueba de desconexión real y conciliación en staging pendiente |
| Comprobantes | Diferenciar venta interna de boleta/factura aceptada por SUNAT; rutas Emitir/Historial/SUNAT/Compartir | `retail_receipts_test.dart`, `retail_receipts_visual_test.dart` | Emisión SUNAT real, CDR y envío correo pendientes |
| Compras/inventario | Compra y pago a proveedor con idempotencia, SKU/stock trazado y sin segundo ingreso por liquidación | `retail_purchase_test.dart`, tests SQL existentes | Inventario concurrente con dos terminales reales pendiente |
| Caja | Apertura, movimientos, arqueo ciego, cierre; no usar sesión/empresa/día alterados durante un diálogo; importes exactos hasta 2 decimales | `operation_scope_fase4_test.dart`, `pos_payment_test.dart` y reglas en `cash_day.dart` | Cierre con ticketera y reconciliación contable real pendientes |
| Visual y accesibilidad | 320/390 px, texto 1.4×, temas claro/oscuro, botones alcanzables | `retail_checkout_visual_test.dart`, `retail_receipts_visual_test.dart`, Android emulator | Lector de pantalla y tablets físicos pendientes |
| Dependencias | Árbol npm de runtime completo; cualquier HIGH/CRITICAL de producción bloquea; avisos nuevos bloquean | `.github/workflows/ci.yml`, `audit-gate.test.mjs`, `npm ls --omit=dev --all` | `picomatch` GHSA-fc5q-39xc-vjpf sigue sin patch upstream, dev-only y bajo revisión con caducidad 2026-12-31 |

## Ejecución manual obligatoria en staging (sin operar sobre clientes)

1. Crear dos empresas **A/B**, un dueño y cajero por empresa, con perfiles separados. Confirmar que productos, tickets, caja y ventas de A no aparecen en B.
2. Con dos móviles: abrir carrito de A, iniciar cobro, simular pérdida de red, cambiar de empresa, volver a A y recuperar el **mismo request ID**. Comprobar una sola factura, un pago y una deducción de stock.
3. Repetir venta simultánea de última unidad de un SKU desde dos terminales: verificar exactamente un descuento por factura y pagos asociados, sin duplicados. **Advertencia:** el contrato SQL actual permite stock negativo si hay venta sin existencias (`test_v34_stock.sql` lo comprueba explícitamente); bloquear sobreventa exige una decisión funcional y migración posterior, no es una garantía actual.
4. Abrir caja y registrar ingreso/egreso en PEN. Verificar importes con coma/punto, error con tres decimales, y rechazo si cambia de empresa mientras se confirma.
5. Hacer arqueo ciego, cerrar día y verificar saldo, diferencias, notificación al dueño y que no puede cerrarse la caja de otra empresa o fecha tras cambiar de contexto.
6. Emitir boleta/factura válida en entorno SUNAT correspondiente, confirmar CDR y estado fiscal, imprimir ticket en periférico físico y compartir comprobante.
7. Auditar accesibilidad con TalkBack, rotación, escala tipográfica y pantallas compactas; probar rendimiento con cargas representativas y registrar p50/p95/p99 y tasa de errores.

**Regla de cierre:** los puntos 1–7 son escenarios reales de aceptación, no resultados afirmados. Aprobación automática ≠ despliegue ni certificación de SUNAT/hardware. La Fase 5 comprende la instalación firmada y la validación física.
