'use strict';
/** Prueba gratis autoservicio: POST /v1/instance/trials (usado por FacturaVoz al registrar un negocio). */
const test = require('node:test');
const assert = require('node:assert/strict');
const jws = require('../src/lib/jws');
const { startHub, Client, makeUser, login, sudo, keysOf } = require('./helpers');

async function facturavoz(t) {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub);
  const c = await login(h, u);
  const p = await c.post('/api/admin/products', { code: 'FACTURAVOZ', name: 'FacturaVoz', kind: 'saas', public: true, feature_keys: ['cotizaciones', 'tienda', 'max_users'] });
  assert.equal(p.status, 201, p.text);
  const pid = p.json.product.id;
  const mk = (code, price, features) => c.post(`/api/admin/products/${pid}/plans`, { code, name: code, interval_unit: 'month', interval_count: 1, price, trial_days: 3, grace_days: 5, public: true, features });
  assert.equal((await mk('BASICO', '29', { cotizaciones: false, tienda: false, max_users: 2 })).status, 201);
  assert.equal((await mk('PRO', '59', { cotizaciones: true, tienda: true, max_users: 5 })).status, 201);
  assert.equal((await mk('EMPRESA', '119', { cotizaciones: true, tienda: true, max_users: -1 })).status, 201);
  await sudo(h, c, u);
  const ins = await c.post('/api/admin/instances', { product_id: pid, name: 'FacturaVoz producción', environment: 'produccion', webhook_url: 'http://localhost:9999/api/solvex/webhook' });
  assert.equal(ins.status, 201, ins.text);
  return { h, c, apiKey: ins.json.apiKey, instance: ins.json.instance };
}

const body = (over = {}) => Object.assign({ tenant_ref: '6f1c2a3b-0000-4000-8000-000000000001', doc_type: 'RUC', doc_number: '20100047218', business_name: 'Bodega Don Pepe', email: 'pepe@bodega.pe', phone: '987654321' }, over);

test('sin clave de instancia no se crea nada', async (t) => {
  const { h } = await facturavoz(t);
  const r = await new Client(h.base).post('/v1/instance/trials', body());
  assert.equal(r.status, 401);
});

test('crea la prueba de 3 días con el plan más completo y devuelve un token válido para la instancia', async (t) => {
  const { h, apiKey, instance } = await facturavoz(t);
  const r = await new Client(h.base).post('/v1/instance/trials', body(), { Authorization: 'Bearer ' + apiKey });
  assert.equal(r.status, 201, r.text);
  assert.equal(r.json.created, true);
  const tok = jws.verify(r.json.token, keysOf(h.hub));
  assert.equal(tok.aud, instance.id);
  assert.equal(tok.tenant, body().tenant_ref);
  assert.equal(tok.status, 'prueba');
  assert.equal(tok.mode, 'full');
  assert.equal(tok.plan, 'EMPRESA');
  assert.equal(tok.features.max_users, -1);
  const days = (Date.parse(tok.period_end) - Date.now()) / 864e5;
  assert.ok(days > 1.9 && days <= 3.01, 'vence en ~3 días (fin del tercer día, hora de Lima): ' + days);
  // auditoría
  const a = h.hub.db.all("SELECT action FROM audit_log WHERE action = 'licencia.prueba_autoservicio'");
  assert.equal(a.length, 1);
});

test('idempotente por negocio: pedirla otra vez devuelve la misma licencia', async (t) => {
  const { h, apiKey } = await facturavoz(t);
  const k = { Authorization: 'Bearer ' + apiKey };
  const a = await new Client(h.base).post('/v1/instance/trials', body(), k);
  const b = await new Client(h.base).post('/v1/instance/trials', body(), k);
  assert.equal(a.status, 201); assert.equal(b.status, 200);
  assert.equal(b.json.created, false);
  assert.equal(a.json.license_code, b.json.license_code);
});

test('una sola prueba por RUC: otro negocio con el mismo RUC recibe 409 PRUEBA_USADA', async (t) => {
  const { h, apiKey } = await facturavoz(t);
  const k = { Authorization: 'Bearer ' + apiKey };
  assert.equal((await new Client(h.base).post('/v1/instance/trials', body(), k)).status, 201);
  const r = await new Client(h.base).post('/v1/instance/trials', body({ tenant_ref: 'otra-empresa-123' }), k);
  assert.equal(r.status, 409);
  assert.equal(r.json.error, 'PRUEBA_USADA');
  assert.equal(h.hub.db.all("SELECT 1 FROM audit_log WHERE action = 'licencia.prueba_rechazada'").length, 1);
});

test('valida el RUC (dígito verificador) y el identificador del negocio', async (t) => {
  const { h, apiKey } = await facturavoz(t);
  const k = { Authorization: 'Bearer ' + apiKey };
  assert.equal((await new Client(h.base).post('/v1/instance/trials', body({ doc_number: '20100047219' }), k)).status, 400);
  assert.equal((await new Client(h.base).post('/v1/instance/trials', body({ tenant_ref: 'a b' }), k)).status, 400);
});

test('plan indicado explícitamente', async (t) => {
  const { h, apiKey } = await facturavoz(t);
  const r = await new Client(h.base).post('/v1/instance/trials', body({ plan_code: 'BASICO' }), { Authorization: 'Bearer ' + apiKey });
  assert.equal(r.status, 201, r.text);
  assert.equal(jws.verify(r.json.token, keysOf(h.hub)).plan, 'BASICO');
});

test('al vencer la prueba el token pasa a restricted (corte sin gracia en pruebas)', async (t) => {
  const { h, apiKey } = await facturavoz(t);
  const r = await new Client(h.base).post('/v1/instance/trials', body(), { Authorization: 'Bearer ' + apiKey });
  const lic = h.hub.db.get('SELECT * FROM licenses WHERE code = ?', r.json.license_code);
  h.hub.db.run('UPDATE licenses SET period_end = ?, grace_end = ? WHERE id = ?', new Date(Date.now() - 864e5).toISOString(), new Date(Date.now() - 864e5).toISOString(), lic.id);
  h.hub.licenses.sweep();
  const again = await new Client(h.base).get('/v1/instance/licenses/' + body().tenant_ref, { Authorization: 'Bearer ' + apiKey });
  const tok = jws.verify(again.json.token, keysOf(h.hub));
  assert.equal(tok.mode, 'restricted');
  assert.equal(tok.status, 'suspendida');
  assert.match(tok.pay_url || '', /\/p\/[A-Za-z0-9_-]+$/, 'trae el enlace de pago del Hub');
});
