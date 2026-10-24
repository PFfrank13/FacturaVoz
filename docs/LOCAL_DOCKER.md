# Probar la facturación SUNAT desde tu PC (Docker + túnel)

Para pruebas en **SUNAT beta**. Tu PC debe estar encendida y la URL del túnel cambia cada vez que lo reinicias.
No lo uses con clientes reales: para eso necesitas un servidor permanente (ver `infra/lycet/INSTALACION.md`).

Requisitos (Windows): Docker Desktop (con WSL2) y Git para Windows (trae Git Bash). Todo lo siguiente en **Git Bash**.

1. `cd infra/lycet` y `./bootstrap.sh local` → guarda el **LYCET_API_KEY** que imprime (no se vuelve a mostrar).
2. `docker compose up -d --build` (la primera vez tarda varios minutos). Prueba: `curl http://localhost:8080/health` → `ok`.
3. En otra terminal, el túnel HTTPS gratuito:
   `docker run --rm cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://host.docker.internal:8080`
   Copia la URL `https://xxxx.trycloudflare.com` que muestra: es tu **LYCET_URL**. Deja esa terminal abierta.
4. Prueba contra SUNAT beta (debe terminar con `success: True` y CDR code `'0'`):
   ```
   MSYS_NO_PATHCONV=1 docker run --rm -it -v "$(pwd -W):/w" -w /w \
     -e LYCET_URL=https://xxxx.trycloudflare.com -e LYCET_API_KEY=TU_CLAVE \
     debian:bookworm-slim bash -c "apt-get update -qq && apt-get install -y -qq curl python3 ca-certificates >/dev/null && bash smoke-beta.sh"
   ```
5. Pon `LYCET_URL` y `LYCET_API_KEY` en Vercel (Settings → Environment Variables, Sensitive) y redespliega.
   Cada vez que reinicies el túnel, actualiza `LYCET_URL` y redespliega.

## Datos de prueba en la app (SUNAT beta)
- Datos del negocio: RUC `20000000001`, ubigeo `150101`, LIMA/LIMA/LIMA, una dirección cualquiera, series `F001` y `B001`.
- Ajustes → Facturación electrónica: entorno **Beta**, usuario SOL `MODDATOS`, clave `moddatos`,
  certificado: descarga https://raw.githubusercontent.com/giansalex/lycet/master/tests/Resources/cert.pem, formato PEM, sin clave.
- Emite una factura (cliente con RUC válido), una boleta y una nota de crédito.
