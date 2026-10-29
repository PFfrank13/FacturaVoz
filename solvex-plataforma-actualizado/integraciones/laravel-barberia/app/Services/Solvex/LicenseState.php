<?php

namespace App\Services\Solvex;

use App\Enums\BusinessStatus;
use App\Models\Business;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Aplica a una barbería el estado que llega en un token de Solvex Hub, y decide el modo efectivo
 * (incluso sin conexión: si el token anunció un corte y ya pasó, se restringe sin esperar al Hub).
 */
final class LicenseState
{
    /** Verifica un token y lo aplica a la barbería que corresponde. Devuelve la barbería o null. */
    public static function applyToken(string $token): ?Business
    {
        $p = LicenseToken::verify($token, config('solvex.public_keys'), config('solvex.instance_id'), (int) config('solvex.clock_skew', 120));

        $tenant = (string) ($p['tenant'] ?? '');
        if ($tenant === '') {
            throw new RuntimeException('El token no indica el negocio.');
        }

        return DB::transaction(function () use ($p, $token, $tenant) {
            /** @var Business|null $b */
            $b = Business::query()->withTrashed()->where(config('solvex.tenant_column', 'slug'), $tenant)->lockForUpdate()->first();
            if (! $b) {
                Log::warning('Solvex: licencia para un negocio que no existe aquí', ['tenant' => $tenant, 'lic' => $p['lic'] ?? null]);

                return null;
            }
            // Un aviso más viejo que el último aplicado no puede "deshacer" un cambio (llegaron desordenados).
            if ($b->license_token_iat && (int) $p['iat'] < (int) $b->license_token_iat) {
                return $b;
            }

            $mode = (string) ($p['mode'] ?? 'blocked');
            $b->forceFill([
                'license_code' => $p['lic'] ?? null,
                'license_status' => $p['status'] ?? null,
                'license_mode' => $mode,
                'license_period_end' => isset($p['period_end']) ? Carbon::parse($p['period_end']) : null,
                // Fecha en que el propio token anuncia el corte (sirve para cortar aunque el Hub no responda).
                'license_cut_at' => ! empty($p['auto_cut']) && ($p['cut_at'] ?? $p['grace_end'] ?? null) ? Carbon::parse($p['cut_at'] ?? $p['grace_end']) : null,
                'license_message' => $p['message'] ?? null,
                'license_pay_url' => $p['pay_url'] ?? null,
                'license_features' => $p['features'] ?? [],
                'license_token' => $token,
                'license_token_iat' => (int) $p['iat'],
                'license_token_exp' => Carbon::createFromTimestamp((int) $p['exp']),
                'license_checked_at' => now(),
            ]);

            // Reflejo en el estado propio de la barbería (columna status del lote 1).
            [$status, $reason] = match ($p['status'] ?? '') {
                'prueba' => [BusinessStatus::Trial, null],
                'activa', 'gracia' => [BusinessStatus::Active, null],
                'cancelada' => [BusinessStatus::Cancelled, 'Licencia dada de baja en Solvex'],
                'pendiente' => [BusinessStatus::Suspended, 'Licencia aún no activada'],
                default => [BusinessStatus::Suspended, ($p['suspension'] ?? null) === 'manual' ? 'Suspensión manual de Solvex' : 'Falta de pago'],
            };
            $was = $b->status;
            $b->status = $status;
            if ($status === BusinessStatus::Suspended && $was !== BusinessStatus::Suspended) {
                $b->suspended_at = now();
            }
            if ($status !== BusinessStatus::Suspended) {
                $b->suspended_at = null;
            }
            $b->suspension_reason = $reason;
            $b->save();

            return $b;
        });
    }

    /**
     * Modo efectivo AHORA. Aunque el Hub esté caído:
     *  - si el token anunciaba un corte y ya pasó → restricted;
     *  - si el token venció hace demasiado (offline_max_hours) → restricted (o de inmediato en modo "closed").
     */
    public static function effectiveMode(Business $b): string
    {
        if (! config('solvex.enabled', true)) {
            return 'full';
        }
        $mode = $b->license_mode ?: 'blocked';
        if (in_array($mode, ['full', 'warning'], true) && $b->license_cut_at && now()->greaterThan($b->license_cut_at)) {
            return 'restricted';
        }
        if ($b->license_token_exp && now()->greaterThan($b->license_token_exp)) {
            $limit = config('solvex.offline_mode') === 'closed' ? 0 : (int) config('solvex.offline_max_hours', 72);
            if (now()->greaterThan($b->license_token_exp->copy()->addHours($limit))) {
                return 'restricted';
            }
        }

        return $mode;
    }

    /** Límite de una función del plan. -1 = ilimitado; null = no definido. */
    public static function feature(Business $b, string $key): int|bool|null
    {
        $f = $b->license_features ?? [];
        if (is_string($f)) {
            $f = json_decode($f, true) ?: [];
        }

        return $f[$key] ?? null;
    }
}
