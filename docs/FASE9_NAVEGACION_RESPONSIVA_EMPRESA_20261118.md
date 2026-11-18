# FacturaVoz · Fase 9: navegación empresarial adaptativa

## Objetivo
Una sola fuente de navegación Bodega/Tienda para móviles, tabletas y escritorios, con continuidad de sesión y permisos.

- Hasta 979 px: `Scaffold.drawer` lateral superpuesto; AppBar con botón de menú.
- Desde 980 px: mismo `NavigationDrawer` permanente de 284 px dentro del `Scaffold.body`; no se crea un segundo menú ni `BottomNavigationBar`.
- Al elegir un destino desde el menú fijo **no** se ejecuta `Navigator.pop()` (de lo contrario se cerraría indebidamente la pantalla actual). El overlay móvil sí se cierra.
- Mismo `bodegaDrawerIds(Access.instance)`: el rol y el plan siguen filtrando destinos, sin exponer módulos prohibidos.
- `LicenseBanner`, vistas y botón flotante conservan su lógica; los cambios son exclusivamente de presentación.
- Sin nueva dependencia, nuevos datos ni cambios de Supabase/Next.js.

## Verificación
- Test de punto de corte a 320, 360, 412, 600, 768, 979, 980, 1024, 1280, 1440 y 1920 px.
- Flutter analyze/test, generación web y APK debug, tests backend y migraciones SQL, emulador Android.
- El CI de compilación usa valores de entorno de prueba: no constituye despliegue de la app Flutter de cara al cliente.

## Producción
El proyecto Vercel `portafolio-frank/factura-voz` desplegado vía GitHub es el **backend Next.js**. La UI Flutter móvil debe distribuirse mediante un artefacto firmado con el keystore original; la compilación web requiere destino de hosting y configuraciones productivas correctas. No sustituir el backend con una web Flutter por error.
