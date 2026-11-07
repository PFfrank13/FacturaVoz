"""Conservative pre-push scan. Reports locations/categories, never matched values.
Not a substitute for provider secret scanning or manual review of novel formats.
"""
import base64
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

patterns = {
    'private-key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'github-token': re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b'),
    'provider-secret': re.compile(rb'\b(?:gsk_[A-Za-z0-9]{30,}|sk-proj-[A-Za-z0-9_-]{30,}|sb_secret_[A-Za-z0-9_-]{20,})\b'),
    'aws-access-key': re.compile(rb'\bAKIA[A-Z0-9]{16}\b'),
    'credential-url': re.compile(rb'(?:postgres(?:ql)?|mysql)://[^\s:/]+:[^\s@]{8,}@'),
}
findings = []
def scan(label, content):
    if b'\0' in content[:8192]:
        return
    for category, pattern in patterns.items():
        for match in pattern.finditer(content):
            # Literal documentation placeholders and this scanner are not secrets.
            value = match.group()
            if b'example' in value.lower() or b'password' in value.lower() or len(set(value[-24:])) < 5:
                continue
            findings.append({'path': label, 'line': content[:match.start()].count(b'\n')+1, 'category': category})
    for match in re.finditer(rb'eyJ[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+', content):
        try:
            body = match.group(1)
            payload = json.loads(base64.urlsafe_b64decode(body+b'='*((-len(body))%4)))
            if payload.get('role') == 'service_role':
                findings.append({'path':label,'line':content[:match.start()].count(b'\n')+1,'category':'service-role-jwt'})
        except (ValueError, UnicodeDecodeError):
            pass

files = git('ls-files','-z','--cached','--others','--exclude-standard').split(b'\0')
for raw in set(files):
    if not raw: continue
    name = raw.decode('utf8')
    path = ROOT / name
    if path.is_file(): scan(name, path.read_bytes())
# All blobs reachable from the branch being published, preserving prior history.
objects = git('rev-list','--objects','HEAD').decode().splitlines()
for entry in objects:
    oid, _, name = entry.partition(' ')
    if not name: continue
    if git('cat-file','-t',oid).strip() != b'blob': continue
    scan(f'history:{oid[:12]}:{name}',git('cat-file','blob',oid))
print(json.dumps({'files_scanned':len(set(files))-1,'history_objects':len(objects),'findings':findings},indent=2))
raise SystemExit(1 if findings else 0)
