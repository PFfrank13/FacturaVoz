-- Arnés de prueba (solo BD local): cada empresa nueva queda con una licencia Hub EMPRESA activada (token sintético).
create or replace function public._test_hub_license() returns trigger language plpgsql security definer as $$
begin
  new.source := 'hub'; new.plan := 'EMPRESA'; new.status := 'activa'; new.mode := 'full';
  new.features := private.all_features(); new.token := 'synthetic-test-token'; new.license_code := 'TEST-' || new.org_id;
  new.auto_cut := false; new.period_end := now() + interval '30 days';
  return new;
end $$;
create trigger _test_hub_license before insert on public.org_licenses for each row execute function public._test_hub_license();
create or replace function public._test_hub_activation() returns trigger language plpgsql security definer as $$
begin insert into private.org_license_activations(org_id, license_code) values (new.org_id, new.license_code) on conflict (org_id) do nothing; return new; end $$;
create trigger _test_hub_activation after insert on public.org_licenses for each row execute function public._test_hub_activation();
create or replace function public._uuid_min(a uuid, b uuid) returns uuid language sql immutable as $$ select least(a, b) $$;
create aggregate public.min(uuid) (sfunc = public._uuid_min, stype = uuid);
