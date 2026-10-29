<?php

namespace App\Http\Middleware;

use App\Models\Business;
use App\Services\Solvex\LicenseState;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

/**
 * Bloquea el uso del sistema según la licencia de la barbería.
 *   full        → pasa.
 *   warning     → pasa y comparte el aviso (banner "pago pendiente").
 *   restricted  → solo rutas permitidas (pagar, exportar, salir). La reserva pública responde "no disponible".
 *   blocked     → no habilitado aún.
 *
 * Uso: Route::middleware(['auth', 'licensed'])->group(...);  y en la web pública: 'licensed:public'.
 * Regístralo en bootstrap/app.php:  $middleware->alias(['licensed' => EnsureBusinessLicensed::class]);
 */
class EnsureBusinessLicensed
{
    public function handle(Request $request, Closure $next, string $area = 'panel'): Response
    {
        $business = $this->resolveBusiness($request);
        if (! $business) {
            return $next($request);
        }

        $mode = LicenseState::effectiveMode($business);
        $request->attributes->set('license_mode', $mode);
        view()->share('licenseMode', $mode);
        view()->share('licenseBusiness', $business);

        if (in_array($mode, ['full', 'warning'], true)) {
            return $next($request);
        }

        // Restringido: el dueño puede pagar o exportar sus datos (nunca se "secuestran" los datos).
        if ($mode === 'restricted' && $area === 'panel' && $this->allowedWhileRestricted($request)) {
            return $next($request);
        }

        $message = $business->license_message ?: 'Servicio no disponible.';
        if ($request->expectsJson() || $request->is('api/*')) {
            return response()->json(['error' => 'LICENCIA', 'mode' => $mode, 'message' => $area === 'public' ? 'Este negocio no está recibiendo reservas en línea por el momento.' : $message], $mode === 'restricted' ? 402 : 403);
        }

        return response()->view('solvex.suspended', ['business' => $business, 'mode' => $mode, 'message' => $message, 'area' => $area], $mode === 'restricted' ? 402 : 403);
    }

    /** Adapta esto a tu app: de dónde sale la barbería actual. */
    private function resolveBusiness(Request $request): ?Business
    {
        if ($b = $request->attributes->get('business')) {
            return $b instanceof Business ? $b : null;
        }
        $param = $request->route('business');
        if ($param instanceof Business) {
            return $param;
        }
        if (is_string($param) && $param !== '') {
            return Business::query()->where('slug', $param)->first();
        }
        $user = $request->user();

        return $user && $user->business_id ? Business::query()->find($user->business_id) : null; // superadmin (business_id null): sin restricción
    }

    private function allowedWhileRestricted(Request $request): bool
    {
        $name = (string) optional($request->route())->getName();
        foreach ((array) config('solvex.restricted_allow', []) as $pattern) {
            if ($name !== '' && Str::is($pattern, $name)) {
                return true;
            }
        }

        return false;
    }
}
