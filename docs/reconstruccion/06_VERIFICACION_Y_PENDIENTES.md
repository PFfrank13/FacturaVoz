# Verificación, pendientes y bloqueos (Prompt Maestro §17–§19)

## Lo que SÍ se ejecutó
| Verificación | Resultado |
|---|---|
| 47 migraciones en una base PostgreSQL 16 vacía, en orden | OK (antes del #2 de `04_SEGURIDAD_Y_RENDIMIENTO.md`, fallaba) |
| Migraciones nuevas aplicadas dos veces | OK (idempotentes) |
| Pruebas SQL (`tests/local/run_all.sh`): fase0, sunat, crm, roles, mod1, mod2, v3_rubros, v3_voz, v3_rls_audit, v33_idempotencia, v33_suscripcion, v33_rls_funciones, hub_precedence | **13 de 13 pasan** |
| Mediciones de consultas del Inicio por rol | ver `04_SEGURIDAD_Y_RENDIMIENTO.md` |
| Revisión estática de los archivos Dart cambiados (llaves balanceadas, importaciones usadas) | OK, con un script propio, **no** con el analizador de Dart |
| Contrastes de color WCAG | calculados (ver `02_DESIGN_SYSTEM.md`) |

`test_lic.sql` y `test_v31_planes.sql` **no** se ejecutan: se escribieron antes de que la base exigiera activación
(20261124) y de que el Hub mandara sobre la matriz de planes (20261125), así que sus expectativas ya no aplican; la
cobertura vigente es `test_hub_precedence.sql`. Las pruebas antiguas necesitan una licencia de prueba
(`tests/local/01_licencia_hub_sintetica.sql`) porque hoy la base bloquea escrituras sin licencia.

## Lo que NO se pudo ejecutar aquí (y por qué)
| Verificación | Motivo | Cómo correrla |
|---|---|---|
| `flutter analyze`, `flutter test` (incluye las pruebas nuevas: `navigation_contract_test`, `role_matrix_test`, `small_screen_test`, `idempotent_test`, `plan_prices_test`) | El SDK de Flutter no se puede descargar en este entorno | CI de GitHub (`.github/workflows`) en cuanto la rama se suba, o local en `app/` |
| Compilación Android y prueba en emulador o teléfono | Sin SDK ni emulador | `flutter build apk` + `docs/GUIA_PRUEBAS_RUBROS.md` |
| Pruebas del backend (`npm test`, vitest) | El registro de npm no resuelve desde aquí | CI o `cd backend && npm ci && npm test` |
| Pull request | GitHub rechaza la subida (la app de Claude no tiene acceso al repositorio) | Instalar la app de Claude en GitHub o reconectar GitHub; o aplicar los parches y abrir el PR a mano con `PR_BODY.md` |

## Criterio de terminación (§18) por entrega
| Entrega | Ubicación | Acción visible | Datos reales | Backend | Permisos | Licencia | Errores | Pruebas | Estado |
|---|---|---|---|---|---|---|---|---|---|
| Inicio por rol | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ reintento | motor ✓ / widget ✗ | Falta correr en Flutter |
| Caja | ✓ | ✓ barra fija | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ prueba de widget | Falta correr en Flutter |
| Planes + activación | ✓ | ✓ | ✓ JSON del Hub | pago solo propietario ✓ | ✓ | ✓ | — | ✓ 320 px | Falta correr en Flutter |
| Equipo: permisos efectivos | ✓ | — | ✓ | base ✓ | ✓ | ✓ | — | ✓ vista previa | Falta correr en Flutter |
| Cobros/fiados/caja una sola vez | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ SQL + Dart | Listo (SQL ejecutado) |
| Stock al emitir sin producto | — | — | ✓ | ✓ | ✓ | ✓ | — | ✓ SQL | Listo (SQL ejecutado) |
| RLS rápida | — | — | ✓ | ✓ | ✓ | ✓ | — | ✓ SQL | Listo (SQL ejecutado) |

## Pendientes reales (ordenados)
1. **Correr Flutter**: analyze, test y compilación Android; corregir lo que salga.
2. **Prueba gratis de 7 días**: hecho el 22/11/2026, tras confirmarlo en Solvex Hub (`trial_days: 7` en el JSON y en `planTrialDays`; una prueba obliga a que coincidan).
3. **Roles por rubro en la base** (cocinero, almacenero, docente, jefe de obra…; marcados ⚠ en `01_MATRIZ_RUBRO_PLAN_ROL.md`): columna `rubro_role` y permisos finos (`cash.open` separado de `collect`, compras sin administración). Requiere tu decisión.
4. **Sucursales**: no hay datos por sucursal; Empresa solo tiene el límite.
5. Retirar la barra heredada v2 y `home.dart`; unificar Clientes, Ajustes y Tienda; migrar los 257 colores fijos a `DsColors`.
6. GRE desde la app (mayorista), resumen diario de baja (vence la regla nueva el 1‑1‑2027) y Libro de Reclamaciones virtual.
7. Docente con acceso solo a sus grupos (datos de menores).
8. Fases 5–7 del prompt (Pro, Empresa y los otros 8 rubros) usan el mismo motor: ya tienen Inicio, barra, roles y acción principal; falta la profundidad de cada módulo.

## Bloqueos
- **GitHub**: sin acceso de escritura → sin rama remota, sin CI, sin PR.
- **Entorno**: sin Flutter, sin npm, sin emulador.
- **Producción**: no se tocó. Las 3 migraciones nuevas (`20261206`–`20261208`) y el renombre deben probarse en staging.
