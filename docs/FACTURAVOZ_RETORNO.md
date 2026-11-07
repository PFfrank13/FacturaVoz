# FacturaVoz: retorno al producto original — 7 noviembre 2026

La instrucción nueva cancela Solvex Retail como producto independiente y
reemplaza la dirección de los documentos anteriores. No cancela mejoras técnicas
ni permite borrar históricos o romper Solvex Hub.

## Punto de recuperación

- Base original: `704632d`, main y archive/facturavoz-before-solvex-20261107.
- Trabajo reciente completo: `8556732`, conservado en la rama remota anterior,
  archive/solvex-retail-20261107 y bundle privado before-facturavoz-return.bundle
  (verificación Git aprobada, historial completo).
- Rama de evolución: codex/facturavoz-evolucion. Continúa el historial original;
  recupera selectivamente la identidad sin resetear las mejoras posteriores.
- Sin cambios a paquetes Android, identificadores iOS, APIs, Supabase, Hub,
  AWS, Caddy, web corporativa ni datos históricos.

## Primera fase implementada

Marca visible FacturaVoz en Flutter, Android/iOS, Flutter web y Next.js.
Se recupera el icono original Flutter. Se conservan tipografía local, accesibilidad,
layout responsive, POS, idempotencia, recepción, refresco y pruebas recientes.
Componentes y tablas con nombres internos retail no se renombran a ciegas.

Flutter deja de exigir RubroPicker al entrar y usa Inicio/Vender/Caja/Herramientas
según permisos. No cambia el rubro histórico que interpreta la licencia del Hub.
Web usa navegación agrupada por ventas/clientes, productos/abastecimiento y
administración. El POS e inventario no dependen del antiguo sector, pero siguen
exigiendo licencia y permisos. Agenda/trabajos dejan el menú activo; sus rutas
históricas siguen autorizadas por las reglas anteriores.

## Videos observados

Se extrajeron y observaron fotogramas de ambos MP4, sin copiar código ni diseño.
El video del 25 octubre (21 s) es una demo móvil de pizza: introducción, login,
catálogo visual. No es FactuSmart ni prueba funcionalidades fiscales.
El del 27 octubre (121 s) muestra FactuSmart: formulario de comprobante y líneas,
resultado del comprobante, POS visual, catálogo público, edición de productos,
pagos de compras, inventario y cobros individuales/múltiples de deudas.
La relación relevante es compartir cliente/producto/documento entre venta,
inventario y pagos. Un registro o modal visible no acredita aceptación SUNAT.
No se verificaron transacciones del producto de referencia ni se analizó su audio.

## Pendientes explícitos

- Sustituir el onboarding/configuración sectorial restante por productos,
  servicios o ambos. Persistir esa preferencia sin reescribir el rubro de licencia.
- Retirar las restantes presentaciones verticales de herramientas/inicio móvil.
- Completar cliente → venta → pago → emisión real → historial; mantener estados
  fiscales separados de una venta guardada o PDF generado.
- Validar descuentos/promociones, pago mixto, abonos, cierre de caja y borrador
  durable móvil antes de aplicar propuestas SQL remotas.
- Navegador Work estaba deshabilitado: no certificar revisión visual ni sesión
  autenticada de Preview sin observarlas.
- El proyecto vacío solvex-retail-control queda sin despliegues; no se utiliza,
  no se elimina ni se crea otro. Los Preview pertenecen al proyecto factura-voz.

Esta es una fase de recuperación, no la conclusión de los cinco recorridos.

## Verificación y continuación del onboarding

Backend: 173 pruebas aprobadas, ESLint y build Next aprobados. Flutter: analyze
sin incidencias y 6 pruebas de identidad/layout POS aprobadas.
Onboarding comercial implementado: productos/servicios/ambos, guardado aditivo
en labels.commercial_offer, sin modificar business_type. Error de persistencia
visible; no se anuncia finalización si el guardado falla. Prueba adicional de
serialización/conservación de contexto histórico aprobada.
Faltan integrar datos comerciales, moneda e impuestos en ese recorrido y retirar
las presentaciones sectoriales restantes de herramientas/configuración.

Commit web `7e51b07` publicado en codex/facturavoz-evolucion. Preview solicitado
en el proyecto original: https://factura-2tyg8lcb4-portafolio-frank.vercel.app.
No se certifica sesión autenticada ni verificación visual por compilar.
