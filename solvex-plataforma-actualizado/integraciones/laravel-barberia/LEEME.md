# Conectar la barbería (Laravel) con Solvex Hub

Con esto, cada barbería del sistema se **corta sola** cuando el Hub lo indica y **vuelve sola en segundos** cuando paga. No hay que tocar nada a mano.

Cómo funciona, en simple:

1. Cuando algo cambia en una licencia (pago, corte, cambio de plan), el Hub envía un **aviso firmado** (webhook) a `https://TU-APP/api/solvex/webhook`.
2. Ese aviso trae un **token firmado** con la llave privada del Hub. La barbería lo verifica con la **llave pública**: nadie puede inventarse un "estás activo".
3. Cada 5 minutos, `php artisan solvex:sync` vuelve a consultar todo por si algún aviso no llegó.
4. Aunque el Hub esté caído, el token trae la fecha exacta de corte: llegado ese momento, la barbería se restringe igual.

> Todo se hace en la terminal de VS Code, dentro de la carpeta `solvex-backend` (WSL).

## Paso 1 · Copiar los archivos

Copia cada archivo de esta carpeta a la misma ruta dentro de `solvex-backend`:

| Archivo | Va en |
|---|---|
| `config/solvex.php` | `config/solvex.php` |
| `app/Services/Solvex/LicenseToken.php` | igual |
| `app/Services/Solvex/LicenseState.php` | igual |
| `app/Services/Solvex/SolvexHub.php` | igual |
| `app/Http/Controllers/SolvexWebhookController.php` | igual |
| `app/Http/Middleware/EnsureBusinessLicensed.php` | igual |
| `app/Console/Commands/SolvexSync.php` | igual |
| `database/migrations/2026_10_20_000001_add_solvex_license_to_businesses_table.php` | igual |
| `resources/views/solvex/suspended.blade.php` | igual |
| `tests/Feature/SolvexLicenseTest.php` | igual |

Comprueba que PHP tenga libsodium (viene incluido en PHP 8.x):

```bash
sail php -m | grep sodium
```
Debe mostrar `sodium`.

## Paso 2 · Base de datos

```bash
sail artisan migrate
```
Debes ver `2026_10_20_000001_add_solvex_license_to_businesses_table ... DONE`.

En `app/Models/Business.php`, agrega a los `casts` (dentro de `casts()` o `$casts`):

```php
'license_period_end' => 'datetime',
'license_cut_at' => 'datetime',
'license_token_exp' => 'datetime',
'license_checked_at' => 'datetime',
'license_features' => 'array',
```
y oculta el token en las respuestas JSON: `protected $hidden = ['license_token'];` (súmalo si ya tienes `$hidden`).

## Paso 3 · Rutas, middleware y tarea programada

**routes/api.php** (las rutas de `api.php` no usan sesión ni CSRF; si no tienes ese archivo: `sail artisan install:api`):

```php
use App\Http\Controllers\SolvexWebhookController;

Route::post('/solvex/webhook', SolvexWebhookController::class)
    ->middleware('throttle:120,1')
    ->name('solvex.webhook');
```

**bootstrap/app.php**, dentro de `->withMiddleware(function (Middleware $middleware) { ... })`:

```php
$middleware->alias(['licensed' => \App\Http\Middleware\EnsureBusinessLicensed::class]);
```

**routes/console.php**:

```php
use Illuminate\Support\Facades\Schedule;

Schedule::command('solvex:sync')->everyFiveMinutes()->withoutOverlapping();
```

Protege las rutas:

```php
// Panel de la barbería y API de la app del barbero
Route::middleware(['auth:sanctum', 'licensed'])->group(function () { /* ... */ });

// Web pública de reservas (solo bloquea crear reservas nuevas)
Route::middleware('licensed:public')->group(function () { /* POST de reservas */ });
```

Cuando la barbería está **suspendida**, el dueño todavía puede entrar a las rutas cuyo nombre coincida con `restricted_allow` en `config/solvex.php` (pagar, exportar datos, salir). Ajusta esos nombres a los de tu app.

> Importante: las citas que los clientes ya pagaron **no se cancelan** por un corte. El enlace personal de cada cita debe seguir funcionando para ver, cancelar o pedir reembolso (no lo pongas detrás de `licensed`).

## Paso 4 · Variables de entorno

En el Hub: **Integraciones → Nueva instancia** (nombre "Barbería SaaS · producción", URL del webhook `https://TU-APP/api/solvex/webhook`). Copia lo que muestra **una sola vez** y pégalo en el `.env` de la barbería:

```dotenv
SOLVEX_HUB_URL=https://hub.solvex.pe
SOLVEX_INSTANCE_ID=ins_xxxxxxxxxxxxxxxxxxxx
SOLVEX_API_KEY=slxk_xxxxxxxx_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SOLVEX_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SOLVEX_PUBLIC_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
SOLVEX_TENANT_COLUMN=slug
```

`SOLVEX_INSTANCE_ID` se muestra al crear la instancia y en la tabla de Integraciones (columna "Id · clave"), y la llave pública está en **Integraciones → Llave pública de licencias → Formato libsodium**.

Luego:

```bash
sail artisan config:clear
sail artisan solvex:sync
```
Debes ver `Licencias actualizadas: N`.

## Paso 5 · Crear las licencias en el Hub

Por cada barbería: **Licencias → Nueva licencia**, cliente, producto "Sistema de Barbería", plan, instancia "Barbería SaaS · producción" e **identificador = el `slug` de la barbería** (exactamente igual).

Prueba de punta a punta: en el Hub, **Integraciones → Enviar ping** debe quedar "Entregado". Después suspende manualmente una licencia de prueba y verás la pantalla de suspensión en la barbería en segundos; levanta la suspensión y vuelve.

## Paso 6 · Pruebas automáticas

```bash
sail artisan test --filter=Solvex
```
Deben pasar 6 pruebas. Si `Business::create` falla por campos protegidos, cambia esa línea del `beforeEach` por tu factory: `Business::factory()->create(['slug' => 'don-corte'])`.

## Límites por plan

El token trae las funciones del plan (`max_branches`, `max_barbers`, ...). Úsalas así:

```php
use App\Services\Solvex\LicenseState;

$max = LicenseState::feature($business, 'max_branches'); // -1 = ilimitado, null = no definido
if ($max !== null && $max !== -1 && $business->branches()->count() >= $max) {
    abort(403, 'Tu plan permite hasta '.$max.' sede(s).');
}
```

## Errores comunes

| Síntoma | Causa | Solución |
|---|---|---|
| El ping queda "Fallido · HTTP 401" | `SOLVEX_WEBHOOK_SECRET` distinto o reloj del servidor desfasado | Copia de nuevo el secreto; sincroniza la hora (`timedatectl`). |
| "HTTP 422" en los avisos | `SOLVEX_PUBLIC_KEY` o `SOLVEX_INSTANCE_ID` incorrectos | Revisa ambos valores y `config:clear`. |
| `solvex:sync` dice "No se pudo conectar" | URL o clave de API mal, o IP no permitida en la instancia | Revisa `SOLVEX_HUB_URL` y `SOLVEX_API_KEY`. |
| La barbería no cambia | El identificador de la licencia no coincide con el `slug` | Edita la licencia en el Hub con el slug exacto. |
| El webhook devuelve 419 | La ruta quedó en `web.php` (CSRF) | Muévela a `routes/api.php`. |
