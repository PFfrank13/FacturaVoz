#!/usr/bin/env python3
"""Genera docs/reconstruccion/01_MATRIZ_RUBRO_PLAN_ROL.md leyendo los datos Dart (fuente de verdad):
app/lib/nav/role_matrix.dart, app/lib/permissions.dart, app/lib/nav/navigation_contract.dart, app/lib/rubros.dart,
app/lib/screens/catalog.dart. Replica el motor simulateExperience (la prueba role_matrix_test.dart valida el mismo motor en Dart).
Uso: python3 tool/gen_matriz.py"""
import re, os
R = os.path.join(os.path.dirname(__file__), '..')
rd = lambda p: open(os.path.join(R, p), encoding='utf-8').read()
rm, pm, nc, ru, cat = rd('app/lib/nav/role_matrix.dart'), rd('app/lib/permissions.dart'), rd('app/lib/nav/navigation_contract.dart'), rd('app/lib/rubros.dart'), rd('app/lib/screens/catalog.dart')
lst = lambda s: re.findall(r"'([^']+)'", s)

rules = {}
for m in re.finditer(r"'([\w.]+)': PermRule\((.*)\),$", pm, re.M):
    body = m.group(2)
    rules[m.group(1)] = dict(label=re.search(r"label: '([^']+)'", body).group(1),
        can=lst(re.search(r"can: \[([^\]]*)\]", body).group(1)) if 'can:' in body else [],
        feature=(re.search(r"feature: '([^']+)'", body) or [None, None])[1],
        owner='ownerOnly: true' in body, admin='adminOnly: true' in body)

def base_can(role):
    money = role in ('owner', 'admin', 'finanzas'); adm = role in ('owner', 'admin')
    return dict(finance=money, sell=role != 'tecnico', collect=role != 'tecnico', clients=True, jobs=True,
                all_jobs=role != 'tecnico', products_edit=money, team=adm, settings=adm, license=adm, **{'import': money})

basic_common = set(lst(re.search(r"const _basicCommon = \{([^}]*)\}", ru).group(1)))
basic_extra = {k: set(lst(v)) for k, v in re.findall(r"'(\w+)': \{([^}]*)\},", ru.split('const _basicExtra')[1].split('};')[0])}
pro_star = dict(re.findall(r"'(\w+)': '(\w+)',", ru.split('const proStar')[1].split('};')[0]))
all_keys = set(lst(ru.split('const allFeatureKeys')[1].split('};')[0]))
def plan_features(r, p):
    if p == 'EMPRESA': return all_keys
    return basic_common | basic_extra[r] | ({'copiloto', pro_star[r]} if p == 'PRO' else set())

navs = {}
for m in re.finditer(r"id: '(\w+)',\n    name: '([^']+)',(.*?)nav: \[(.*?)\],", ru, re.S):
    navs[m.group(1)] = (m.group(2), re.findall(r"RubroNav\('(\w+)', '([^']+)'\)", m.group(4)))
contracts = {}
for m in re.finditer(r"'(\w+)': NavContract\(([^\n]*)\),\n", nc):
    b = m.group(2)
    contracts[m.group(1)] = ((re.search(r"permission: '([^']+)'", b) or [None, None])[1], (re.search(r"feature: '([^']+)'", b) or [None, None])[1])
blocks = {}
for m in re.finditer(r"'(\w+)': HomeBlock\('\w+', '([^']+)', '([\w.]+)'(.*?)\),\n", rm):
    blocks[m.group(1)] = dict(label=m.group(2), perm=m.group(3), feature=(re.search(r"feature: '(\w+)'", m.group(4)) or [None, None])[1], route=(re.search(r"route: '(\w+)'", m.group(4)) or [None, None])[1])

def parse_roles(text):
    out = []
    for m in re.finditer(r"RubroRole\('(\w+)', '([^']+)', '(\w+)',\s*home: \[([^\]]*)\](.*?)\)(?:,|;)\n", text, re.S):
        rest = m.group(5)
        out.append(dict(id=m.group(1), label=m.group(2), base=m.group(3), home=lst(m.group(4)),
            approvals=lst((re.search(r"approvals: \[([^\]]*)\]", rest) or [None, ''])[1]),
            exact='exact: false' not in rest, gap=(re.search(r"gap: '([^']+)'", rest) or [None, ''])[1]))
    return out
common = parse_roles(rm.split('/// Roles por rubro')[0])
per = {}
body = rm.split('const rubroRoles')[1].split('\n};')[0]
for m in re.finditer(r"  '(\w+)': \[(.*?)\n  \],", body, re.S):
    per[m.group(1)] = parse_roles(m.group(2) + '\n')

cat_entries = {}
for m in re.finditer(r"FeatureEntry\(([^\n]*)\),\n", cat):
    b = m.group(1)
    fid = re.search(r"id: '(\w+)'", b).group(1)
    cat_entries[fid] = dict(title=re.search(r"title: '([^']+)'", b).group(1), feature=(re.search(r"feature: '(\w+)'", b) or [None, None])[1], perm=(re.search(r"perm: '(\w+)'", b) or [None, None])[1])
