\set ON_ERROR_STOP 1
-- G: auditoría de RLS entre empresas. Siembra una fila por tabla en la empresa A (como postgres) y verifica que el
-- usuario de la empresa B no ve NINGUNA fila de A en NINGUNA tabla pública con org_id.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','a@a.pe'),('55555555-5555-5555-5555-555555555555','b@b.pe') on conflict do nothing;
select org_id as org_a from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select invoice_id as inv from public.create_invoice('Cliente A', null, 18, 'PEN', null, null, '[{"description":"X","quantity":1,"unit_price":10}]'::jsonb, :'org_a') \gset
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org_a','Paciente A') returning id as ca \gset
insert into public.private_notes(org_id, client_id, body) values (:'org_a', :'ca', 'dato sensible');
insert into public.service_packages(org_id, client_id, name, sessions_total) values (:'org_a', :'ca', 'p', 2);
insert into public.service_reminders(org_id, client_id, due_on, title) values (:'org_a', :'ca', current_date, 't');
insert into public.expenses(org_id,user_id,category,description,total) values (:'org_a',auth.uid(),'otros','Luz',100);
insert into public.jobs(org_id,client_id,title) values (:'org_a',:'ca','Obra');
select public.consume_tts(:'org_a', 10, 0) is not null as tts;
select public.consume_lookup(:'org_a') is not null as lookup;
select public.wb_import_begin(:'org_a', 'x.xlsx', '{}'::jsonb) is not null as wb;
select set_config('x.org_a', :'org_a', false);
-- B mira
select set_config('request.jwt.claim.sub','55555555-5555-5555-5555-555555555555',false);
do $$
declare t text; n bigint; leaks text := ''; checked int := 0;
begin
  for t in select c.table_name from information_schema.columns c join information_schema.tables tb using (table_schema, table_name)
           where c.table_schema = 'public' and c.column_name = 'org_id' and tb.table_type = 'BASE TABLE' order by 1 loop
    begin
      execute format('select count(*) from public.%I where org_id = %L', t, current_setting('x.org_a')) into n;
      checked := checked + 1;
      if n > 0 then leaks := leaks || t || '(' || n || ') '; end if;
    exception when insufficient_privilege then checked := checked + 1; -- sin permiso de lectura: también es seguro
    end;
  end loop;
  if leaks <> '' then raise exception 'FUGA entre empresas en: %', leaks; end if;
  raise notice 'OK: % tablas con org_id revisadas, 0 filas de otra empresa visibles', checked;
end $$;
reset role;
