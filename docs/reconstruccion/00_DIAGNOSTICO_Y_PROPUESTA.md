# Reconstrucción FacturaVoz — Diagnóstico de la arquitectura real y propuesta

Rama: `feat/reconstruccion-ux-roles-20261116` (sale del PR #9, `3cdc46e`). No toca `main` ni producción.
Base revisada: `main` + PR #9 (borrador, "No fusionar a main"; CI de backend y app en verde).

## 1. Qué hay hoy (medido en el código, no supuesto)

| Indicador | Valor |
|---|---|
| Archivos Dart en `app/lib` | 141 (~43 000 líneas) |
| Navegación | Imperativa: 129 `Navigator.push` en 41 archivos, sin router ni rutas con nombre |
| Hojas inferiores / diálogos | 44 `showModalBottomSheet` · 45 `showDialog` (varios contienen pantallas completas) |
| Degradados | 79 usos |
| Colores fijos `Color(0x…)` fuera del tema | 257 valores distintos |
| Pruebas Flutter | 41 archivos |
| Migraciones SQL | 44 |

### 1.1 Lo que está bien y se conserva
- **Registro único de funciones** (`screens/catalog.dart → featureCatalog()`): menú, buscador y accesos leen de aquí; cada
  función declara plan (`feature`), permiso (`perm`) y rubro (`rubroShows`). Es la base natural del contrato de navegación.
- **Rubros como datos** (`rubros.dart → RubroSpec`): barra de 4 destinos, vocabulario, Inicio, áreas del menú, núcleo.
- **Licencias que fallan cerradas** (`access.dart`): sin licencia verificada en línea no hay funciones; Hub manda
  (`20261125`: `has_feature` = `effective_features(org)`; límite ausente = 0).
- **Roles en la base**: `set_member_role_impl` ya impide que un administrador ascienda a otro a administrador o toque al
  propietario. RLS por empresa en todas las tablas.
- **Flujo de venta del PR #9**: `PosScreen → PosCartReviewScreen → choosePosPayment → fastCheckoutAtomic → comprobante`.

### 1.2 Lo que está mal organizado
1. **Pantallas duplicadas para la misma responsabilidad**
   - Inicio: `home.dart` (`HomeScreen`, 1 114 líneas, lista heredada de comprobantes) **y** `inicio.dart` (`InicioScreen`).
     `shell.dart` aún monta `HomeScreen` en la barra heredada v2.
   - Clientes: `clients.dart` · `clients_hub.dart` · `clients360.dart`.
   - Ajustes: `settings.dart` · `settings_v2.dart`. Tienda: `store.dart` · `store_v2.dart`. Venta: `sell_hub.dart` · `pos.dart`.
   - Agrupadores v3 (`hubs_v3.dart`: `OwedHubScreen`, `BusinessHubScreen`) que repiten cobranza/fiados y negocio.
2. **Varios nombres para lo mismo**: "Mi negocio" lo usaban dos funciones distintas (`negocio_hub` y `negocio`).
   → **Corregido en esta rama** ("Mi negocio" = el agrupador; "Ganancia real" = la pantalla de margen) y protegido por prueba.
3. **Tres barras de navegación** en `shell.dart → _dests()`: técnico fija, rubro (4 destinos) y heredada v2
   (simple/completa). Cada una con su propia lógica de "a dónde vuelvo".
4. **Acción principal escondida**: solo la bodega tenía su botón ("Vender" en la cabecera). Salón, taller, restaurante…
   veían un carrusel horizontal de accesos genéricos con "Nueva venta" primero.
   → **Corregido en esta rama** (ver §3.3).
5. **Permisos gruesos**: `my_access().can` tiene 11 claves; `Access.can()` cae en `isAdmin` si la clave no existe
   (permitir por defecto para administradores). El administrador podía ver "Pagar o mejorar mi plan".
   → **Corregido en la pantalla** (§4): permisos granulares con denegación por defecto; suscripción solo propietario.
6. **Destino sin permiso de rol**: la pestaña "Mesas" (`tables`) solo miraba el plan, no el rol.
   → **Corregido**: exige `sell` además de `carta_qr`.
7. **Diseño**: degradados en casi todos los encabezados y botones, 257 colores sueltos, tarjetas con sombra fuerte, alturas
   fijas que cortan texto con letra grande. Hay `DESIGN_SYSTEM.md` y `ERP_DESIGN_SYSTEM.md` que el código no sigue del todo.

## 2. Estructura propuesta

```
app/lib/
  nav/navigation_contract.dart   ← NUEVO: destinos nivel 1 + acción principal por rubro (fuente de verdad)
  permissions.dart               ← NUEVO: permisos granulares → my_access().can + plan (denegar por defecto)
  screens/catalog.dart           ← sigue siendo el registro único de funciones (nivel 2)
  rubros.dart                    ← rubro = datos (barra, vocabulario, áreas, núcleo)
  screens/<módulo>/...           ← fase siguiente: agrupar por módulo (ventas, caja, inventario, compras, comprobantes…)
```

Niveles: **1** barra (máx. 4 + micrófono) → **2** funciones desde Inicio/Menú (`featureCatalog`) → **3** detalle/edición
(pantalla completa) → **4** acciones cortas en hoja inferior (una decisión, nunca una pantalla entera).

### 2.1 Mapa de navegación (nivel 1) por rubro

| Rubro | Barra | Acción principal en Inicio |
|---|---|---|
| Bodega | Inicio · Vender · Fiados · Caja | **Vender** (cabecera) → POS |
| Restaurante | Inicio · Mesas · Caja · Negocio | **Nuevo pedido** → POS |
| Servicios técnicos | Inicio · Trabajos · Abonados · Cobrar | **Nueva orden** → formulario de trabajo |
| Salón | Inicio · Citas · Clientes · Caja | **Nueva cita** → formulario (tipo cita) |
| Consultorio | Inicio · Agenda · Pacientes · Cobrar | **Nueva cita** → formulario (tipo cita) |
| Taller | Inicio · Órdenes · Clientes · Cobrar | **Nueva orden** → formulario de trabajo |
| Mayorista | Inicio · Pedidos · Clientes · Cobranza | **Nuevo pedido** → cotización/pedido |
| Educación | Inicio · Alumnos · Pensiones · Horarios | **Cobrar pensión** → pensiones pendientes |
| Construcción | Inicio · Obras · Cobrar · Negocio | **Nueva obra** → formulario (tipo obra) |

El botón solo aparece si el rol tiene el permiso granular y el plan la función (nunca un botón sin destino válido).

### 2.2 Contrato por destino
Cada destino de la barra declara en `navContracts`: id, objetivo (una responsabilidad), función del plan, permiso
granular, acción principal, estado que conserva y datos que invalida. Las pruebas verifican que **todo destino de todo
rubro tenga contrato**, que **toda acción principal apunte a una función existente** y que **no haya dos funciones con el
mismo nombre**.

## 3. Roles y permisos

### 3.1 Roles reales hoy
`organization_members.role` ∈ {owner, admin, member} + `staff_role` ∈ {finanzas, cajero, tecnico, vendedor}.

| `can` | owner | admin | finanzas | cajero | vendedor | técnico |
|---|---|---|---|---|---|---|
| finance | ✓ | ✓ | ✓ | – | – | – |
| sell / collect | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| clients / jobs | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| all_jobs | ✓ | ✓ | ✓ | ✓ | ✓ | – |
| products_edit / import | ✓ | ✓ | ✓ | – | – | – |
| team / settings / license | ✓ | ✓ | – | – | – | – |

### 3.2 Permisos granulares (implementado en `permissions.dart`)
`sales.create/read/cancel/discount`, `payments.record/refund`, `cash.open/close/read_all`,
`products.read/create/update`, `inventory.adjust`, `purchases.create/approve`, `reports.view/profit`,
`customers.manage`, `jobs.create/read_all`, `team.manage`, `settings.manage`, `data.import`, `subscription.manage`.
Permiso efectivo = función contratada + permiso del rol + rol de membresía. Id desconocido → **denegado**.
`subscription.manage` es solo del propietario (la base aún lo permite al administrador: ver §6, migración propuesta).

### 3.3 Roles por rubro (pendiente de backend)
Los roles especializados (mesero, cocinero, barbero, recepcionista, mecánico, almacenero, cobrador, docente, jefe de
obra…) **no existen** en la base. Propuesta compatible: nueva columna `rubro_role` (texto libre validado por rubro) que
solo cambia **presentación** (Inicio, vocabulario) y se mapea a uno de los `staff_role` actuales para los permisos.
Ejemplo: mesero/cocinero → `cajero` sin `collect`… requiere permiso fino nuevo, por eso va en migración aparte y revisada.

## 4. Inicio por rol (siguiente paso)
- Cajero: caja asignada, NUEVA VENTA, últimas operaciones, estado de caja. (Hoy ve el total del mes porque `seeMoney` = finance **o** collect; debe ver solo su caja.)
- Dueño: ventas del día, fiados, stock bajo, margen, compras pendientes, caja, equipo, reportes.
- Técnico/operario: sus trabajos (ya existe `WorkQueue` y `JobsScreen(mine: true)`).
- Cocinero y barbero: dependen de §3.3.

## 5. Planes (implementado: comparación con Pro protagonista)
`PlanScreen` ahora muestra **Compara los planes**: Básico · **Pro** · Empresa. Pro con borde de marca, insignia
"RECOMENDADO" y botón principal; en tablet va al centro y más ancho, en teléfono al medio de la lista. Funciones de
`planMatrix` (copia de `private.plan_matrix`), precios de `planPrices` (= `docs/facturavoz-planes.json`, ya probado) con
la nota "Precio referencial con IGV. El cobro lo confirma Solvex". **No** se puso "Más elegido" (no hay datos reales).
Prueba gratis: la duración la fija Solvex Hub (`org_licenses`, estado `prueba`); **no se cambió**. Llevarla a ≥ 7 días es
una configuración del Hub, no de esta app.

## 6. Cambios de backend propuestos (NO aplicados)
1. `my_access_impl`: `license` solo para `owner` (hoy owner+admin). Afecta quién puede pagar desde la app.
2. Columna `organization_members.rubro_role` + validación por rubro (§3.3).
3. Permisos finos nuevos que hoy no existen: `cash.open` separado de `collect`, `sales.discount` propio.
Se escriben como migraciones nuevas, idempotentes, probadas en Postgres local, y se aplican solo cuando lo pidas.

## 7. Hecho en esta rama
- `lib/nav/navigation_contract.dart`, `lib/permissions.dart`, `lib/screens/plan_compare.dart` (nuevos).
- `inicio.dart`: botón de acción principal por rubro (altura mínima, no fija: no se corta con letra grande).
- `license_gate.dart`: pagar/renovar solo propietario; comparación de planes.
- `catalog.dart`: "Mi negocio" sin duplicar. `shell.dart`: "Mesas" exige permiso de venta.
- `test/navigation_contract_test.dart`: 11 pruebas (contratos, acciones, nombres únicos, permisos por rol).

## 8. Fases siguientes
1. Retirar la barra heredada v2 y `HomeScreen` del arranque (dejar `InicioScreen` como único Inicio).
2. Unificar Clientes (`clients_hub` canónico), Ajustes (`settings_v2`), Tienda (`store_v2`).
3. Tokens de diseño: reemplazar colores sueltos y degradados por `ColorScheme` (sin degradado salvo la cabecera).
4. Inicio por rol (§4) y roles por rubro (§3.3, con migración).
5. Matriz de investigación por rubro (16 preguntas del prompt) con fuentes SUNAT/MINSA/MTC/MINEDU.

## 9. Fase 2 (Prompt parte 2: §9.6–§12)
- **Matriz rubro × plan × rol**: motor único `nav/role_matrix.dart` (`roleExperience`) + 38 roles de rubro (más propietario, administrador y finanzas) sobre los 6
  roles base reales; documento generado `01_MATRIZ_RUBRO_PLAN_ROL.md` (`python3 tool/gen_matriz.py`), pruebas
  `test/role_matrix_test.dart` sobre todas las combinaciones. Taller, mayorista, educación y construcción (§9.6–9.9)
  tienen sus roles; los que la base no cubre exactamente están marcados ⚠ con la diferencia escrita.
- **Design System**: `02_DESIGN_SYSTEM.md` (paleta del prompt, modo claro AA, contrastes calculados, componentes `ds.dart`).
- **Bodega Básico**: `03_BODEGA_BASICO.md` (estado paso a paso; Inicio por rol y Caja reconstruidos).
- **Pendiente**: investigación por rubro con fuentes oficiales (§8, 16 preguntas) y migraciones de roles por rubro.
