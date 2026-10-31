# FacturaVoz v3.1 · Fase 19 — Error al abrir la app (setState durante build)

Primer arranque en el teléfono (`flutter run`): compiló e instaló bien; en consola salió
"setState() or markNeedsBuild() called during build" (ListenableBuilder, desde `AppState.load` llamado en `_ProfileGateState.initState`).

- `lib/main.dart`: la carga inicial ahora se lanza tras el primer cuadro (`addPostFrameCallback`) en vez de dentro de `initState`. Mientras tanto se ve la pantalla de carga (ya era el caso cuando aún no hay perfil).
- No cambia nada más. Sin cambios en base de datos ni backend.
- Verificado: sintaxis. Falta confirmar en tu consola que el error ya no sale.
