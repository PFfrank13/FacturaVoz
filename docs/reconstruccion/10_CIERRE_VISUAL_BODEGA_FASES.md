# FacturaVoz — cierre visual y funcional de Bodega/Tienda
Fecha de corte: 17-11-2026. Alcance: Bodega/Tienda en BÁSICO, PRO y EMPRESA; los otros ocho rubros permanecen intactos.

## Reglas no negociables

1. Un solo NavigationDrawer por sesión (Scaffold principal); sin BottomNavigationBar de Bodega ni submenús redundantes; sus secciones son Inicio, Vender, Fiados, Caja, Inventario y Configuración, filtradas por los permisos firmados del Hub.
2. AppBar transparente con título y menú. El acceso Copiloto se muestra únicamente si el Hub autoriza `copiloto`. En Básico, el micrófono abre el dictado comercial; no se promocionan funciones bloqueadas en el flujo.
3. No reemplazar APIs, flujos transaccionales, políticas RLS, contratos de licencia, lógica SUNAT ni inventar métricas/comprobantes. El cambio visual debe consumir pantallas y operaciones reales.
4. Una paleta semántica única (DsColors en `app/lib/ui/theme.dart`) en modo claro y oscuro; no usar `ThemeData.dark()` dentro de módulos; un solo estilo de tipografía, bordes, espacios y estados. Eliminar degradados y colores neón innecesarios.
5. Pro y Empresa incluyen las funciones contratadas; Básico no tiene candados de upsell, accesos de Copiloto, ni menús duplicados.
6. Los cambios se desarrollan en ramas/PR, con CI, y solo se integran si las puertas pertinentes pasan. No desactivar `audit-gate`, RLS ni otros controles para obtener verde artificial.

## Fases y puertas de salida

| Fase | Entrega | Estado verificable | Puerta de salida |
| --- | --- | --- | --- |
| 0. Auditoría y trazabilidad | Inventario de rutas, diseño, módulos y defectos, contrato de pruebas y tablero de seguimiento | Completada (este documento, inventario de abajo) | Riesgos, pruebas y criterios explícitos |
| 1. Base visual consistente | Unificar superficies y texto en Caja/Fiados/Ventas, tema claro/oscuro y retirar encabezados redundantes | En desarrollo — rama `feat/bodega-visual-fase1-20261117` | Flutter analyze + tests de UI/responsividad sin overflow + compile; revisión de diferencias |
| 2. Nueve flujos de Básico | Inicio, Ventas, Comprobantes, Fiados, Inventario, Compras, Caja, Reportes, Alta de productos, incluyendo pagos y ticket | Pendiente | Cada flujo real funciona, títulos/acciones coherentes, no menús/candados; accesibilidad de acciones |
| 3. Pro, Empresa y roles | Mismos componentes, expansiones comerciales reales y cada rol ve solo lo autorizado | Pendiente | Matriz Bodega × 3 planes × roles, sin promociones ajenas |
| 4. Calidad integral | Estados loading/vacío/error, accesibilidad, responsividad, teclado, contraste, rendimiento y recorridos integrados | Pendiente | 320/360/412/600 px, escalado 1.0/1.4, dos temas; cero overflow/análisis/test; checklist de tareas validado |
| 5. Entrega Android real | Build release firmado, credenciales prod, versionado, verificación de APK/AAB y actualización en dispositivo | Pendiente | Prueba en Android físico, firma y backend configurados, verificación del Hub y circuitos de venta/comprobante/caja |

## Hallazgos de auditoría sobre main bccd540 (antes de esta rama)

- `MainShell` ya aplica NavigationDrawer para Bodega, pero 8 rubros conservan su navegación anterior, intencionadamente fuera del alcance.
- `PosScreen` imponía un `ThemeData.dark` y fondo `#0B1030` incluso cuando la aplicación estaba en tema claro; mostraba badge de plan y encabezado adicional en modo embebido.
- `RetailVisual.hero/section/panel/microStat` mezclaba fondos #1B2149, degradados violetas, texto blanco fijo y sombras con el tema general `DsColors`; varias pantallas de Bodega dependen de estos componentes.
- `RetailReceiptsScreen` impone un tema oscuro propio y gradientes (abordar en fase 2).
- En Caja, el bar de Abrir/Cerrar es parte del flujo transaccional: no es navegación y no se elimina.
- La licencia comercial BÁSICO observada el 17-11 autoriza `stock=true`, `fiados=true`, `copiloto=false`.
- `backend audit-gate` sigue rojo por dependencias altas preexistentes, ajenas a estos commits de Flutter: **bloqueo de seguridad** que debe corregirse sin rebajar el gate.
- GitHub CI usa URLs y credenciales ficticias para compilar, **no certifica Android de producción**. El despliegue Vercel de Next.js **no actualiza una APK instalada**.

## Recorridos obligatorios de aceptación

1. **Inicio:** abrir Drawer → Venta → volver a Inicio; sin menú doble, sin segundo título, sin spinner permanente, métricas reales y acción Vender.
2. **Vender:** buscar/escáner → cantidad y precio → carrito → Yape/Plin/efectivo y vuelto → confirmación única. Prevenir cobros duplicados y conservar recuperación.
3. **Comprobantes:** Emitir → Historial → SUNAT → Compartir. No denominar aceptado por SUNAT un comprobante interno no aceptado.
4. **Fiados:** nueva deuda → abono → saldo actualizado e historial, accesible desde Drawer cuando el plan lo incluye.
5. **Inventario/Compras:** alta de producto, foto, código, stock → compra/recepción → inventario coherente; proveedores reales, sin registros simulados.
6. **Caja:** abrir → cobros y movimientos → arqueo ciego → cierre. No revelar saldo esperado antes del cierre.
7. **Reportes:** valores conciliables con ventas/comprobantes/caja por periodo.
8. **Roles/planes:** BÁSICO no muestra Copiloto ni candados. PRO/EMPRESA exhiben únicamente funcionalidades concedidas por Hub.
9. **Diseño:** 320px y letras ampliadas no cortan textos/acciones; dark/light con contraste; botones accesibles; scroll estable sin sobredibujos.

## Monitor y evidencias

- Vigilancia recurrente (cada 4 h): GitHub main/PR, Actions Flutter/backend/PostgreSQL y Vercel. Solo alerta por error nuevo, regresión o hito; nunca modifica producción por su cuenta.
- Cada PR debe indicar: fase, archivos tocados, pruebas ejecutadas, resultado de CI, captura o evidencia visual al estar disponible, riesgos y rollback.
- El control objetivo será [GitHub Actions](https://github.com/PFfrank13/FacturaVoz/actions), con commit SHA concreto, **no un informe verbal**.
- Considerar fase validada solo con artefactos y comprobaciones reales. Una APK debug con parámetros CI no cuenta como release comercial.
