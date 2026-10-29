<?php

/*
 * Pruebas de la integración con Solvex Hub (Pest).
 * Ejecuta:  sail artisan test --filter=Solvex
 * No necesitan el Hub: firman tokens con una llave de prueba generada aquí.
 */

use App\Enums\BusinessStatus;
use App\Models\Business;
use App\Services\Solvex\LicenseState;

function solvexKeys(): array
{
    static $kp = null;
    $kp ??= sodium_crypto_sign_keypair();

    return [sodium_crypto_sign_secretkey($kp), base64_encode(sodium_crypto_sign_publickey($kp))];
}

function b64u(string $s): string
{
    return rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
}

function solvexToken(array $claims): string
{
    [$secret] = solvexKeys();
    $now = time();
    $payload = array_merge(['iss' => 'solvex-hub', 'aud' => 'ins_prueba', 'iat' => $now, 'nbf' => $now - 60, 'exp' => $now + 3600, 'lic' => 'LIC-00001', 'tenant' => 'don-corte', 'status' => 'activa', 'mode' => 'full', 'auto_cut' => true, 'features' => ['max_branches' => 2]], $claims);
    $input = b64u(json_encode(['alg' => 'EdDSA', 'typ' => 'slx-license+jwt', 'kid' => 'test'])).'.'.b64u(json_encode($payload));

    return $input.'.'.b64u(sodium_crypto_sign_detached($input, $secret));
}

function postWebhook($test, array $event, ?string $secret = null, ?int $ts = null)
{
    $body = json_encode($event);
    $ts ??= time();
    $sig = 'v1='.hash_hmac('sha256', $ts.'.'.$body, $secret ?? 'whsec_prueba');

    return $test->call('POST', '/api/solvex/webhook', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_SOLVEX_TIMESTAMP' => (string) $ts, 'HTTP_SOLVEX_SIGNATURE' => $sig], $body);
}

beforeEach(function () {
    config(['solvex.public_keys' => [solvexKeys()[1]], 'solvex.instance_id' => 'ins_prueba', 'solvex.webhook_secret' => 'whsec_prueba', 'solvex.tenant_column' => 'slug', 'solvex.enabled' => true]);
    $this->business = Business::query()->create(['name' => 'Don Corte', 'slug' => 'don-corte']);
});

it('un webhook firmado suspende y luego reactiva la barbería', function () {
    postWebhook($this, ['id' => 'evt_1', 'type' => 'license.updated', 'data' => ['token' => solvexToken(['status' => 'suspendida', 'mode' => 'restricted', 'suspension' => 'auto'])]])->assertOk();
    $b = $this->business->fresh();
    expect($b->status)->toBe(BusinessStatus::Suspended)
        ->and($b->license_mode)->toBe('restricted')
        ->and(LicenseState::effectiveMode($b))->toBe('restricted');

    postWebhook($this, ['id' => 'evt_2', 'type' => 'license.updated', 'data' => ['token' => solvexToken(['status' => 'activa', 'mode' => 'full', 'iat' => time() + 1])]])->assertOk();
    expect($this->business->fresh()->status)->toBe(BusinessStatus::Active);
});

it('rechaza webhooks con firma inválida o viejos (anti-repetición)', function () {
    postWebhook($this, ['id' => 'evt_3', 'data' => ['token' => solvexToken([])]], 'otro_secreto')->assertStatus(401);
    postWebhook($this, ['id' => 'evt_4', 'data' => ['token' => solvexToken([])]], null, time() - 3600)->assertStatus(401);
});

it('rechaza tokens falsificados o dirigidos a otra instancia', function () {
    $falso = solvexToken(['status' => 'activa']);
    $falso = substr($falso, 0, -6).'AAAAAA';
    postWebhook($this, ['id' => 'evt_5', 'data' => ['token' => $falso]])->assertStatus(422);
    postWebhook($this, ['id' => 'evt_6', 'data' => ['token' => solvexToken(['aud' => 'ins_otra'])]])->assertStatus(422);
});

it('un aviso más viejo no deshace uno más nuevo', function () {
    LicenseState::applyToken(solvexToken(['status' => 'activa', 'mode' => 'full', 'iat' => time()]));
    LicenseState::applyToken(solvexToken(['status' => 'suspendida', 'mode' => 'restricted', 'iat' => time() - 100]));
    expect($this->business->fresh()->license_mode)->toBe('full');
});

it('corta sin conexión cuando pasa la fecha de corte anunciada en el token', function () {
    LicenseState::applyToken(solvexToken(['status' => 'gracia', 'mode' => 'warning', 'cut_at' => now()->subMinute()->toIso8601String()]));
    expect(LicenseState::effectiveMode($this->business->fresh()))->toBe('restricted');
});

it('el mismo aviso no se procesa dos veces', function () {
    $ev = ['id' => 'evt_7', 'data' => ['token' => solvexToken([])]];
    postWebhook($this, $ev)->assertOk();
    postWebhook($this, $ev)->assertOk()->assertJson(['duplicado' => true]);
});
