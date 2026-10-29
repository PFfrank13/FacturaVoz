'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { startHub, Client, makeUser, login, catalog } = require('./helpers');

test('en el archivo de la base no aparece ningún dato personal en claro', async (t) => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'slx-')), 'hub.db');
  const h = await startHub({ file }); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); await catalog(h, c, u);
  await c.post('/api/admin/clients/' + (await c.get('/api/admin/clients')).json.clients[0].id + '/contacts', { channel: 'WhatsApp', note: 'Conversamos con Luis sobre su cumpleaños 12/03' });
  h.hub.db.raw.exec('PRAGMA wal_checkpoint(TRUNCATE)');
  const raw = fs.readFileSync(file).toString('latin1') + (fs.existsSync(file + '-wal') ? fs.readFileSync(file + '-wal').toString('latin1') : '');
  for (const secret of ['20100047218', 'luis@doncorte.pe', '987654321', '51987654321', 'Luis Ramos', 'cumpleaños', u.secret]) assert.ok(!raw.includes(secret), 'aparece en claro: ' + secret);
  assert.ok(raw.includes('Don Corte'), 'el nombre comercial sí es visible (es público)');
});

test('la bitácora detecta manipulación aunque se salten los triggers', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); await catalog(h, c, u);
  assert.equal((await c.post('/api/admin/audit/verify')).json.ok, true);
  assert.throws(() => h.hub.db.run("UPDATE audit_log SET actor_label = 'otro' WHERE seq = 2"), /solo inserción/);
  assert.throws(() => h.hub.db.run('DELETE FROM audit_log WHERE seq = 2'), /solo inserción/);
  // un atacante con acceso total borra el trigger y edita
  h.hub.db.exec('DROP TRIGGER audit_no_update');
  h.hub.db.run("UPDATE audit_log SET data = '{\"amount_cents\":1}' WHERE seq = 3");
  const r = h.hub.audit.verify();
  assert.equal(r.ok, false); assert.equal(r.brokenAt, 3);
  h.hub.db.exec('DROP TRIGGER audit_no_delete');
  const n = h.hub.db.get('SELECT MAX(seq) m FROM audit_log').m;
  h.hub.db.run('DELETE FROM audit_log WHERE seq = ?', n);
  assert.equal(h.hub.audit.verify().ok, false);
});

test('inyección SQL, rutas raras y XSS no pasan', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); const cat = await catalog(h, c, u);
  const q = await c.get("/api/admin/clients?q=" + encodeURIComponent("' OR 1=1 --"));
  assert.equal(q.status, 200); assert.equal(q.json.total, 0);
  for (const p of ['/panel/..%2f..%2f.env', '/panel/%2e%2e/src/config.js', '/panel/../package.json', '/static/../.env']) assert.equal((await fetch(h.base + p)).status, 404, p);
  const x = await c.post('/api/admin/clients', { kind: 'persona', display_name: '<img src=x onerror=alert(1)>', doc_type: 'DNI', doc_number: '12345678' });
  assert.equal(x.status, 201);
  const lic = (await c.post('/api/admin/licenses', { client_id: x.json.client.id, plan_id: cat.plan.id, start: 'cobro' })).json;
  const html = await (await fetch(lic.invoice.pay_url.replace('http://localhost:8080', h.base))).text();
  assert.ok(!html.includes('<img src=x'), 'escapado en la página de pago'); assert.ok(html.includes('&lt;img src=x'));
  const big = await c.req('POST', '/api/admin/clients', '{"a":"' + 'x'.repeat(300 * 1024) + '"}');
  assert.equal(big.status, 413);
  const badJson = await c.req('POST', '/api/admin/clients', '{nope');
  assert.equal(badJson.status, 400);
  const massAssign = await c.post('/api/admin/clients', { kind: 'persona', display_name: 'Prueba', doc_type: 'DNI', doc_number: '87654321', verification: 'verificado', id: 'cli_hack', code: 'CLI-9999' });
  assert.equal(massAssign.json.client.verification, 'pendiente'); assert.notEqual(massAssign.json.client.id, 'cli_hack');
});

test('cabeceras de seguridad del panel y de la API', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const p = await fetch(h.base + '/panel/');
  assert.match(p.headers.get('content-security-policy'), /script-src 'self'/);
  assert.equal(p.headers.get('x-frame-options'), 'DENY');
  assert.equal(p.headers.get('x-content-type-options'), 'nosniff');
  const a = await fetch(h.base + '/api/admin/auth/me');
  assert.equal(a.status, 401); assert.equal(a.headers.get('cache-control'), 'no-store');
  assert.equal((await fetch(h.base + '/api/admin/auth/me', { headers: { 'X-Forwarded-For': '1.2.3.4' } })).status, 401);
});

test('lista de IPs del panel: fuera de la lista, el panel "no existe"', async (t) => {
  const h = await startHub({ env: { ADMIN_ALLOWED_IPS: '10.0.0.0/8' } }); t.after(h.stop);
  assert.equal((await fetch(h.base + '/panel/')).status, 404);
  assert.equal((await fetch(h.base + '/api/admin/auth/me')).status, 404);
  assert.equal((await fetch(h.base + '/health')).status, 200);
});

test('anonimizar cliente (derecho de supresión) conserva lo contable', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); const cat = await catalog(h, c, u);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' });
  await c.post('/api/admin/payments', { invoice_id: r.json.invoice.id, method: 'efectivo', amount: '150', approve: true });
  await c.post('/api/admin/auth/sudo', { code: require('./helpers').code(h.hub, u) });
  assert.equal((await c.post(`/api/admin/clients/${cat.client.id}/anonymize`)).status, 409, 'con licencias vivas no');
  await c.post(`/api/admin/licenses/${r.json.license.id}/cancel`, { reason: 'Cierre del negocio' });
  assert.equal((await c.post(`/api/admin/clients/${cat.client.id}/anonymize`)).status, 200);
  const row = h.hub.db.get('SELECT * FROM clients WHERE id = ?', cat.client.id);
  assert.equal(row.email_enc, null); assert.match(row.display_name, /anonimizado/);
  assert.equal(h.hub.db.get("SELECT COUNT(*) n FROM payments WHERE client_id = ? AND status = 'aprobado'", cat.client.id).n, 1, 'el pago se conserva');
});
