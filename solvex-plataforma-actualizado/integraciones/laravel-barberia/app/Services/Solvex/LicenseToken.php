<?php

namespace App\Services\Solvex;

use RuntimeException;

/**
 * Verifica tokens de licencia emitidos por Solvex Hub (JWS compacto firmado con Ed25519).
 *
 * Usa libsodium, que viene incluido en PHP 7.2+ (no requiere paquetes de Composer).
 * Nunca confíes en el contenido de un token sin pasar por verify().
 */
final class LicenseToken
{
    /**
     * @param  string[]  $publicKeysB64  llaves públicas (32 bytes en base64)
     * @return array<string, mixed> contenido verificado
     *
     * @throws RuntimeException si la firma, el emisor, el destinatario o las fechas no son válidas
     */
    public static function verify(string $token, array $publicKeysB64, ?string $audience = null, int $clockSkew = 120, ?int $now = null): array
    {
        $now ??= time();
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            throw new RuntimeException('Token mal formado.');
        }
        [$h, $p, $s] = $parts;
        $header = json_decode(self::b64url($h), true);
        $payload = json_decode(self::b64url($p), true);
        $sig = self::b64url($s);

        if (! is_array($header) || ! is_array($payload)) {
            throw new RuntimeException('Token ilegible.');
        }
        // Solo EdDSA: se rechaza cualquier otro algoritmo (incluido "none").
        if (($header['alg'] ?? null) !== 'EdDSA' || ($header['typ'] ?? null) !== 'slx-license+jwt') {
            throw new RuntimeException('Algoritmo o tipo no permitido.');
        }
        if (strlen($sig) !== SODIUM_CRYPTO_SIGN_BYTES) {
            throw new RuntimeException('Firma inválida.');
        }

        $ok = false;
        foreach ($publicKeysB64 as $keyB64) {
            $key = base64_decode((string) $keyB64, true);
            if ($key !== false && strlen($key) === SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES
                && sodium_crypto_sign_verify_detached($sig, $h.'.'.$p, $key)) {
                $ok = true;
                break;
            }
        }
        if (! $ok) {
            throw new RuntimeException('Firma inválida.');
        }
        if (($payload['iss'] ?? null) !== 'solvex-hub') {
            throw new RuntimeException('Emisor inválido.');
        }
        if ($audience !== null && ($payload['aud'] ?? null) !== $audience) {
            throw new RuntimeException('El token no es para esta instancia.');
        }
        if (isset($payload['nbf']) && $now + $clockSkew < (int) $payload['nbf']) {
            throw new RuntimeException('Token aún no válido.');
        }
        if (! isset($payload['exp']) || $now - $clockSkew > (int) $payload['exp']) {
            throw new RuntimeException('Token vencido.');
        }

        return $payload;
    }

    /** Firma HMAC de los webhooks: "v1=" + hex(HMAC-SHA256(secreto, timestamp + "." + cuerpo)). */
    public static function webhookSignatureValid(string $secret, string $timestamp, string $body, string $header, int $tolerance = 300, ?int $now = null): bool
    {
        $now ??= time();
        if (! ctype_digit($timestamp) || abs($now - (int) $timestamp) > $tolerance) {
            return false; // fuera de la ventana: posible repetición de un aviso viejo
        }
        $expected = 'v1='.hash_hmac('sha256', $timestamp.'.'.$body, $secret);

        return hash_equals($expected, $header);
    }

    private static function b64url(string $s): string
    {
        $r = base64_decode(strtr($s, '-_', '+/').str_repeat('=', (4 - strlen($s) % 4) % 4), true);
        if ($r === false) {
            throw new RuntimeException('Base64 inválido.');
        }

        return $r;
    }
}
