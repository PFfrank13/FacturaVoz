# FacturaVoz Fase 36 — Diseño fotográfico por rubro

Base: FacturaVoz Fase 35 HOTFIX (correcciones pos.dart y settings.dart conservadas).

## Cambios implementados
- Identidad índigo/cobalto + violeta y acento azul cian. Conserva modo claro y oscuro.
- Logotipo real incluido en BrandMark; la bienvenida animada ya existente continúa y respeta reducir movimiento.
- Tarjetas con fotografía contextual para elegir uno de los nueve rubros (alta y vista previa).
- Cabeceras diferenciadas en Inicio, Vender, Productos, Clientes, Reportes y Ajustes.
- El POS vacío muestra fotografía contextual; fotos de productos siempre son las subidas por el propietario.
- Material de referencia específico para nueve rubros en docs/REFERENCIAS_VISUALES_FASE36. Son mockups de diseño, NO capturas reales ni pruebas de funcionalidad; no se incluyen como pantallas de la app.
- Fotografías locales WebP para funcionamiento sin internet; no se añaden dependencias.

## Importante
- Esta entrega es un rediseño visual sobre la base anterior. No es una reconstrucción de cada pantalla ni implementa las funcionalidades hipotéticas mostradas en los mockups.
- No certifica 200 clientes ni 30.000 ventas/día. Las pruebas del plan siguen pendientes en staging.
- La última migración incluida en el ZIP sigue siendo 20261123_fast_checkout_atomic: **no hay migración SQL nueva en esta fase visual**.
- No se ejecutaron flutter analyze, flutter test ni compile release en este entorno (Flutter no disponible). Hay que comprobar en Windows antes de desplegar.

## Comandos en Windows
En la carpeta app:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run --release --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY --dart-define=API_BASE_URL=https://TU_BACKEND
```

No pegues secretos service_role ni tokens privados en la app. Después de compilar, revisa onboarding/rubros, imágenes locales, cada barra por rubro y el flujo de caja y comandas.
