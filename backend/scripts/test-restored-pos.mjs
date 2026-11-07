// A new, private, network-isolated clone of the verified restore for every run.
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const container='solvex-cloud-lab-20261107';
const source=process.argv[2];
if(!/^restore_\d+$/.test(source ?? '')) throw Error('Expected verified local restore');
const call=(args,input)=>spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:16*1024*1024});
const state=call(['inspect','--format','{{.HostConfig.NetworkMode}}|{{len .Mounts}}',container]);
if(state.status || state.stdout.trim()!=='none|0') throw Error('Isolation required');
const database=`retail_restore_${Date.now()}`;
const clone=call(['exec',container,'createdb','-h','/tmp','-U','postgres','-T',source,database]);
if(clone.status) throw Error('Could not clone restore');
const read=p=>readFileSync(new URL('../supabase/'+p,import.meta.url),'utf8');
const sqlArgs=['exec','-i',container,'psql','-h','/tmp','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'];
let scenario=read('tests/test_cloud_checkout.sql');
// Existing copied customers/licenses must remain byte-for-byte unchanged.
scenario=scenario.replace('features=private.all_features();',`features=private.all_features()
 where org_id in (select org_id from public.organization_members where user_id in
 ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'));`);
scenario=scenario.replace("where role='owner';",`where role='owner' and user_id in
 ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222');`);
const snapshot=`select jsonb_build_object(
 'users',(select jsonb_agg(to_jsonb(t) order by id) from auth.users t where id in(select id from protected_users)),
 'organizations',(select jsonb_agg(to_jsonb(t) order by id) from public.organizations t where id in(select id from protected_orgs)),
 'licenses',(select jsonb_agg(to_jsonb(t) order by org_id) from public.org_licenses t where org_id in(select id from protected_orgs)),
 'memberships',(select jsonb_agg(to_jsonb(t) order by org_id,user_id) from public.organization_members t where org_id in(select id from protected_orgs)),
 'invoices',(select jsonb_agg(to_jsonb(t) order by id) from public.invoices t where org_id in(select id from protected_orgs)),
 'payments',(select jsonb_agg(to_jsonb(t) order by id) from public.payments t where org_id in(select id from protected_orgs)),
 'products',(select jsonb_agg(to_jsonb(t) order by id) from public.products t where org_id in(select id from protected_orgs)),
 'storage',(select jsonb_agg(to_jsonb(t) order by id) from storage.objects t),
 'events',(select jsonb_agg(to_jsonb(t) order by id) from public.solvex_events t),
 'contracts',(select jsonb_agg(pg_get_functiondef(p.oid) order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname like '%license%')
 ) as fingerprint`;
const result=call(sqlArgs,`begin;
 create temp table protected_users as select id from auth.users;
 create temp table protected_orgs as select id from public.organizations;
 create temp table before_pos as ${snapshot};
 ${read('migrations/20261123_v31_fast_checkout_atomic.sql')}
 ${read('local/retail_checkout.sql')}
 ${read('local/retail_receiving.sql').replace(/^\s*(begin|commit)\s*;\s*$/gmi,'')}
 ${scenario}
 set local role authenticated;
 select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
 do $$ declare org uuid; product uuid; recovered record; begin
 select org_id into org from public.organization_members where user_id=auth.uid() limit 1;
 select id into product from public.products where org_id=org and name='Synthetic rice';
 update public.products set unit_price=11 where id=product;
 begin
  perform public.fast_checkout_atomic(org,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  jsonb_build_array(jsonb_build_object('product_id',product,'description','Synthetic rice','quantity',1,'unit_price',10)),18,'PEN','efectivo');
  raise exception 'Stale price accepted';
 exception when sqlstate 'P2001' then null; end;
 if exists(select 1 from public.fast_checkout_requests where request_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc') then raise exception 'Rejected price left request'; end if;
 select * into recovered from public.fast_checkout_atomic(org,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  jsonb_build_array(jsonb_build_object('product_id',product,'description','Synthetic rice','quantity',2,'unit_price',10)),18,'PEN','efectivo');
 if not recovered.reused or recovered.charged<>23.60 then raise exception 'Recovery failed after price change'; end if;
 update public.products set unit_price=10 where id=product;
 raise notice 'PASS: stale price rolls back; prior committed sale recovers at original amount'; end $$;
 reset role;
 create temp table after_pos as ${snapshot};
 do $$ begin if (select fingerprint from before_pos) is distinct from (select fingerprint from after_pos)
 then raise exception 'Historical Hub/Auth contracts changed'; end if;
 raise notice 'PASS: historical users, organizations, licenses, events and license functions preserved'; end $$;
 commit;`);
// This log may contain private restore data on failure; do not commit or print it.
const log=process.env.RETAIL_PRIVATE_LOG;
if(log) writeFileSync(log,result.stdout+result.stderr);
console.log((result.stdout+'\n'+result.stderr).split('\n').filter(l=>/PASS:|ERROR:/.test(l)).join('\n'));
if(result.status) {console.log(`Preserved failed clone: ${database}`);process.exit(result.status);}
const durable=call(sqlArgs,`set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$ declare org uuid; begin
 select org_id into org from public.organization_members where user_id=auth.uid() limit 1;
 if (select stock from public.products where org_id=org and name='Synthetic rice')<>8 then raise exception 'Persisted stock mismatch'; end if;
 if (select count(*) from public.invoices where org_id=org)<>1 then raise exception 'Persisted history mismatch'; end if;
 if (select sum(amount) from public.payments where org_id=org)<>23.60 then raise exception 'Persisted payments mismatch'; end if;
 if (public.day_summary(org,(now() at time zone 'America/Lima')::date)->>'expected_cash')::numeric<>23.60 then raise exception 'Persisted cash mismatch'; end if;
 raise notice 'PASS: new connection reads committed history=1, payment/cash=23.60, stock=8'; end $$;`);
console.log((durable.stdout+'\n'+durable.stderr).split('\n').filter(l=>/PASS:|ERROR:/.test(l)).join('\n'));
console.log(`Preserved database: ${database}`);
process.exitCode=durable.status ?? 1;
