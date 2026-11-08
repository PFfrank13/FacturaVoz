# Abrir el Plan Básico Bodega actualizado en Android Studio (Windows)

El emulador puede seguir mostrando **Activa tu FacturaVoz** cuando ejecuta
`codex/facturavoz-evolucion`, cuyo código todavía exige `source == hub`.
Esto no demuestra que Supabase siga bloqueado: el tenant de ensayo usa
`source=local`, `plan=BASICO`, `status=activa`, `mode=full`.

**No ejecutes `git reset --hard`, `git clean`, ni cambies de rama en la carpeta
original.** La rama `codex/facturavoz-evolucion` conserva varias mejoras no
fusionadas de interfaz, recepción de mercadería y caja. Forzar `main` sobre
ella haría perder esos cambios.

## Ruta segura: una segunda carpeta desde main

1. En Android Studio, mantén encendido el emulador Android y detén la ejecución
   Flutter anterior (botón Stop) si todavía está depurando.
2. Abre **Terminal** dentro de la carpeta `app` original y ejecuta:

```powershell
git fetch origin main
git show origin/main:tools/abrir_plan_basico_windows.ps1 | Set-Content -Encoding UTF8 "$env:TEMP\abrir_plan_basico_windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\abrir_plan_basico_windows.ps1"
```

3. El script crea/actualiza `FacturaVoz-PlanBasico\app` como un worktree
   independiente. No sobreescribe ni cambia `codex/facturavoz-evolucion`.
4. Si existe `app\dart_defines.json` en el proyecto original, lo reutiliza.
   En caso contrario pide la clave **publicable** de Supabase (anon o
   `sb_publishable_`), nunca `service_role`. Escribe la nueva configuración
   solo en el `app\dart_defines.json` ignorado por Git.
5. Ejecuta `flutter pub get`, detecta el emulador y
   `flutter run -d <emulador> --debug --dart-define-from-file=<archivo>`.
   Desde Android Studio también puedes abrir **File → Open** y seleccionar
   la nueva carpeta `FacturaVoz-PlanBasico\app`.

**Prueba sin ejecutar**: agrega `-PrepareOnly` al comando de PowerShell.
**Emulador concreto**: agrega `-DeviceId emulator-5554` si está disponible.

La instalación no desinstala, borra datos, resetea contraseñas ni cambia
la licencia. Si Android rechaza actualizar la app por firma incompatible,
**no desinstales automáticamente**: preservar primero las credenciales
y los datos locales del teléfono.

## Qué ver

Inicia sesión con la misma cuenta y empresa de ensayo. Verifica:

- **Vender → Venta rápida**: productos y carrito.
- **Cobrar**: selector Efectivo, Yape, Plin, Tarjeta y Transferencia.
- **Confirmar**: cálculo de vuelto o comprobación manual del cobro.
- **Pago confirmado**: Boleta, Factura, Compartir y Ver comprobante.
- **Productos**, **Inventario**, **Compras**, **Fiados** y **Caja** visibles
  según permisos del rol.

El QR que aparece para Yape/Plin debe ser una foto exportada por el negocio
y cargada en Ajustes → Medios de cobro. Mostrar una marca no prueba una
transferencia bancaria. Para emitir comprobantes SUNAT reales se requieren
RUC, SOL, certificado y datos fiscales válidos.

Si no se abre el Plan Básico, verifica primero que la compilación se
realizó desde `FacturaVoz-PlanBasico\app` y que
`SUPABASE_URL=https://qzcpeipjlskyazrrelqu.supabase.co`. Pulsa
«Reintentar acceso al Plan Básico»; si sigue bloqueado, revisa los
mensajes de Flutter y las respuestas de `my_license` / `my_access`.

## Después

La rama `codex/facturavoz-evolucion` y `main` tienen commits divergentes
con cambios de UI y flujo que necesitan una integración específica y tests
de regresión. Esta vista previa de `main` es la forma segura de validar ya
el POS nuevo sin perder esa evolución.
