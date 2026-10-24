#!/usr/bin/env bash
# Genera .env con secretos aleatorios. Ejecutar UNA vez en el VPS: ./bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .env ]; then echo "Ya existe .env (bórralo solo si quieres rotar TODOS los secretos)."; exit 1; fi
# Modo local (PC con Docker + túnel HTTPS): ./bootstrap.sh local  -> Caddy escucha en HTTP :8080 y el túnel pone el HTTPS.
LOCAL=0
if [ "${1:-}" = "local" ]; then
  LOCAL=1; DOMAIN=":80"
else
  read -rp "Dominio apuntando a este VPS (ej. facturacion.midominio.com): " DOMAIN
  [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Dominio no válido"; exit 1; }
fi
APP_SECRET=$(openssl rand -hex 32)
TOKEN=$(openssl rand -hex 24)
API_KEY=$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-48)
HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "$API_KEY")
umask 177
cat > .env <<ENV
DOMAIN=$DOMAIN
$( [ "$LOCAL" = 1 ] && printf 'HTTP_PORT=8080\nHTTPS_PORT=8443' )
LYCET_APP_SECRET=$APP_SECRET
LYCET_TOKEN=$TOKEN
LYCET_BASIC_HASH='$HASH'
ENV
echo
echo "Listo. Guarda ESTOS dos valores en Vercel (Environment Variables, Sensitive) y no se vuelven a mostrar:"
if [ "$LOCAL" = 1 ]; then
  echo "  LYCET_URL     = la URL https://xxxx.trycloudflare.com que imprima el túnel (ver docs)"
else
  echo "  LYCET_URL     = https://$DOMAIN"
fi
echo "  LYCET_API_KEY = $API_KEY"
