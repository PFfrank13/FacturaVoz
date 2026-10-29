<?php

/*
|--------------------------------------------------------------------------
| Conexión con Solvex Hub (licencias)
|--------------------------------------------------------------------------
| Copia los valores desde el panel del Hub > Integraciones. Van en .env, nunca en Git.
*/

return [
    // Dirección del Hub, sin barra final. Ej: https://hub.solvex.pe
    'hub_url' => env('SOLVEX_HUB_URL'),

    // Id de esta instancia (ins_...). El token debe venir dirigido a ella (campo "aud").
    'instance_id' => env('SOLVEX_INSTANCE_ID'),

    // Clave de API (slxk_...) para consultar licencias. Secreta.
    'api_key' => env('SOLVEX_API_KEY'),

    // Secreto para verificar la firma de los webhooks (whsec_...). Secreto.
    'webhook_secret' => env('SOLVEX_WEBHOOK_SECRET'),

    // Llave(s) PÚBLICA(s) Ed25519 en base64 (formato libsodium que muestra el Hub). No son secretas.
    // La segunda sirve para rotar la llave sin cortar a nadie.
    'public_keys' => array_values(array_filter([
        env('SOLVEX_PUBLIC_KEY'),
        env('SOLVEX_PUBLIC_KEY_NEXT'),
    ])),

    // Columna de businesses que coincide con el "identificador del negocio" de la licencia en el Hub.
    'tenant_column' => env('SOLVEX_TENANT_COLUMN', 'slug'),

    // Rutas (por nombre) que el dueño puede usar aunque el servicio esté suspendido: pagar, exportar, salir.
    'restricted_allow' => ['solvex.suspended', 'logout', 'billing.*', 'export.*', 'profile.*'],

    // Margen para relojes desfasados al validar firmas y fechas (segundos).
    'clock_skew' => 120,

    // Ventana anti-repetición de webhooks (segundos).
    'webhook_tolerance' => 300,

    // Si el Hub no responde y el token guardado venció: 'open' mantiene el último estado conocido
    // (nunca más allá del corte que el propio token anunció); 'closed' restringe de inmediato.
    'offline_mode' => env('SOLVEX_OFFLINE_MODE', 'open'),
    'offline_max_hours' => 72,

    // Desactivar SOLO en desarrollo local, nunca en producción.
    'enabled' => env('SOLVEX_ENABLED', true),
];
