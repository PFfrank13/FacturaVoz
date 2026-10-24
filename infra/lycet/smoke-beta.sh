#!/usr/bin/env bash
# Prueba de punta a punta contra SUNAT BETA (empresa de pruebas 20000000001). No toca datos reales.
# Uso:  LYCET_URL=https://facturacion.midominio.com LYCET_API_KEY=... ./smoke-beta.sh
set -euo pipefail
: "${LYCET_URL:?}" "${LYCET_API_KEY:?}"
cd "$(dirname "$0")"
AUTH=(-u "lycet:$LYCET_API_KEY")
CERT=$(mktemp); trap 'rm -f "$CERT"' EXIT
curl -fsSL https://raw.githubusercontent.com/giansalex/lycet/master/tests/Resources/cert.pem -o "$CERT"
B64=$(base64 -w0 "$CERT")

echo "1) Registrar empresa de pruebas..."
curl -fsS "${AUTH[@]}" -X PUT "$LYCET_URL/api/v1/configuration/company/20000000001" -H 'Content-Type: application/json' \
  -d "{\"SOL_USER\":\"20000000001MODDATOS\",\"SOL_PASS\":\"moddatos\",\"certificate\":\"$B64\",\"FE_URL\":\"https://e-beta.sunat.gob.pe/ol-ti-itcpfegem-beta/billService\"}"
echo

echo "2) Enviar factura de prueba a SUNAT beta..."
NUM=$(( $(date +%s) % 99999999 + 1 ))
NOW=$(TZ=America/Lima date +%Y-%m-%dT%H:%M:%S-05:00)
sed -e "s/__NUM__/$NUM/" -e "s/__NOW__/$NOW/" sample-factura-beta.json > /tmp/factura-beta.json
curl -sS "${AUTH[@]}" -X POST "$LYCET_URL/api/v1/invoice/send" -H 'Content-Type: application/json' -d @/tmp/factura-beta.json \
  | python3 -c "import sys,json; r=json.load(sys.stdin); s=r.get('sunatResponse',{}); print('hash:',r.get('hash')); print('success:',s.get('success')); print('CDR:',s.get('cdrResponse')); print('error:',s.get('error'))"
echo
echo "Esperado: success True y CDR code '0' (aceptada)."
