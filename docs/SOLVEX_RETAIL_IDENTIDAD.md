# Solvex Retail — identidad y compatibilidad

Fecha: 2026-11-07. Marca de trabajo provisional; disponibilidad comercial y jurídica no verificada.

Actualización arquitectónica: cloud-first por instrucción expresa del usuario. PostgreSQL es la fuente de operaciones confirmadas. Los borradores locales no son ventas; no se exige base empresarial offline ni siete días desconectado. La puerta actual es una jornada comercial íntegra en laboratorio aislado; ver `REGISTRO_AVANCES.md`.

## Contrato visual

- Plataforma: Solvex Retail. Móvil/POS: Solvex Retail POS. Administración web: Solvex Retail Control. Fabricante: Solvex Software Labs.
- Símbolo vectorial propio: una S geométrica formada por estantes, sobre petróleo. Verde de acción #176B57, petróleo #102F32, lima #C9F27A, fondo papel #F5F5F0, tinta #142F30.
- Inter local en web, con licencia distribuida en `backend/public/fonts/Inter-LICENSE.txt`. Sin descarga de fuentes durante el build.
- Acceso centrado en la tienda; onboarding productos/revisión/cobro; navegación retail Vender/Inicio/Caja/Herramientas según permisos. El cobro muestra total, recibido, vuelto y estado de confirmación.
- Los estados distinguen borrador local, operación pendiente y respuesta confirmada. Un registro digital manual no implica verificación bancaria ni aceptación fiscal.

## Migración aplicada y pendiente

Se cambiaron componentes de marca, tema, acceso, onboarding, cabecera, títulos y nombres visibles de instalación. Se conservaron nombres internos como FacturaVozApp, tokens históricos del tema y clases CSS fv para reducir roturas.

No se cambiaron applicationId, paquetes Dart/Android, bundle identifiers, URL schemes, rutas API, tablas, organizaciones, dominios, secretos ni configuración externa. El diff de AndroidManifest e Info.plist afecta etiquetas y textos de permisos; no concede nuevos permisos. Voz, OCR y endpoints existentes siguen presentes.

Pendiente: completar revisión visual de todas las pantallas, páginas públicas/legales y activos de instalación (iconos/splash), validar Android en dispositivo y compilar iOS en macOS. No presentar el rebranding como terminado.

Una futura migración técnica será aditiva: inventariar consumidores, mantener aliases y callbacks antiguos, probar actualización sobre instalación existente y recuperación de datos, y sólo después evaluar retirada de compatibilidad. Los cambios de identificadores externos requieren autorización expresa. Reversión local: editar exclusivamente los textos/componentes de esta fase, conservando los cambios de negocio; no resetear el repositorio ni borrar almacenamiento de tickets.

## Capacidades de voz y documentos conservadas

Referencias: `app/lib/services/voice.dart`, `app/lib/logic/doc_voice.dart`, pantallas `scan.dart` y `new_invoice.dart`, endpoints `backend/src/app/api/{transcribe,parse,scan,tts}/route.ts`. Los archivos de servicio/endpoints no tienen modificaciones en este diff. Se mantienen controles existentes de acceso/licencia. El menú sólo ofrece el disparador de voz si el permiso voz está activo; el dock retail prioriza las operaciones comerciales.

Esta revisión identifica código reutilizable, no certifica proveedores ni funcionamiento con credenciales reales. No se hicieron solicitudes reales a proveedores. Búsqueda, reposición y compras asistidas por voz son trabajo futuro, no funciones anunciadas como disponibles.

## Límites comerciales actuales

La web calcula líneas e impuestos en centavos y milésimas de cantidad; Flutter usa centavos para validar efectivo/vuelto, pero sus totales y el contrato RPC todavía contienen decimales heredados. No se ha migrado toda la contabilidad.

El borrador web tiene esquema v1, revisión optimista, alcance usuario/organización y bloqueo exclusivo Web Locks. Conserva precios/moneda/impuesto y exige revisión ante cambios observados. Falta versionado autoritativo del catálogo en servidor. localStorage no es un libro contable, puede ser eliminado por el navegador y no está cifrado. Una lectura después de escritura prueba el guardado en ese navegador, no durabilidad ante fallo del dispositivo.

No hay nueva venta offline confirmada, base transaccional local ni sincronización contable. Puerta 1 sigue abierta.
