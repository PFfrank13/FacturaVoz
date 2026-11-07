"""Restore private SQL exports into a NEW database in the network-isolated lab.

Never accepts a database URL. Does not delete databases. Logs may contain private
data on restore errors; keep the supplied backup directory outside the repository.
"""
import argparse
import datetime
import json
import re
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('backup', type=Path)
a = p.parse_args()
folder = a.backup.resolve()
root = Path(__file__).resolve().parents[1]
if folder == root or root in folder.parents:
    raise SystemExit('Private backups must remain outside the repository')
container = 'solvex-cloud-lab-20261107'
def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, encoding='utf-8', **kw)
state = run(['docker','inspect','--format','{{.HostConfig.NetworkMode}}|{{len .Mounts}}',container])
if state.returncode or state.stdout.strip() != 'none|0':
    raise SystemExit('Laboratory must have no network and no host mounts')
database = 'restore_' + datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')
created = run(['docker','exec',container,'createdb','-h','/tmp','-U','postgres',database])
if created.returncode:
    raise SystemExit(created.stderr)
managed = (folder/'managed-schema.sql').read_text(encoding='utf-8')
schema = (folder/'schema.sql').read_text(encoding='utf-8')
# Storage policies depend on application functions: install them after public/private.
policies = re.findall(r'^CREATE POLICY .*?;\s*$', managed, re.M)
managed = re.sub(r'^CREATE POLICY .*?;\s*$', '', managed, flags=re.M)
policies += re.findall(r'^CREATE OR REPLACE TRIGGER .*?;\s*$', managed, re.M)
managed = re.sub(r'^CREATE OR REPLACE TRIGGER .*?;\s*$', '', managed, flags=re.M)
roles = sorted(set(re.findall(r'OWNER TO "([a-z_]+)"', managed+schema)) | {'anon','authenticated','service_role','authenticator','supabase_admin','supabase_auth_admin','supabase_storage_admin','dashboard_user'})
bootstrap = '\n'.join("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='%s') THEN CREATE ROLE %s; END IF; END $$;" % (r,r) for r in roles)
bootstrap += '\nCREATE SCHEMA extensions; CREATE SCHEMA vault; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;\n'
bootstrap += 'CREATE PUBLICATION supabase_realtime;\n'
# Circular invoice FKs and existing user triggers: restore data with replication
# disabled ONLY inside this isolated transaction. Validate every FK afterwards.
sql = 'BEGIN;\n'+bootstrap+managed+schema+'\n'.join(policies)
sql += '\nSET LOCAL session_replication_role=replica;\n'
# Current CLI data.sql already includes auth/storage. Supplement only migration
# history, avoiding duplicate auth sessions from separate capture times.
extra = (folder/'auth-storage-migrations.sql').read_text(encoding='utf-8')
sql += '\n'.join(re.findall(r'^COPY "supabase_migrations"\..*?^\\\.$', extra, re.M | re.S)) + '\n'
sql += (folder/'data.sql').read_text(encoding='utf-8')
sql += '\nSET LOCAL session_replication_role=origin;\n'
sql += """
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT conrelid::regclass AS tbl, conname, pg_get_constraintdef(oid) AS def
 FROM pg_constraint WHERE contype='f' AND connamespace IN
 (SELECT oid FROM pg_namespace WHERE nspname IN ('public','auth','storage')) LOOP
 EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',r.tbl,r.conname);
 EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s',r.tbl,r.conname,r.def);
 END LOOP;
END $$;
COMMIT;
SELECT 'RESTORE_OK';
"""
result = run(['docker','exec','-i',container,'psql','-h','/tmp','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],input=sql)
(folder/'restore-private.log').write_text(result.stdout+result.stderr,encoding='utf-8')
report = {'database':database,'container':container,'network':'none','host_mounts':0,'exit_code':result.returncode,'restored':result.returncode==0,'scope':'SQL schema/data/FK validation; not a full hosted Auth/Storage service restore'}
(folder/'restore-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
raise SystemExit(result.returncode)
