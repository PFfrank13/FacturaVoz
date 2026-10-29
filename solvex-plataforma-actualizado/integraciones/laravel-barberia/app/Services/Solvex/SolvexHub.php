<?php

namespace App\Services\Solvex;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

/** Cliente HTTP para consultar Solvex Hub (respaldo de los webhooks). */
final class SolvexHub
{
    private static function client()
    {
        return Http::baseUrl(rtrim((string) config('solvex.hub_url'), '/'))
            ->withToken((string) config('solvex.api_key'))
            ->acceptJson()->timeout(15)->retry(2, 500, throw: false);
    }

    /** Trae y aplica el token de TODAS las barberías de esta instancia. Devuelve cuántas se actualizaron. */
    public static function syncAll(): int
    {
        $res = self::client()->get('/v1/instance/licenses');
        if (! $res->successful()) {
            Log::error('Solvex: no se pudo sincronizar licencias', ['status' => $res->status()]);

            return -1;
        }
        $n = 0;
        foreach ((array) $res->json('licenses', []) as $item) {
            try {
                if (LicenseState::applyToken((string) ($item['token'] ?? ''))) {
                    $n++;
                }
            } catch (Throwable $e) {
                Log::error('Solvex: token rechazado', ['tenant' => $item['tenant_ref'] ?? null, 'error' => $e->getMessage()]);
            }
        }

        return $n;
    }

    /** Trae y aplica el token de una barbería (por ejemplo, al iniciar sesión). */
    public static function refresh(string $tenant): bool
    {
        $res = self::client()->get('/v1/instance/licenses/'.rawurlencode($tenant));
        if (! $res->successful()) {
            return false;
        }
        try {
            return (bool) LicenseState::applyToken((string) $res->json('token'));
        } catch (Throwable $e) {
            Log::error('Solvex: token rechazado', ['tenant' => $tenant, 'error' => $e->getMessage()]);

            return false;
        }
    }

    public static function heartbeat(int $tenants): void
    {
        try {
            self::client()->post('/v1/instance/heartbeat', ['version' => config('app.version', '1.0.0'), 'tenants' => $tenants]);
        } catch (Throwable) {
            // no es crítico
        }
    }
}
