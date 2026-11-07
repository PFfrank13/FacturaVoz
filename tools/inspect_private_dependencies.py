"""Read-only dependency check using an exported environment outside Git.

Never prints credential values or signed license tokens. Does not activate,
sync, issue trials, send heartbeats, or modify the Hub.
"""
import argparse
import json
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

p = argparse.ArgumentParser()
p.add_argument('environment', type=Path)
a = p.parse_args()
values = {}
for line in a.environment.read_text(encoding='utf-8-sig').splitlines():
    if not line or line.startswith('#') or '=' not in line:
        continue
    name, value = line.split('=', 1)
    values[name] = json.loads(value) if value.startswith('"') else value
withheld = sorted(k for k,v in values.items() if v == '[SENSITIVE]')
if withheld:
    print(json.dumps({'status':'credentials_withheld_by_provider','names':withheld,'live_hub_check':False},indent=2))
    raise SystemExit(2)
hub = values.get('SOLVEX_HUB_URL', '').rstrip('/')
if urlparse(hub).scheme != 'https':
    raise SystemExit('Expected configured HTTPS Hub URL')
report = {
    'supabase_host': urlparse(values.get('NEXT_PUBLIC_SUPABASE_URL', '')).hostname,
    'hub_host': urlparse(hub).hostname,
    'instance_configured': bool(values.get('SOLVEX_INSTANCE_ID')),
    'webhook_secret_configured': bool(values.get('SOLVEX_WEBHOOK_SECRET')),
}
request = urllib.request.Request(hub+'/v1/instance/licenses', headers={
    'Authorization': 'Bearer '+values['SOLVEX_API_KEY'],
})
with urllib.request.urlopen(request, timeout=20) as response:
    payload = json.load(response)
    report['license_list_http_status'] = response.status
    report['license_count'] = len(payload.get('licenses', []))
    report['tenant_reference_count'] = sum(bool(x.get('tenant_ref')) for x in payload.get('licenses', []))
with urllib.request.urlopen(hub+'/.well-known/solvex-license-keys.json', timeout=20) as response:
    payload = json.load(response)
    report['public_keys_http_status'] = response.status
    report['issuer'] = payload.get('issuer')
    report['public_key_count'] = len(payload.get('keys', []))
print(json.dumps(report, indent=2))
