// Local PostgreSQL integration only. No URLs, credentials, host volumes or network.
// Auth helpers emulate JWT context, not the Supabase Auth service.
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { spawnSync, spawn } from "node:child_process";
const container = "solvex-cloud-lab-20261107";
const inspect = spawnSync("docker", ["inspect", "--format", "{{.HostConfig.NetworkMode}}|{{len .Mounts}}", container], { encoding: "utf8" });
if (inspect.status !== 0 || inspect.stdout.trim() !== "none|0") throw new Error("Refusing a non-isolated laboratory");
const root = new URL("../supabase/", import.meta.url);
const read = name => readFileSync(new URL(name, root), "utf8");
const concurrent = process.argv.includes('--concurrency');
const database = concurrent ? `solvex_lab_${Date.now()}` : 'postgres';
if (concurrent) {
  const created = spawnSync('docker',['exec',container,'createdb','-h','/tmp','-U','postgres',database],{encoding:'utf8'});
  if (created.status !== 0) throw new Error(created.stderr);
}
const bootstrap = `
do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; end $$;
do $$ begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$;
do $$ begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if; end $$;
create schema auth;
create schema extensions;
create extension pgcrypto with schema extensions;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}', created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;
`;
// Contain historical migration transaction markers inside one rollback-only run.
const migrations = readdirSync(new URL("migrations/", root)).filter(n => n.endsWith(".sql")).sort();
const sql = [bootstrap, read("schema.sql"), ...migrations.map(n => `\n-- ${n}\n${read(`migrations/${n}`)}`)]
  .map(s => s.replace(/^\s*(begin|commit|rollback)\s*;\s*$/gmi, "")).join("\n");
const args = ["exec", "-i", container, "psql", "-h", "/tmp", "-U", "postgres", "-d", database, "-v", "ON_ERROR_STOP=1"];
const result = spawnSync("docker", args, {
  input: `begin;\n${sql}\n${read("local/retail_receiving.sql")}\nselect 'PASS: full local schema loaded' as result;\n${read("tests/test_cloud_checkout.sql")}\n${read("tests/test_retail_receiving.sql")}\n${concurrent ? 'commit' : 'rollback'};`, encoding: "utf8", maxBuffer: 16 * 1024 * 1024,
});
writeFileSync(new URL("../cloud-schema-test.log", import.meta.url), result.stdout + result.stderr);
console.log((result.stdout + result.stderr).split("\n").slice(-14).join("\n"));
console.log((result.stdout + result.stderr).split("\n").filter(line => line.includes("PASS:")).join("\n"));
process.exitCode = result.status ?? 1;
if (concurrent && result.status === 0) {
  const run = input => new Promise((resolve,reject)=>{
    const child=spawn('docker',args); let output='';
    child.stdout.on('data',d=>output+=d); child.stderr.on('data',d=>output+=d);
    child.on('error',reject); child.on('close',code=>code===0?resolve(output):reject(new Error(output)));
    child.stdin.end(input);
  });
  const operation = `begin; set local role authenticated; select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
    select public.retail_receive(org_id,'ffffffff-ffff-4fff-8fff-ffffffffffff','Proveedor QA','QA-CONCURRENT',jsonb_build_array(jsonb_build_object('product_id',id,'quantity',7,'unit_cost',6))) from public.products where name='Synthetic rice'; select pg_sleep(0.5); commit;`;
  await Promise.all([run(operation),run(operation)]);
  const verification=await run(`do $$ begin
    if (select count(*) from public.retail_receipts where reference='QA-CONCURRENT')<>1 then raise exception 'Concurrent receipt duplicated'; end if;
    if (select stock from public.products where name='Synthetic rice')<>17 then raise exception 'Concurrent stock duplicated'; end if;
    if (select sum(delta) from public.retail_stock_ledger where product_id=(select id from public.products where name='Synthetic rice'))<>17 then raise exception 'Concurrent ledger mismatch'; end if;
    raise notice 'PASS: two concurrent receivers, one receipt, stock and ledger 17';
    end $$;`);
  console.log(verification); console.log(`Preserved isolated synthetic database: ${database}`);
  const sale = request => `begin; set local role authenticated; select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
    select * from public.fast_checkout_atomic((select org_id from public.products where name='Synthetic rice'),'${request}',
    (select jsonb_build_array(jsonb_build_object('product_id',id,'description','Synthetic rice','quantity',12,'unit_price',10)) from public.products where name='Synthetic rice'),18,'PEN','efectivo'); select pg_sleep(0.5); commit;`;
  const sales=await Promise.allSettled([run(sale('12345678-1111-4111-8111-111111111111')),run(sale('12345678-2222-4222-8222-222222222222'))]);
  if (sales.filter(s=>s.status==='fulfilled').length!==1 || !sales.some(s=>s.status==='rejected' && String(s.reason).includes('Stock insuficiente'))) throw new Error('Expected exactly one concurrent sale and one insufficient-stock rejection');
  const saleVerification=await run(`do $$ begin
    if (select stock from public.products where name='Synthetic rice')<>5 or (select sum(delta) from public.retail_stock_ledger where product_id=(select id from public.products where name='Synthetic rice'))<>5 then raise exception 'Concurrent sales ledger mismatch'; end if;
    if (select count(*) from public.fast_checkout_requests where request_id in ('12345678-1111-4111-8111-111111111111','12345678-2222-4222-8222-222222222222'))<>1 then raise exception 'Failed concurrent sale left request'; end if;
    if (select sum(amount) from public.payments)<>200.60 then raise exception 'Concurrent payment reconciliation mismatch'; end if;
    raise notice 'PASS: two concurrent sales compete for stock; one commits, one rolls back; stock 5, payments 200.60'; end $$;`);
  console.log(saleVerification);
  writeFileSync(new URL('../cloud-concurrency-test.log',import.meta.url),verification+saleVerification+`\nDatabase: ${database}\n`);
}
