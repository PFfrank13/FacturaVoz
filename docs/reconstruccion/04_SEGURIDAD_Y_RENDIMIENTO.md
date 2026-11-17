# Seguridad, consistencia y rendimiento (Prompt Maestro §13 y §15)

Todo lo de esta página se comprobó en un PostgreSQL 16 local y desechable, con las 47 migraciones aplicadas en orden
(`backend/supabase/tests/local/run_all.sh`). Nada se aplicó en producción.

## Hallazgos y correcciones

| # | Hallazgo | Impacto | Corrección | Evidencia |
|---|---|---|---|---|
| 1 | **`min(uuid)` no existe en PostgreSQL.** La salida de stock al emitir (`apply_stock_on_issue`, 20261128) lo usaba con `search_path = ''`. | Emitir cualquier comprobante con una línea **sin producto** (facturas dictadas o escritas) fallaba con "function min(uuid) does not exist". | `20261206_v33_fix_stock_min_uuid.sql`: misma lógica con `(array_agg(p.id order by p.id))[1]`. | `test_sunat.sql` fallaba en la línea 9 antes del arreglo y pasa después. Conviene confirmarlo en staging (la versión de PostgreSQL de Supabase puede variar). |
| 2 | **Migraciones con fecha fuera de orden.** Cinco archivos `20261108_*` se escribieron después de `20261130` pero su nombre los ponía antes de `20261111_licencias`, de la que dependen. | En un entorno nuevo (staging, rama de Supabase), `20261108_local_dev_license_bodega.sql` fallaba ("type public.org_licenses does not exist") y `pay_settings_column_grants` dependía de `pos_merchant_qr`, que se ordenaba después. | Renombrados a `20261201`–`20261205` en el orden real en que se escribieron (historial de git). Contenido sin cambios. | Las 47 migraciones aplican limpias en orden alfabético en una base vacía. **Si producción registró esas versiones con el CLI de Supabase**, hay que marcarlas como aplicadas (`supabase migration repair`) en vez de volver a correrlas. |
| 3 | **El administrador podía pagar o cambiar el plan.** `my_license()` le entregaba `pay_url` y `my_access().can.license` era `true` para él. | Contradice §4 (el administrador no gestiona la suscripción). La app solo ocultaba el botón. | `20261207_v33_suscripcion_solo_propietario.sql`: `pay_url` y `can.license` solo para el propietario. La **activación** con código sigue siendo de propietario o administrador (`api/license/activate`). | `test_v33_suscripcion.sql` (6 comprobaciones). |
| 4 | **Cobros, abonos de fiado y movimientos de caja sin idempotencia.** Ventas y compras ya usaban RPC con `request_id`; estas tres inserciones no. | Con mala señal, una respuesta perdida + reintento podía registrar el cobro dos veces. | App: el id de la fila se genera en el teléfono y el reintento usa el mismo id (`logic/idempotent.dart`, `Repo.insertOnce`); un choque de clave primaria en el reintento significa "ya se guardó". Sin cambios de esquema. | `test_v33_idempotencia.sql` (la base rechaza el duplicado en las 3 tablas) y `test/idempotent_test.dart` (5 casos). |
| 5 | **RLS lenta por fila.** Las 13 políticas `hub_feature_read_*` llamaban a `has_feature(org_id, …)` en cada fila. | Inicio y Caja lentos con negocios grandes. | `20261208_v33_rls_funciones_rendimiento.sql`: la lista de empresas del usuario con la función se calcula una vez por consulta. Misma regla. | Ver la medición de abajo; `test_v33_rls_funciones.sql` da el mismo resultado antes y después del cambio. |
| 6 | **Arqueo ciego roto por el Inicio nuevo** (error propio de la fase 2). | El Inicio mostraba el efectivo esperado antes del cierre. | El indicador muestra solo el estado (Sin abrir / Abierta / Cerrada). | Revisión de código (`role_home.dart`). |
| 7 | **Destino "Mesas" sin permiso de rol.** | Un técnico de restaurante veía la pestaña. | Exige permiso de venta (fase 1). | `navigation_contract_test`. |

## Garantías revisadas (§13)
| Garantía | Estado | Dónde |
|---|---|---|
| Aislamiento entre empresas | Ninguna fila de otra empresa es visible en **57 tablas** con `org_id`. | `test_v3_rls_audit.sql` |
| Permisos por miembro | Los decide la base (`my_access`, RLS, `set_member_role_impl` impide que un administrador ascienda a otro). La app los traduce a permisos granulares que niegan por defecto. | `test_roles.sql`, `permissions.dart` |
| Licencia desde el backend | `license_guard` bloquea escrituras sin licencia; el Hub manda (función ausente = denegada). | `test_hub_precedence.sql` |
| Idempotencia | Ventas (`fast_checkout_atomic`), compras y liquidaciones (RPC idempotentes); cobros, fiados y caja (id del teléfono). | ver #4 |
| Cambio de empresa | La app descarta respuestas de la empresa anterior (`Access._generation`, `CashDay._loadGeneration`; el Inicio por rol se reconstruye con su clave). | código |
| Sin credenciales privilegiadas en Flutter | Solo `SUPABASE_URL` y la clave pública `SUPABASE_ANON_KEY` por `--dart-define`; ninguna clave de servicio en `app/lib`. | `config.dart` |
| Restricción por sucursal | **No existe** en la base: no hay sucursales con datos separados (solo el límite `max_branches`). Pendiente real. | — |

## Rendimiento medido (§15)
PostgreSQL 16 local con 10 000 comprobantes, 10 000 cobros, 2 000 movimientos de fiado, 500 clientes y 1 000 productos
(`tests/bench_v33_inicio_rol.sql`), consultas como usuario autenticado con RLS, tres ejecuciones seguidas:

| Consulta del Inicio por rol | Antes (#5) | Después |
|---|---|---|
| `day_summary` (ventas de hoy y caja) | 414 / 468 / 457 ms | 14 / 7,5 / 7,4 ms |
| `credit_balances` (fiados por cobrar) | 305 / 306 / 287 ms | 5,1 / 4,7 / 4,6 ms |
| productos para "stock bajo" (1 000 filas) | 2,6 ms | igual |

Son tiempos de la base, sin red ni teléfono. **No se midió la app en Android** (aquí no hay SDK ni emulador). Del lado
de Flutter se revisó en código: sin `IntrinsicHeight` en la comparación de planes, indicadores con `Wrap` en vez de listas
anidadas, el Inicio por rol solo pide los datos de los bloques que ve ese rol, y las pruebas a 320 px con letra x1,3 no
deben dar desbordes (`small_screen_test.dart`).
