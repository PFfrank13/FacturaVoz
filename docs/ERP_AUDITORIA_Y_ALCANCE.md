# FacturaVoz — auditoría e implementación local

Fecha: 4 de noviembre de 2026. Base: `4f9f593`, rama `main`.

## Estado y límites de esta entrega

Se implementó una base ERP web conectada al backend existente y se reforzaron permisos y navegación móvil. **No equivale todavía a la transformación integral ni a nueve ERP sectoriales terminados.** Los módulos y verificaciones pendientes se indican abajo; no deben comercializarse como terminados.

Git estaba limpio al comenzar. Existe otro worktree, `voice-invoice-solvex-preview`, rama `fix/solvex-enforcement-preview`; no se editó. No se ejecutaron push, despliegues, migraciones productivas, cambios de secretos ni modificaciones de licencias reales. No se cambió el webhook ni el cron de Solvex. Sus rutas siguen sin invocar `license_set_enforced`.

## Arquitectura encontrada

- `app/`: Flutter con catálogo de funciones, nueve rubros, shell contextual, temas, Supabase Auth, RLS/RPC, licencias y tiempo real. Los procesos móviles existentes se conservan.
- `backend/`: Next.js 15, React 19, API autenticada, páginas públicas por token y una web heredada mínima. La nueva web vive en `/erp/[org]` y reutiliza Supabase y sus RPC; no crea empresas o suscripciones paralelas.
- `backend/supabase/migrations/`: evolución del esquema y de las autorizaciones. La numeración existente llega a `20261124`, aunque la fecha de esta entrega es anterior. Se conserva esa secuencia en `20261125_v32_hub_feature_precedence.sql`.
- `solvex-plataforma-actualizado/`: integración y Hub existentes; no modificados.
- `infra/`, Vercel y GitHub workflows: conservados, sin operaciones remotas.

La revisión se concentró en acceso, navegación, consultas, acciones web, rubros y migraciones relacionadas. No es una auditoría exhaustiva de cada procedimiento, pantalla ni integración fiscal.

## Hallazgos corregidos

1. `private.plan_allows` de `20261118` devolvía true por núcleo/matriz incluso con `stock=false`. Se reprodujo con las definiciones históricas en PostgreSQL local.
2. `20261124` ya sustituía `effective_features` por la respuesta Hub. Por eso no se puede afirmar que producción siga usando la función antigua sin inspeccionar su esquema desplegado. No se consultó producción.
3. El helper histórico seguía existiendo. La migración nueva elimina su capacidad de conceder derechos por plan/rubro, distingue booleanos de límites y hace que un límite omitido o inválido sea cero.
4. La guardia SQL comprobaba la función solo al insertar. La propuesta valida actualizaciones y cambios de tipo; protege cambios de existencias y mínimos. Añade políticas SELECT restrictivas a tablas operativas, conservando las políticas existentes.
5. Flutter aceptaba números como funciones booleanas, límites de desarrollo, y exponía funciones cacheadas a través de `has`. Ahora exige autorización positiva verificada y rechaza estados obsoletos. Descarta respuestas de otra empresa o de una carga anterior.
6. El menú y el inicio usaban `roleOk` y mostraban funciones sin licencia con candados. Filtran por `allowed`. La barra, el micrófono y accesos básicos comprueban también su función comercial.
7. La web heredada listaba facturas sin selección explícita de empresa y guardaba en EUR. Ahora valida usuario y pertenencia, filtra por empresa y guarda con `p_org_id` y la moneda de la organización.
8. `/api/parse` podía consumir proveedor sin comprobar licencia de voz. Ahora comprueba voz, facturación y permiso de venta antes de consumir cuota/proveedor.

## Matriz funcional real

En todos los casos, la visibilidad exige función Hub, permiso y compatibilidad. Una ruta desconocida o denegada no consulta datos del módulo.

