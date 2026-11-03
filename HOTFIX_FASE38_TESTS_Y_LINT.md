# FacturaVoz Fase 38 — Hotfix de análisis y pruebas de licencias (02/11/2026)

Fuente: FacturaVoz v3.1 Fase 38 UX simplificada (9 rubros).

## Causa
`flutter analyze` reportó cuatro observaciones: dos imports sin usar, un if sin llaves y uso de BuildContext después de un await sin comprobar mounted.
`flutter test` reportó 13 fallos en dos suites antiguas. Las pruebas usaban licencias con mode por defecto `blocked` y/o esperaban que el modo desarrollo concediera todos los módulos. Esto contradice las restricciones comerciales introducidas en Fase 37.

## Correcciones
- `app/lib/access.dart`: quitar import sin uso.
- `app/lib/screens/rubro_picker.dart`: quitar import sin uso.
- `app/lib/screens/license_gate.dart`: encerrar if en llaves.
- `app/lib/screens/pos.dart`: validar `mounted` tras esperar a guardar el pedido antes de usar `context`; en dos flujos.
- `app/test/logic_v2_test.dart`: casos de licencia activa con permisos explícitos y modo sin licencia bloqueado.
- `app/test/rubros_v3_test.dart`: probar la concesión explícita de funciones desde Hub, revocación y planes simulados por rubro. No se alteró la lógica de bloqueo en producción.

## Validación
- Comparación binaria del ZIP original: únicamente seis archivos existentes modificados.
- ZIP íntegro verificado. No se ha ejecutado Flutter ni se ha probado Hub/Supabase en este entorno.
- Ejecutar en Windows desde `app`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

`flutter test` valida lógica local y widgets, no la activación real con Hub, la seguridad RLS ni la compilación en un dispositivo Android. No ejecutar nuevas migraciones SQL para este hotfix.
