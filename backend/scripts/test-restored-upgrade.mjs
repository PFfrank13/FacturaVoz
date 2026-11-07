// Exercise the receiving proposal against an actual private restore, not a
// reconstructed migration baseline. Never connects to a hosted database.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const container = 'solvex-cloud-lab-20261107';
const database = process.argv[2];
if (!/^restore_\d+$/.test(database ?? '')) throw new Error('Expected an isolated restore database');
const state = spawnSync('docker', ['inspect','--format','{{.HostConfig.NetworkMode}}|{{len .Mounts}}',container], {encoding:'utf8'});
if (state.status || state.stdout.trim() !== 'none|0') throw new Error('Laboratory isolation required');
const proposal = readFileSync(new URL('../supabase/local/retail_receiving.sql',import.meta.url),'utf8').replace(/^\s*(begin|commit)\s*;\s*$/gmi,'');
const snapshot = `SELECT jsonb_build_object(
 'licenses',(select jsonb_agg(to_jsonb(t) order by t.org_id) from public.org_licenses t),
 'events',(select jsonb_agg(to_jsonb(t) order by t.id) from public.solvex_events t),
 'organizations',(select jsonb_agg(to_jsonb(t) order by t.id) from public.organizations t),
 'auth',(select jsonb_agg(to_jsonb(t) order by t.id) from auth.users t),
 'license_functions',(select jsonb_agg(pg_get_functiondef(p.oid) order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname like '%license%')
) AS fingerprint`;
const sql = `BEGIN; CREATE TEMP TABLE before_upgrade AS ${snapshot};
${proposal}
CREATE TEMP TABLE after_upgrade AS ${snapshot};
DO $$ BEGIN
 IF (SELECT fingerprint FROM before_upgrade) IS DISTINCT FROM (SELECT fingerprint FROM after_upgrade) THEN
 RAISE EXCEPTION 'Protected contracts changed'; END IF;
 IF NOT EXISTS(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='retail_receipts' and c.relrowsecurity) THEN RAISE EXCEPTION 'Receipt RLS missing'; END IF;
 RAISE NOTICE 'PASS: receiving proposal applies to restored production; Auth, organizations, licenses, events and license functions unchanged';
END $$;
ROLLBACK;`;
const result = spawnSync('docker',['exec','-i',container,'psql','-h','/tmp','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',maxBuffer:8*1024*1024});
// Avoid exposing restored business data even when a query fails.
console.log((result.stdout+'\n'+result.stderr).split('\n').filter(l=>/PASS:|ERROR:|ROLLBACK/.test(l)).join('\n'));
process.exitCode=result.status ?? 1;