| Rubro | Base móvil existente revisada | Prioridades web implementadas | Pendiente sectorial web |
|---|---|---|---|
| Bodega | POS, fiados, caja, catálogo | Comprobantes, inventario, clientes, cobros | POS táctil, fiados y cierre de caja |
| Restaurante | Mesas, QR, cocina y comandas sobre quotes | Comprobantes, productos, cobros, clientes | Mapa de mesas, cocina, comandas y turnos |
| Servicios técnicos | Trabajos, agenda, clientes | Trabajos, agenda, clientes, cotizaciones | Seguimiento detallado, materiales, entregas |
| Salón | Agenda, servicios, comisiones | Agenda, clientes, productos, cobros | Calendario por profesional y comisiones |
| Consultorio | Agenda, pacientes, notas existentes | Agenda y registro administrativo de pacientes | Horarios y controles administrativos específicos; sin nuevas funciones médicas |
| Taller | Órdenes, placas y repuestos | Trabajos, inventario, cotizaciones, clientes | Detalle por vehículo y entregas |
| Mayorista | Cotizaciones, precios, créditos | Cotizaciones, inventario, clientes, cobros | Precios por volumen, crédito, multimoneda operativa |
| Educación | Contactos, agenda, recurrentes | Agenda, contactos, cobros, comprobantes | Pagos recurrentes y horarios; no LMS ni calificaciones |
| Construcción | Trabajos, materiales, hitos y gastos | Trabajos, cotizaciones, inventario, cobros | Hitos, materiales, responsables y costos de obra |

### Qué hace la web ahora

- Acceso por correo/código, selección de empresa y navegación autorizada.
- Dashboard con prioridades de los nueve rubros y conteos reales de registros accesibles. Los conteos no se presentan como ventas del día ni como indicadores financieros.
- Tablas con búsqueda **en la página actual**, ordenación local, paginación de 50 filas en servidor y estados de error/vacío.
- Alta de clientes, productos, trabajos y citas administrativas. No edición/borrado general.
- Borrador de comprobante manual o por voz, revisión, múltiples artículos y PDF interno; no se implementó emisión fiscal web nueva.
- Consulta de inventario, cotizaciones y cobros; consulta de equipo, configuración y licencia.
- Reportes mediante `sales_summary`, periodo de hasta 366 días, moneda de empresa y regla fiscal existente.
- Refresco de licencia por evento realtime, foco y sondeo de 60 segundos. Las mutaciones vuelven a validar en servidor; una pestaña abierta no constituye autorización.

### Qué cambia en móvil

Además de la seguridad, salón/consultorio/educación incorporan citas de hoy y servicios/taller/construcción una lista de trabajos por avanzar, usando registros reales y abriendo el detalle existente. Máximo cuatro filas, errores recuperables y tipografía adaptable. No reemplaza todos los inicios por nueve composiciones nuevas.

## Siguiente trabajo necesario

1. Validar la migración completa contra una copia local del esquema real y una matriz de usuarios/empresas sintéticos. El harness actual prueba funciones y triggers con tablas mínimas, no todo Supabase.
2. Completar permisos de lectura por columna de productos: el catálogo comparte tabla con stock. La migración protege modificaciones de stock, pero no oculta condicionalmente columnas a clientes directos de Supabase.
3. Completar los procesos web sectoriales de la matriz, edición, gestión de equipo y configuración. Sucursales no se implementa como duplicación de empresas: requiere aclarar el modelo real de organización/sucursal antes de añadirlo.
4. Probar flujo autenticado completo de altas/ventas, renovaciones/revocaciones en vivo, voz y cambio de empresa con datos sintéticos. No se usaron cuentas reales.
5. Sustituir/validar el catálogo fotográfico con licencias verificables y documentar cada fuente. No se añadieron fotos externas ni imágenes IA.
6. Realizar revisión visual de todos los módulos autenticados y los nueve rubros en dispositivos reales; probar impresión, micrófono y accesibilidad con lectores de pantalla.

La migración permanece **sin aplicar**. No ejecutar indiscriminadamente las migraciones históricas en producción: algunas contienen actualizaciones de licencias y configuración global.
