#!/usr/bin/env bash
# Corre migraciones + pruebas SQL en un PostgreSQL 16 LOCAL y desechable (nunca producción).
# Uso: PGHOST=/ruta/socket PGPORT=5545 PGUSER=postgres bash backend/supabase/tests/local/run_all.sh
set -u
cd "$(dirname "$0")/../.."   # backend/supabase
P="psql -q -v ON_ERROR_STOP=1"
psql -q -c "drop database if exists fv_base" -c "create database fv_base" >/dev/null
$P -d fv_base -f tests/local/00_shim_supabase.sql >/dev/null
$P -d fv_base -f schema.sql >/dev/null 2>&1
for f in $(ls migrations/*.sql | sort); do
  $P -d fv_base -f "$f" >/dev/null 2>/tmp/fv_mig.err || { echo "MIGRACIÓN FALLA: $f"; tail -3 /tmp/fv_mig.err; exit 1; }
done
echo "migraciones: OK ($(ls migrations/*.sql | wc -l) en orden)"
fail=0
# test_lic.sql y test_v31_planes.sql son anteriores a 20261124/20261125 (activación obligatoria y Hub manda):
# sus expectativas ya no aplican; la cobertura vigente es test_hub_precedence.sql.
for t in test_fase0 test_sunat test_crm test_roles test_mod1 test_mod2 test_v3_rubros test_v3_voz test_v3_rls_audit test_v33_idempotencia test_v33_suscripcion test_v33_rls_funciones test_v34_stock test_v34_licencias test_hub_precedence; do
  psql -q -c "drop database if exists fv_t" -c "create database fv_t template fv_base" >/dev/null
  [ "$t" != test_hub_precedence ] && [ "$t" != test_v34_licencias ] && $P -d fv_t -f tests/local/01_licencia_hub_sintetica.sql >/dev/null
  if psql -q -d fv_t -v ON_ERROR_STOP=1 -f "tests/$t.sql" >/tmp/fv_$t.out 2>&1; then echo "PASA  $t"; else echo "FALLA $t"; grep -m1 ERROR /tmp/fv_$t.out; fail=1; fi
done
exit $fail
