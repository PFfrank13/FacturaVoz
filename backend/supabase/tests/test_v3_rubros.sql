\set ON_ERROR_STOP 1
-- B: historial privado, paquetes y recordatorios por rol y entre empresas.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.invite_member(:'org','tecnico@a.pe','tecnico',false,'Pedro');
select public.invite_member(:'org','caja@a.pe','cajero',false,'Lucía');
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org','Paciente A') returning id as ca \gset
reset role;
insert into auth.users(id,email) values ('33333333-3333-3333-3333-333333333333','tecnico@a.pe'),('44444444-4444-4444-4444-444444444444','caja@a.pe'),('55555555-5555-5555-5555-555555555555','otra@b.pe');
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into public.private_notes(org_id, client_id, body) values (:'org', :'ca', 'Alergia a la penicilina');
insert into public.service_packages(org_id, client_id, name, sessions_total) values (:'org', :'ca', '4 sesiones de terapia', 2) returning id as pkg \gset
select public.use_package_session(:'pkg') as quedan_1;
select public.use_package_session(:'pkg') as quedan_0;
select set_config('x.pkg', :'pkg', false);
do $$ begin perform public.use_package_session(current_setting('x.pkg')::uuid); exception when others then raise notice 'OK sin sesiones: %', sqlerrm; end $$;
insert into public.service_reminders(org_id, client_id, due_on, title) values (:'org', :'ca', current_date + 30, 'Control mensual');
-- cajero: no ve notas privadas del dueño, no puede regalar sesiones
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',false);
select count(*) as cajero_ve_notas from public.private_notes;
update public.service_packages set name = 'X' where id = :'pkg';
do $$ begin execute 'update public.service_packages set sessions_used = 0'; raise notice 'MAL: pudo devolver sesiones'; exception when others then raise notice 'OK no puede devolver sesiones: %', sqlerrm; end $$;
insert into public.private_notes(org_id, client_id, body) values (:'org', :'ca', 'Nota de la cajera');
select count(*) as cajero_ve_su_nota from public.private_notes;
-- técnico: no puede escribir historial privado
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',false);
do $$ begin insert into public.private_notes(org_id, client_id, body) select org_id, id, 'x' from public.clients limit 1; raise notice 'técnico insertó (sin clientes visibles = 0 filas)'; exception when others then raise notice 'OK técnico bloqueado: %', sqlerrm; end $$;
-- dueño ve todas
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select count(*) as dueno_ve_notas from public.private_notes;
-- otra empresa no ve nada
select set_config('request.jwt.claim.sub','55555555-5555-5555-5555-555555555555',false);
select (select count(*) from public.private_notes) + (select count(*) from public.service_packages) + (select count(*) from public.service_reminders) as otra_empresa_ve;
reset role;
