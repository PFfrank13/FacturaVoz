#!/usr/bin/env bash
# Respaldo CIFRADO de empresas.json + certificados + claves SOL. Programa con cron (ver INSTALACION.md).
# Requiere: BACKUP_PASSPHRASE_FILE (archivo con una frase larga, permisos 600). Copia el resultado FUERA del VPS.
set -euo pipefail
cd "$(dirname "$0")"
PASS_FILE="${BACKUP_PASSPHRASE_FILE:-/root/.lycet-backup-pass}"
OUT_DIR="${BACKUP_DIR:-/var/backups/lycet}"
[ -r "$PASS_FILE" ] || { echo "Falta $PASS_FILE"; exit 1; }
mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
VOL=$(docker volume ls -q | grep -E '(^|_)lycet_data$' | head -1)
docker run --rm -v "$VOL":/data:ro -v "$OUT_DIR":/out alpine \
  tar -C /data -czf "/out/lycet-$STAMP.tgz" .
openssl enc -aes-256-cbc -pbkdf2 -salt -pass "file:$PASS_FILE" -in "$OUT_DIR/lycet-$STAMP.tgz" -out "$OUT_DIR/lycet-$STAMP.tgz.enc"
rm -f "$OUT_DIR/lycet-$STAMP.tgz"
find "$OUT_DIR" -name 'lycet-*.tgz.enc' -mtime +30 -delete
echo "Respaldo: $OUT_DIR/lycet-$STAMP.tgz.enc"
