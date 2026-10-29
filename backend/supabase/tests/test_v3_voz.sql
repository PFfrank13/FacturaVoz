\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
insert into auth.users(id,email) values ('55555555-5555-5555-5555-555555555555','otra@b.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.voice_quota(:'org') as quota_inicio;
select public.consume_tts(:'org', 1000, 0) ->> 'ok' as tts_1000;
select public.consume_tts(:'org', 600, 0) ->> 'reason' as tts_pasa_limite;
select public.consume_tts(:'org', 400, 1200) ->> 'reason' as tts_tope_global;
select public.voice_quota(:'org') as quota_despues;
select count(*) filter (where (public.consume_lookup(:'org') ->> 'ok')::boolean) as lookups_ok from generate_series(1, 45);
select public.lookup_quota(:'org') as lookup_quota;
select set_config('request.jwt.claim.sub','55555555-5555-5555-5555-555555555555',false);
select set_config('x.org', :'org', false);
do $$ begin perform public.consume_tts(current_setting('x.org')::uuid, 10, 0); raise notice 'MAL'; exception when others then raise notice 'OK otra empresa bloqueada: %', sqlerrm; end $$;
select count(*) as otra_ve_uso from public.tts_usage;
reset role;
