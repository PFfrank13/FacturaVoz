'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const jws = require('../src/lib/jws');
const { startHub, Client, makeUser, login, sudo, catalog, keysOf } = require('./helpers');

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test('formulario de contacto: CORS del sitio, trampa para robots, consentimiento, datos cifrados', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const pre = await fetch(h.base + '/v1/public/leads', { method: 'OPTIONS', headers: { Origin: 'https://solvex.pe' } });
  assert.equal(pre.status, 204); assert.equal(pre.headers.get('access-control-allow-origin'), 'https://solvex.pe');
  const bad = await fetch(h.base + '/v1/public/leads', { method: 'OPTIONS', headers: { Origin: 'https://otro.com' } });
  assert.equal(bad.headers.get('access-control-allow-origin'), null);
  const c = new Client(h.base);
  assert.equal((await c.post('/v1/public/leads', { contact: '987654321', consent: true, website: 'spam', elapsed_ms: 9000 })).status, 200);
  assert.equal((await c.post('/v1/public/leads', { contact: '987654321', consent: true, elapsed_ms: 500 })).status, 200);
  assert.equal(h.hub.db.get('SELECT COUNT(*) n FROM leads').n, 0, 'robots descartados en silencio');
  assert.equal((await c.post('/v1/public/leads', { contact: '987654321', consent: false, elapsed_ms: 9000 })).status, 400);
  const ok = await c.post('/v1/public/leads', { name: 'Ana Pérez', business: 'Barbería Sur', contact: '987654321', message: 'Quiero reservas', consent: true, elapsed_ms: 9000 });
  assert.equal(ok.status, 200);
  const row = h.hub.db.get('SELECT * FROM leads');
  assert.ok(!row.contact_enc.includes('987654321') && !row.name_enc.includes('Ana'));
});

test('pedir enlace de pago: misma respuesta exista o no (no permite enumerar clientes)', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); const cat = await catalog(h, c, u);
  const L = (await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' })).json.license;
  const pub = new Client(h.base);
  const good = await pub.post('/v1/public/pay-link', { license_code: L.code, doc_number: '20100047218' });
  const wrongDoc = await pub.post('/v1/public/pay-link', { license_code: L.code, doc_number: '20131312955' });
  const noLic = await pub.post('/v1/public/pay-link', { license_code: 'LIC-99999', doc_number: '20100047218' });
  assert.equal(good.status, 200); assert.deepEqual(good.json, wrongDoc.json); assert.deepEqual(good.json, noLic.json);
  assert.equal(h.hub.db.get("SELECT COUNT(*) n FROM notifications WHERE template = 'enlace_pago'").n, 1, 'solo se envía cuando coincide');
});

test('libro de reclamaciones: número correlativo, plazo en días hábiles, constancia y respuesta inmutable', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u);
  const r = await new Client(h.base).post('/v1/public/complaints', { kind: 'reclamo', name: 'Juan Torres', doc_type: 'DNI', doc_number: '45678912', email: 'juan@correo.pe', address: 'Av. Lima 123, Ica', good_type: 'servicio', good_description: 'Sistema de reservas', description: 'El sistema no envió mi constancia de pago.', request: 'Que me envíen la constancia.', accept: true });
  assert.equal(r.status, 200, r.text); assert.match(r.json.number, /^\d{4}-\d{5}$/);
  const list = (await c.get('/api/admin/complaints')).json.complaints;
  assert.equal(list.length, 1); assert.equal(list[0].consumer_name, 'Juan Torres');
  assert.equal((await c.post(`/api/admin/complaints/${list[0].id}/respond`, { response: 'Le enviamos la constancia a su correo. Disculpe las molestias.' })).status, 200);
  assert.equal((await c.post(`/api/admin/complaints/${list[0].id}/respond`, { response: 'Cambio la respuesta después de enviada...' })).status, 409);
});