common_features = set(lst(ru.split('const commonFeatures')[1].split('};')[0]))
def rubro_feature_ids(r):
    i = ru.index(f"id: '{r}'"); j = ru.find('RubroSpec(', i + 10); blk = ru[i: j if j > 0 else None]
    ids = set()
    for a in re.findall(r"RubroArea\('[^']+', \[([^\]]*)\]", blk): ids |= set(lst(a))
    ids |= set(lst(re.search(r"home: \[([^\]]*)\]", blk).group(1)))
    ids.add(re.search(r"signature: '(\w+)'", blk).group(1))
    for name in re.findall(r"(_\w+Area)\b", blk):
        mm = re.search(rf"const {name} = RubroArea\('[^']+', \[([^\]]*)\]", ru)
        if mm: ids |= set(lst(mm.group(1)))
    return ids

def simulate(r, plan, role):
    can = base_can(role['base']); feats = plan_features(r, plan); has = lambda f: f in feats
    def allows(p):
        x = rules.get(p)
        if not x: return False
        if x['owner'] and role['base'] != 'owner': return False
        if x['admin'] and role['base'] not in ('owner', 'admin'): return False
        if not all(can.get(k, False) for k in x['can']): return False
        return x['feature'] is None or has(x['feature'])
    nav = [lbl for i, lbl in navs[r][1] if i in contracts and (contracts[i][0] is None or allows(contracts[i][0])) and (contracts[i][1] is None or has(contracts[i][1]))]
    home = [blocks[h]['label'] for h in role['home'] if h in blocks and allows(blocks[h]['perm']) and (blocks[h]['feature'] is None or has(blocks[h]['feature']))]
    allowed = [k for k in rules if allows(k)]
    shows = common_features | rubro_feature_ids(r)
    routes = [e['title'] for k, e in cat_entries.items() if k in shows and (e['perm'] is None or can.get(e['perm'], role['base'] in ('owner', 'admin'))) and (e['feature'] is None or has(e['feature'])) and (k != 'compras' or role['base'] in ('owner', 'admin')) and k not in ('tipo', 'presentacion')]
    return nav, home, allowed, [k for k in rules if k not in allowed], [a for a in role['approvals'] if a in allowed], routes

money_perms = {'reports.view', 'reports.profit', 'cash.read_all'}
out = ['# Matriz rubro × plan × rol', '',
       '> Generado por `tool/gen_matriz.py` desde el código (`nav/role_matrix.dart`, `permissions.dart`, `rubros.dart`, `catalog.dart`).',
       '> No editar a mano: cambia los datos en Dart y vuelve a generar. La prueba `test/role_matrix_test.dart` valida el mismo motor.', '',
       'Un solo motor (`roleExperience`) arma la experiencia de cada combinación: **9 rubros × 3 planes × roles**. No son 27 apps.', '',
       '**Cómo leerla.** *Rol base* = el rol que existe hoy en la base (`organization_members`). Los roles de rubro marcados ⚠ se apoyan en un rol base que no los cubre exactamente: la diferencia está escrita y requiere la migración propuesta (no aplicada).',
       '**Límites del plan**: los numéricos (usuarios, sucursales, comprobantes) los entrega Solvex Hub por empresa (`feature_limit`; si falta, 0 = denegado), no se fijan en la app.',
       '**Evidencias de prueba**: `test/role_matrix_test.dart` (reglas de seguridad en todas las combinaciones), `test/navigation_contract_test.dart` (rutas y nombres), `test/plan_prices_test.dart` (planes).', '']
labels = {k: v['label'] for k, v in rules.items()}
for r in navs:
    name = navs[r][0]
    out += [f'## {name}', '', '### Funciones por plan', '', '| Plan | Funciones del plan para este rubro |', '|---|---|']
    for p in ('BASICO', 'PRO', 'EMPRESA'):
        prev = plan_features(r, {'PRO': 'BASICO', 'EMPRESA': 'PRO'}[p]) if p != 'BASICO' else set()
        new = sorted(plan_features(r, p) - prev)
        out.append(f"| {dict(BASICO='Básico', PRO='Pro', EMPRESA='Empresa')[p]} | {'' if p == 'BASICO' else 'todo lo anterior + '}{', '.join(new)} |")
    out.append('')
    for role in common + per.get(r, []):
        warn = '' if role['exact'] else ' ⚠'
        out += [f"### {role['label']}{warn} · rol base `{role['base']}`", '']
        if role['gap']: out += [f"> ⚠ {role['gap']}", '']
        out += ['| | Básico | Pro | Empresa |', '|---|---|---|---|']
        sims = [simulate(r, p, role) for p in ('BASICO', 'PRO', 'EMPRESA')]
        row = lambda t, f: out.append(f'| {t} | ' + ' | '.join(f(s) or '—' for s in sims) + ' |')
        row('Navegación', lambda s: ' · '.join(s[0]))
        row('Inicio', lambda s: ' · '.join(s[1]))
        row('Puede', lambda s: ', '.join(labels[k] for k in s[2]))
        row('No puede', lambda s: ', '.join(labels[k] for k in s[3]))
        row('Datos de dinero', lambda s: 'Ventas, margen y todas las cajas' if money_perms & set(s[2]) else ('Solo su caja del día' if 'cash.close' in s[2] else 'No ve montos del negocio'))
        row('Aprueba', lambda s: ', '.join(labels[k] for k in s[4]))
        row('Rutas válidas', lambda s: f'{len(s[5])}: ' + ', '.join(s[5]))
        out.append('')
open(os.path.join(R, 'docs/reconstruccion/01_MATRIZ_RUBRO_PLAN_ROL.md'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('roles comunes', len(common), 'rubros', len(per), {k: len(v) for k, v in per.items()}, 'bloques', len(blocks), 'reglas', len(rules), 'contratos', len(contracts), 'navs', len(navs), 'catalogo', len(cat_entries))
