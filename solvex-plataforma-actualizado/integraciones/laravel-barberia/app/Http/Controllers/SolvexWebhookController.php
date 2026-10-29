<?php

namespace App\Http\Controllers;

use App\Services\Solvex\LicenseState;
use App\Services\Solvex\LicenseToken;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Recibe los avisos de Solvex Hub (corte, reactivación, cambios de plan) al instante.
 * Doble verificación: firma HMAC del cuerpo + firma Ed25519 del token que viene adentro.
 */
class SolvexWebhookController extends Controller
{
    public function __invoke(Request $request)
    {
        $body = $request->getContent();
        $ok = LicenseToken::webhookSignatureValid(
            (string) config('solvex.webhook_secret'),
            (string) $request->header('Solvex-Timestamp'),
            $body,
            (string) $request->header('Solvex-Signature'),
            (int) config('solvex.webhook_tolerance', 300),
        );
        if (! $ok) {
            Log::warning('Solvex: webhook con firma inválida', ['ip' => $request->ip()]);

            return response()->json(['error' => 'firma'], 401);
        }

        $event = json_decode($body, true) ?: [];
        $id = (string) ($event['id'] ?? '');
        // Idempotencia: el mismo aviso no se procesa dos veces (el Hub reintenta si no respondemos 2xx).
        if ($id === '' || ! Cache::add('solvex:evt:'.$id, 1, now()->addDays(2))) {
            return response()->json(['ok' => true, 'duplicado' => true]);
        }

        if (($event['type'] ?? '') === 'ping') {
            return response()->json(['ok' => true, 'pong' => true]);
        }

        try {
            $token = (string) data_get($event, 'data.token', '');
            if ($token !== '') {
                LicenseState::applyToken($token);
            }
        } catch (Throwable $e) {
            Cache::forget('solvex:evt:'.$id); // permitir el reintento
            Log::error('Solvex: no se pudo aplicar el aviso', ['id' => $id, 'error' => $e->getMessage()]);

            return response()->json(['error' => 'token'], 422);
        }

        return response()->json(['ok' => true]);
    }
}