test('API de instancias: clave, IP permitida, tokens por negocio y llaves públicas', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); const cat = await catalog(h, c, u);
  await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'don-corte', start: 'prueba' });
  const inst = new Client(h.base);
  assert.equal((await inst.get('/v1/instance/licenses', { Authorization: 'Bearer slxk_aaaaaaaa_' + 'x'.repeat(43) })).status, 401);
  const r = await inst.get('/v1/instance/licenses', { Authorization: 'Bearer ' + cat.apiKey });
  assert.equal(r.status, 200); assert.equal(r.json.licenses.length, 1);
  const keys = (await inst.get('/.well-known/solvex-license-keys.json')).json.keys;
  const p = jws.verify(r.json.licenses[0].token, Object.fromEntries(keys.map((k) => [k.kid, k.pem])));
  assert.equal(p.tenant, 'don-corte'); assert.equal(p.status, 'prueba'); assert.equal(p.aud, cat.instance.id);
  assert.equal((await inst.get('/v1/instance/licenses/no-existe', { Authorization: 'Bearer ' + cat.apiKey })).status, 404);
  // restringir por IP
  await c.put('/api/admin/instances/' + cat.instance.id, { name: 'Barbería SaaS', allowed_ips: '10.9.9.9', webhook_url: 'http://localhost:9999/solvex/webhook' });
  assert.equal((await inst.get('/v1/instance/licenses', { Authorization: 'Bearer ' + cat.apiKey })).status, 403);
  // rotar la clave invalida la anterior
  await c.put('/api/admin/instances/' + cat.instance.id, { name: 'Barbería SaaS', allowed_ips: '', webhook_url: 'http://localhost:9999/solvex/webhook' });
  await sudo(h, c, u);
  const nk = (await c.post(`/api/admin/instances/${cat.instance.id}/rotate`, { what: 'api_key' })).json.apiKey;
  assert.equal((await inst.get('/v1/instance/licenses', { Authorization: 'Bearer ' + cat.apiKey })).status, 401);
  assert.equal((await inst.get('/v1/instance/licenses', { Authorization: 'Bearer ' + nk })).status, 200);
});

test('producto instalable: clave mostrada una vez, límite de equipos, token atado al equipo', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u);
  const cat = await catalog(h, c, u, { kind: 'instalable', interval_unit: 'year', price: '1200' });
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cortesia', note: 'Licencia anual', max_activations: 1 });
  const key = r.json.licenseKey; assert.match(key, /^SLX(-[A-Z0-9]{5}){4}$/);
  assert.ok(!JSON.stringify(h.hub.db.get('SELECT * FROM licenses')).includes(key), 'la clave no queda guardada en claro');
  const pub = new Client(h.base);
  const a1 = await pub.post('/v1/activate', { license_key: key, fingerprint: 'equipo-1-'.padEnd(32, 'a'), label: 'Caja 1' });
  assert.equal(a1.status, 200);
  assert.ok(jws.verify(a1.json.token, keysOf(h.hub)).fp);
  assert.equal((await pub.post('/v1/activate', { license_key: key, fingerprint: 'equipo-2-'.padEnd(32, 'b') })).status, 409, 'máximo 1 equipo');
  assert.equal((await pub.post('/v1/refresh', { license_key: key, fingerprint: 'equipo-1-'.padEnd(32, 'a') })).status, 200);
  assert.equal((await pub.post('/v1/activate', { license_key: 'SLX-AAAAA-BBBBB-CCCCC-DDDDD', fingerprint: 'x'.repeat(32) })).status, 403);
});

test('webhook de Culqi: secreto en la URL, idempotencia, la verdad viene de la API, reembolso revierte', async (t) => {
  const h = await startHub({ env: { CULQI_SECRET_KEY: 'sk_test_x', CULQI_PUBLIC_KEY: 'pk_test_x' } }); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); const cat = await catalog(h, c, u);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' });
  const inv = r.json.invoice;
  const ch = await h.gateway.createCharge({ amountCents: 15000, email: 'a@b.pe', token: 'tkn_ok_x', metadata: { invoice_id: inv.id } });
  const pub = new Client(h.base);
  assert.equal((await pub.post('/webhooks/culqi/' + 'x'.repeat(32), { id: 'evt_1', type: 'charge.creation.succeeded', data: { id: ch.id } })).status, 404);
  const hook = '/webhooks/culqi/' + 'w'.repeat(32);
  assert.equal((await pub.post(hook, { id: 'evt_1', type: 'charge.creation.succeeded', data: JSON.stringify({ id: ch.id }) })).status, 200);
  await pub.post(hook, { id: 'evt_1', type: 'charge.creation.succeeded', data: { id: ch.id } });
  await wait(50);
  assert.equal(h.hub.db.get("SELECT COUNT(*) n FROM payments WHERE method = 'culqi'").n, 1, 'una sola vez');
  assert.equal(h.hub.licenses.get(r.json.license.id).status, 'activa');
  // aviso falso: un cargo que no existe en la pasarela no hace nada
  await pub.post(hook, { id: 'evt_2', type: 'charge.creation.succeeded', data: { id: 'chr_inventado_123' } });
  await wait(50);
  assert.equal(h.hub.db.get("SELECT COUNT(*) n FROM payments WHERE method = 'culqi'").n, 1);
  // reembolso
  h.gateway.refund(ch.id);
  await pub.post(hook, { id: 'evt_3', type: 'charge.refund', data: { id: ch.id } });
  await wait(50);
  assert.equal(h.hub.db.get("SELECT status FROM payments WHERE method = 'culqi'").status, 'reembolsado');
  assert.equal(h.hub.licenses.get(r.json.license.id).status, 'suspendida', 'su único pago se reembolsó');
});
