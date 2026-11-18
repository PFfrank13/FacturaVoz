#!/usr/bin/env bash
# Prueba de ACTUALIZACIÓN desde el estado real de producción (leído el 2026-11-17), en bases desechables:
#   base = migraciones que producción ya tiene (hasta 20261205) + datos sintéticos equivalentes + las 2 migraciones
#          locales tal como se aplicaron + la deriva de org_mode encontrada en producción.
# Escenarios:
#   1) Camino feliz: 20261206–20261208 → FASE A (sin corte) → reconciliación verificada → FASE B (estricta).
#   2) Protección: FASE A sin reconciliar → FASE B se NIEGA y no cambia nada (la empresa sigue operando).
#   3) Rollback: después del camino feliz, el script de rollback deja la licencia EXACTAMENTE como estaba.
set -u
cd "$(dirname "$0")/../.."
P="psql -q -v ON_ERROR_STOP=1"
NEW='*2026120[6-9]_*|*202612[1-9][0-9]_*'

replica() { # $1 = nombre de la base
  psql -q -c "drop database if exists $1" -c "create database $1" >/dev/null
  $P -d "$1" -f tests/local/00_shim_supabase.sql >/dev/null
  $P -d "$1" -f schema.sql >/dev/null 2>&1
  for f in $(ls migrations/*.sql | sort); do
    case "$f" in *2026120[6-9]_*|*202612[1-9][0-9]_*) continue;; esac
    $P -d "$1" -f "$f" >/dev/null 2>/tmp/fv_up.err || { echo "FALLA (base) $f"; tail -3 /tmp/fv_up.err; exit 1; }
  done
  $P -d "$1" -f tests/upgrade/prod_drift_org_mode.sql >/dev/null
  $P -d "$1" -f tests/upgrade/prod_replica_data.sql >/dev/null
  $P -d "$1" -f tests/upgrade/legacy_20261108223032_isolated_bodega_local_plan.sql >/dev/null
  $P -d "$1" -f tests/upgrade/legacy_20261108223858_remove_trial_banner.sql >/dev/null
}
apply() { # $1 = base, $2 = patrón de archivo
  for f in $(ls migrations/*.sql | sort); do
    case "$f" in $2) $P -d "$1" -f "$f" >/dev/null 2>/tmp/fv_up.err || { echo "FALLA $f"; tail -3 /tmp/fv_up.err; return 1; };; esac
  done
}
state() { psql -d "$1" -Atc "select md5(row(source,license_code,plan,status,mode,features,message,pay_url,period_end,grace_end,cut_at,auto_cut,token,token_iat,token_exp)::text)||' modo='||private.org_mode(org_id) from public.org_licenses"; }

# 1) Camino feliz
replica fv_rep
echo "réplica antes: $(psql -d fv_rep -Atc "select source||' '||plan||' '||status||' modo='||private.org_mode(org_id)||' period_end='||coalesce(period_end::text,'null') from public.org_licenses")"
apply fv_rep '*2026120[678]_*' || exit 1
apply fv_rep '*20261209_v34a_*' || exit 1
$P -d fv_rep -f tests/upgrade/check_fase_a.sql >/tmp/fv_a.out 2>&1 || { echo "FALLA fase A"; grep -m3 -E "FALLO|ERROR" /tmp/fv_a.out; exit 1; }
echo "PASA  FASE A sin corte + reconciliación verificada ($(grep -c 'ok:' /tmp/fv_a.out) comprobaciones)"
apply fv_rep '*20261210_v34b_*' || exit 1
apply fv_rep '*20261211_v35_bodega_stock_*' || exit 1
$P -d fv_rep -f tests/upgrade/check_fase_b.sql >/tmp/fv_b.out 2>&1 || { echo "FALLA fase B"; grep -m3 -E "FALLO|ERROR" /tmp/fv_b.out; exit 1; }
echo "PASA  FASE B estricta: renovación, suspensión, reactivación ($(grep -c 'ok:' /tmp/fv_b.out) comprobaciones)"

# 2) Protección: sin reconciliar, la FASE B no se aplica y nada cambia
replica fv_guard
apply fv_guard '*2026120[678]_*' || exit 1
apply fv_guard '*20261209_v34a_*' || exit 1
before=$(state fv_guard)
if $P -d fv_guard -f migrations/20261210_v34b_licencias_solo_hub.sql >/tmp/fv_g.out 2>&1; then
  echo "FALLA protección: la FASE B se aplicó con la empresa sin reconciliar"; exit 1
fi
after=$(state fv_guard)
grep -q "FASE B detenida" /tmp/fv_g.out && [ "$before" = "$after" ] && [ "${after##* }" = "modo=full" ] \
  && echo "PASA  FASE B se niega sin reconciliar y la empresa sigue operando ($after)" \
  || { echo "FALLA protección: antes=$before después=$after"; cat /tmp/fv_g.out | tail -3; exit 1; }

# 3) Rollback verificable sobre el camino feliz completo
replica fv_rb
before=$(state fv_rb)
apply fv_rb '*2026120[678]_*' && apply fv_rb '*20261209_v34a_*' || exit 1
$P -d fv_rb -f tests/upgrade/check_fase_a.sql >/dev/null 2>&1 || { echo "FALLA preparando rollback"; exit 1; }
apply fv_rb '*20261210_v34b_*' || exit 1
apply fv_rb '*20261211_v35_bodega_stock_*' || exit 1
$P -d fv_rb -f rollback/20261209_v34_rollback.sql >/dev/null || { echo "FALLA rollback"; exit 1; }
after=$(state fv_rb)
[ "$before" = "$after" ] && echo "PASA  rollback restaura el estado exacto ($after)" || { echo "FALLA rollback: antes=$before después=$after"; exit 1; }
