# FacturaVoz — Fase 6: Bodega/Tienda, stock no negativo y publicación controlada

Fecha de referencia: 2026-11-17. **No es una autorización de cobro real ni de despliegue móvil firmado.**

## Hallazgo

La migración anterior de salida de inventario permitía expresamente stock negativo. Una venta podía descontar más unidades de las disponibles; el control técnico de ±10 millones no era una regla de disponibilidad. Ese comportamiento no es apropiado como predeterminado en Bodega/Tienda con inventario controlado.

Inspección de Supabase productivo FacturaVoz antes del cambio (solo agregados):
- 1 empresa, rubro `bodega`.
- 11 productos, 2 con stock numérico controlado y 9 con `stock IS NULL`.
- 0 productos con inventario negativo; los 2 controlados contaban con 100 unidades.
- La función `private.apply_stock_on_issue()` restaba sin comprobar saldo mínimo.

## Nueva regla comercial y técnica

- En organizaciones `org_settings.business_type = 'bodega'`, **el saldo numérico de stock jamás puede quedar negativo** en un `INSERT` o `UPDATE` de `products`.
- `stock IS NULL` indica *sin seguimiento de inventario*, no equivale a cero. Permanece válido para servicios y artículos todavía no configurados. No asignar stock cero automáticamente a esos 9 registros.
- No cambia la política de los demás rubros (salón, consultorio, restaurante, etc.). El historial de ventas y stock no se reescribe.
- La guarda se instala en la **base de datos** como trigger, no solo en la interfaz. Protege venta rápida, facturación convencional, ajustes y escrituras directas.
- Antes de abrir la confirmación de pago (efectivo, Yape, Plin o tarjeta), el POS comprueba el stock más reciente por SKU en Supabase. Si no alcanza, impide continuar; evita pedir dinero para una venta que ya se sabe imposible.
- La salida de inventario bloquea la fila del producto `FOR UPDATE` antes de descontar. Si dos cajas compiten por las últimas unidades, la segunda operación que intenta dejar inventario negativo falla en la misma transacción. La comprobación previa NO reserva inventario: una carrera todavía puede requerir conciliación manual si hubo transferencia externa.
- La factura, el cobro, la solicitud idempotente y los eventos de stock se revierten si la venta rápida falla por existencias. No se debe crear un cargo nuevo por una desconexión de red.
- Si el error SQL es **explícito y transaccional** `22023` con el prefijo propio de insuficiencia, Flutter libera la solicitud local para corregir cantidades. Errores de red o ambiguos mantienen la clave idempotente.

## Implementación

- `backend/supabase/migrations/20261211_v35_bodega_stock_no_negative.sql`
- `backend/supabase/tests/test_v34_stock.sql`
- `backend/supabase/tests/upgrade/run_upgrade.sh`
- `app/lib/errors.dart` y `app/lib/screens/pos.dart`
- `app/test/bodega_stock_rejection_test.dart`

## Criterios automáticos antes de integrar

1. Migraciones y SQL fresh desde PostgreSQL 17.
2. Ruta upgrade equivalente a Supabase real, preservando licencias, ventas y stock previos.
3. Rechazo de venta insuficiente dejando factura en `draft`, sin eventos ni cargo.
4. Venta válida e idempotencia: un descuento único.
5. RPC `fast_checkout_atomic`: ningún pago, factura ni request persistente si hay stock insuficiente.
6. Ajuste directo negativo rechazado incluso fuera de Flutter.
7. `stock NULL` permitido, y rubros diferentes de Bodega sin cambios.
8. Backend + tests + auditoría, Flutter analyze/test, builds web/APK y Android emulador.

## Publicación en Supabase

- La migración se aplica **una sola vez** al proyecto productivo autenticado, después de CI verde y una inspección del esquema real.
- Es aditiva y no actualiza datos antiguos; no hay backfill ni restablecimiento de existencias.
- Verificar tras aplicar: trigger habilitado, función existente, versión de migración registrada, cero inventario negativo.
- Los 9 productos sin seguimiento exigen revisión de catálogo antes de prometer inventario completo. No alterar su saldo sin decisión del negocio.

## Publicación de aplicaciones

El código integrado en `main` **no garantiza** que Vercel esté actualizado ni que la APK release esté firmada.

La conexión Vercel disponible en esta sesión está asociada al equipo `portafolio-frank`, que devolvió **0 proyectos** y no contiene el despliegue FacturaVoz solicitado. No crear un proyecto paralelo, ni sustituir URLs o variables existentes.

El despliegue web se ejecutará únicamente cuando la cuenta y el proyecto Vercel correctos estén accesibles. La APK/AAB comercial depende del keystore privado aprobado, sin el cual no es legítimo afirmar que está en producción móvil. La aceptación SUNAT/impresoras/bancos sigue requiriendo cuentas/hardware reales.
