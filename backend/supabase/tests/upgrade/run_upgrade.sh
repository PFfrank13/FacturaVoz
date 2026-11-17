#!/usr/bin/env bash
# Prueba de ACTUALIZACIÓN desde el estado real de producción (2026-11-17), en una base desechable:
#  1) migraciones hasta 20261205 (lo que producción ya tiene)
#  2) datos sintéticos equivalentes + las 2 migraciones locales tal como se aplicaron en producción + la deriva de org_mode
#  3) migraciones nuevas 20261206–20261209 y verificación de la transición local → Hub.
set -u
cd "$(dirname "$0")/../.."
P="psql -q -v ON_ERROR_STOP=1"
psql -q -c "drop database if exists fv_rep" -c "create database fv_rep" >/dev/null
$P -d fv_rep -f tests/local/00_shim_supabase.sql >/dev/null
$P -d fv_rep -f schema.sql >/dev/null 2>&1
for f in $(ls migrations/*.sql | sort); do
  case "$f" in *2026120[6-9]_*|*202612[1-9]*) continue;; esac
  $P -d fv_rep -f "$f" >/dev/null 2>/tmp/fv_up.err || { echo "FALLA (base) $f"; tail -3 /tmp/fv_up.err; exit 1; }
done
$P -d fv_rep -f tests/upgrade/prod_drift_org_mode.sql >/dev/null
$P -d fv_rep -f tests/upgrade/prod_replica_data.sql >/dev/null
$P -d fv_rep -f tests/upgrade/legacy_20261108223032_isolated_bodega_local_plan.sql >/dev/null
$P -d fv_rep -f tests/upgrade/legacy_20261108223858_remove_trial_banner.sql >/dev/null
echo "réplica antes: $(psql -d fv_rep -Atc "select source||' '||plan||' '||status||' modo='||private.org_mode(org_id)||' period_end='||coalesce(period_end::text,'null') from public.org_licenses")"
for f in $(ls migrations/*.sql | sort); do
  case "$f" in *2026120[6-9]_*|*202612[1-9]*) ;; *) continue;; esac
  $P -d fv_rep -f "$f" >/dev/null 2>/tmp/fv_up.err || { echo "FALLA (nueva) $f"; tail -3 /tmp/fv_up.err; exit 1; }
done
if $P -d fv_rep -f tests/upgrade/prod_replica_check.sql >/tmp/fv_up.out 2>&1; then
  echo "PASA  actualización desde producción ($(grep -c 'ok:' /tmp/fv_up.out) comprobaciones)"
else
  echo "FALLA actualización"; grep -m3 -E "FALLO|ERROR" /tmp/fv_up.out; exit 1
fi

# Rollback verificable: sobre la misma réplica ya actualizada, se vuelve al estado anterior exacto.
if [ "${1:-}" = "--rollback" ] || [ "${CHECK_ROLLBACK:-1}" = "1" ]; then
  psql -q -c "drop database if exists fv_rb" -c "create database fv_rb" >/dev/null
  $P -d fv_rb -f tests/local/00_shim_supabase.sql >/dev/null
  $P -d fv_rb -f schema.sql >/dev/null 2>&1
  for f in $(ls migrations/*.sql | sort); do
    case "$f" in *2026120[6-9]_*|*202612[1-9]*) continue;; esac
    $P -d fv_rb -f "$f" >/dev/null 2>&1
  done
  $P -d fv_rb -f tests/upgrade/prod_drift_org_mode.sql >/dev/null
  $P -d fv_rb -f tests/upgrade/prod_replica_data.sql >/dev/null
  $P -d fv_rb -f tests/upgrade/legacy_20261108223032_isolated_bodega_local_plan.sql >/dev/null
  $P -d fv_rb -f tests/upgrade/legacy_20261108223858_remove_trial_banner.sql >/dev/null
  before=$(psql -d fv_rb -Atc "select md5(row(source,license_code,plan,status,mode,features,message,pay_url,period_end,grace_end,cut_at,auto_cut,token,token_iat,token_exp)::text)||' modo='||private.org_mode(org_id) from public.org_licenses")
  for f in $(ls migrations/*.sql | sort); do
    case "$f" in *2026120[6-9]_*|*202612[1-9]*) $P -d fv_rb -f "$f" >/dev/null || exit 1;; esac
  done
  $P -d fv_rb -f rollback/20261209_v34_rollback.sql >/dev/null || { echo "FALLA rollback"; exit 1; }
  after=$(psql -d fv_rb -Atc "select md5(row(source,license_code,plan,status,mode,features,message,pay_url,period_end,grace_end,cut_at,auto_cut,token,token_iat,token_exp)::text)||' modo='||private.org_mode(org_id) from public.org_licenses")
  if [ "$before" = "$after" ]; then echo "PASA  rollback restaura el estado exacto ($after)"; else echo "FALLA rollback: antes=$before después=$after"; exit 1; fi
fi
