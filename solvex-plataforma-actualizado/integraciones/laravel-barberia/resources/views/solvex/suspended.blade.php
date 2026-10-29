{{-- Pantalla cuando la licencia de la barbería no permite operar. --}}
<!doctype html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>{{ $area === 'public' ? 'No disponible' : 'Servicio suspendido' }} · {{ $business->name }}</title>
    <style>
        body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;background:#F2F5F4;color:#0B1A2C;display:grid;place-items:center;min-height:100vh;padding:16px}
        .c{max-width:460px;background:#fff;border:1px solid #DCE4E0;border-radius:20px;padding:28px}
        h1{font-size:24px;margin:0 0 8px}p{color:#5A6A77;line-height:1.5}
        a.b{display:inline-block;background:#0D8460;color:#fff;padding:12px 18px;border-radius:12px;text-decoration:none;font-weight:600;margin:8px 8px 0 0}
        a.l{color:#0D8460;font-weight:600}
    </style>
</head>
<body>
<main class="c">
    @if ($area === 'public')
        <h1>{{ $business->name }}</h1>
        <p>Por el momento no estamos recibiendo reservas en línea. Si ya tienes una cita, sigue siendo válida: revisa el enlace que te enviamos o comunícate con el local.</p>
    @elseif ($mode === 'blocked')
        <h1>Tu sistema aún no está activado</h1>
        <p>{{ $message }}</p>
    @else
        <h1>Servicio suspendido</h1>
        <p>{{ $message }}</p>
        <p>Tus datos están seguros y se conservan. Al pagar, el sistema se reactiva automáticamente en segundos.</p>
        @if ($business->license_pay_url)
            <a class="b" href="{{ $business->license_pay_url }}" rel="noopener noreferrer">Pagar ahora</a>
        @endif
        @if (Route::has('export.index'))
            <a class="l" href="{{ route('export.index') }}">Exportar mis datos</a>
        @endif
    @endif
</main>
</body>
</html>
