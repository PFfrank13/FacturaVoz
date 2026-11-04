// Disposable PostgreSQL only. The named container has no network or host database volume.
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
const container = process.env.FV_SQL_CONTAINER || "facturavoz-erp-local-sql-20261104";
const read = name => readFileSync(new URL(`../supabase/${name}`, import.meta.url), "utf8");
const definition = (sql, name) => {
  const start = sql.indexOf(`create or replace function private.${name}(`);
  if (start < 0) throw new Error(`Missing function ${name}`);
  const end = sql.indexOf("$$;", start);
  return sql.slice(start, end + 3);
};
const old = read("migrations/20261118_v31_planes_por_rubro.sql");
const activation = read("migrations/20261124_v31_solvex_activation_required.sql");
const setup = `
create schema private;
create role authenticated;
create table public.organizations(id uuid primary key);
create table public.org_licenses(org_id uuid primary key, source text, token text, mode text, features jsonb);
create table public.products(id integer primary key, org_id uuid, stock numeric, reorder_point numeric, name text);
create table public.jobs(id integer primary key, org_id uuid, kind text, title text);
create function private.org_mode(p_org uuid) returns text language sql as $$ select mode from public.org_licenses where org_id=p_org $$;
create function private.license_enforced() returns boolean language sql as $$ select true $$;
create function private.license_write_ok(p_org uuid) returns boolean language sql as $$ select private.org_mode(p_org) in ('full','warning') $$;
${definition(read("migrations/20261111_licencias.sql"), "all_features")}
${definition(read("migrations/20261115_v3_rubros.sql"), "rubro_core")}
${definition(old, "plan_matrix")}
${definition(old, "plan_union")}
${definition(old, "plan_allows")}
do $$ begin
  if not private.plan_allows('bodega','EMPRESA','{"stock":false}'::jsonb,'stock') then raise exception 'Historical bug did not reproduce'; end if;
  raise notice 'REPRODUCED: historical matrix enables stock=false';
end $$;
${definition(activation, "effective_features")}
${definition(activation, "feature_for")}
`;
const assertions = `
insert into organizations values ('00000000-0000-4000-8000-000000000001');
insert into org_licenses values ('00000000-0000-4000-8000-000000000001','hub','synthetic-test-token','full','{"stock":false,"trabajos":false,"agenda":true,"max_users":2}'::jsonb);
insert into products values (1,'00000000-0000-4000-8000-000000000001',10,2,'Synthetic product');
insert into jobs values (1,'00000000-0000-4000-8000-000000000001','servicio','Synthetic job');
create trigger products_license_guard before insert or update or delete on products for each row execute function private.license_guard();
create trigger jobs_license_guard before insert or update or delete on jobs for each row execute function private.license_guard();
do $$ declare org uuid := '00000000-0000-4000-8000-000000000001'; begin
  if private.has_feature(org,'stock') then raise exception 'Stock denial lost'; end if;
  if private.feature_limit(org,'max_users') <> 2 then raise exception 'User limit lost'; end if;
  if private.feature_limit(org,'max_branches') <> 0 then raise exception 'Missing limit became unlimited'; end if;
  begin update products set stock=11 where id=1; raise exception 'Stock update allowed'; exception when insufficient_privilege then null; end;
  update products set name='Catalog editing still allowed' where id=1;
  begin update jobs set title='Denied edit' where id=1; raise exception 'Job update allowed'; exception when insufficient_privilege then null; end;
  begin update jobs set kind='cita' where id=1; raise exception 'Feature switch allowed'; exception when insufficient_privilege then null; end;
  update org_licenses set features='{"stock":true,"max_users":-1}'::jsonb where org_id=org;
  update products set stock=12 where id=1;
  if private.feature_limit(org,'max_users') <> -1 then raise exception 'Unlimited value lost'; end if;
  update org_licenses set mode='blocked' where org_id=org;
  if private.has_feature(org,'stock') or private.feature_limit(org,'max_users') <> 0 then raise exception 'Blocked license grants rights'; end if;
  begin update products set name='Blocked edit' where id=1; raise exception 'Blocked write allowed'; exception when insufficient_privilege then null; end;
  raise notice 'PASS: denial, omission, limits, stock updates, feature transitions and blocked writes';
end $$;
`;
const inspect = spawnSync("docker", ["inspect", "--format", "{{.HostConfig.NetworkMode}}|{{len .Mounts}}", container], { encoding: "utf8" });
if (inspect.status !== 0 || inspect.stdout.trim() !== "none|0") throw new Error("Refusing non-isolated container");
// Roll back all synthetic schema and records; repeatable, no cleanup of user data.
const migration = read("migrations/20261125_v32_hub_feature_precedence.sql").replace(/^begin;$/m, "").replace(/^commit;$/m, "");
const tests = read("tests/test_hub_precedence.sql").replace(/^begin;$/m, "").replace(/^rollback;$/m, "");
const result = spawnSync("docker", ["exec", "-i", container, "psql", "-h", "/tmp", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], { input: `begin;\n${setup}\n${migration}\n${tests}\n${assertions}\nrollback;`, encoding: "utf8" });
process.stdout.write(result.stdout); process.stderr.write(result.stderr); process.exitCode = result.status ?? 1;
