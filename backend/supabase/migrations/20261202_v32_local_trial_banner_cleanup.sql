-- v3.4: RETIRADO del recorrido comercial (sin efecto). Antes quitaba el vencimiento de la licencia local de la
-- única empresa de prueba (period_end/grace_end/cut_at = null, sin corte automático). En producción ya se aplicó como
-- 20261108223858 "bodega_local_remove_stale_hub_trial_banner_20261108"; 20261209_v34_licencias_solo_hub.sql respalda
-- y revierte ese estado hacia una licencia del Hub verificada.
select 1;
