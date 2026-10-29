'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const jws = require('../src/lib/jws');
const T = require('../src/lib/time');
const { startHub, Client, makeUser, login, sudo, catalog, shiftDays, keysOf } = require('./helpers');

const flush = async (h) => { await new Promise((r) => setImmediate(r)); await h.hub.outbox.run(); };
const lastHook = (h) => h.fetchImpl.calls.filter((c) => /webhook/.test(c.url)).pop();
const tokenOf = (h, call) => jws.verify(call.body.data.token, keysOf(h.hub));

async function world(t, opts) {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub);
  const c = await login(h, u);
  const cat = await catalog(h, c, u, opts);
  return { h, u, c, cat };
}

test('ciclo completo: cobro de alta → pago con tarjeta → activa → gracia → corte automático → pago → reactivación automática', async (t) => {
  const { h, c, cat } = await world(t);
  // 1. Licencia que se activa sola al pagar el primer cobro
  let r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'don-corte', start: 'cobro' });
  assert.equal(r.status, 201, r.text);
  const lic = r.json.license; assert.equal(lic.status, 'pendiente');
  const payUrl = r.json.invoice.pay_url; assert.match(payUrl, /\/p\/[A-Za-z0-9_-]{43}$/);
  const token = payUrl.split('/p/')[1];
  // la instancia recibe el estado "pendiente" (bloqueado)
  await flush(h);
  let hook = lastHook(h); assert.ok(hook, 'webhook enviado');
  assert.equal(tokenOf(h, hook).mode, 'blocked');
  // firma HMAC del webhook
  const ts = hook.headers['Solvex-Timestamp'], sig = hook.headers['Solvex-Signature'];
  assert.equal(sig, 'v1=' + crypto.createHmac('sha256', cat.webhookSecret).update(ts + '.' + hook.opts.body).digest('hex'));

  // 2. Página de pago pública y pago con tarjeta (pasarela simulada)
  const page = await fetch(h.base + '/p/' + token); const html = await page.text();
  assert.equal(page.status, 200); assert.match(html, /S\/ 150\.00/); assert.match(page.headers.get('content-security-policy'), /script-src 'self'/);
  const pay = await new Client(h.base).post(`/v1/public/pay/${token}/card`, { token: 'tkn_ok_1234567', email: 'luis@doncorte.pe' });
  assert.equal(pay.status, 200, pay.text); assert.match(pay.json.receipt, /^R-\d{6}$/);
  r = await c.get('/api/admin/licenses/' + lic.id);
  let L = r.json.license;
  assert.equal(L.status, 'activa');
  const today = T.localDate(Date.now(), 'America/Lima');
  assert.equal(L.period_end_local, T.lastCoveredDay(today, 'month', 1, 1), 'un mes calendario desde hoy');
  assert.equal(L.period_end, T.endOfLocalDay(L.period_end_local, 'America/Lima'), 'vence a las 23:59:59 hora de Lima');
  await flush(h);
  assert.equal(tokenOf(h, lastHook(h)).status, 'activa');
  // el mismo enlace ya no cobra dos veces
  const again = await new Client(h.base).post(`/v1/public/pay/${token}/card`, { token: 'tkn_ok_999999', email: 'luis@doncorte.pe' });
  assert.equal(again.status, 409);

  // 3. Pasa el tiempo: vence → gracia (el producto recibe "warning")
  shiftDays(h.hub, lic.id, L.days_left + 2); // venció hace 2 días
  assert.equal(h.hub.licenses.sweep(), 1);
  L = (await c.get('/api/admin/licenses/' + lic.id)).json.license;
  assert.equal(L.status, 'gracia'); assert.ok(L.cut_at);
  await flush(h);
  const tg = tokenOf(h, lastHook(h));
  assert.equal(tg.mode, 'warning'); assert.ok(tg.pay_url, 'el token trae el enlace de pago');
  assert.ok(tg.exp <= Math.ceil(Date.parse(L.grace_end) / 1000), 'el token no dura más allá del corte');
  const notif = h.hub.db.all("SELECT template FROM notifications WHERE license_id = ?", lic.id).map((x) => x.template);
  assert.ok(notif.includes('gracia'), 'aviso de gracia encolado');

  // 4. Termina la gracia: corte automático
  shiftDays(h.hub, lic.id, 6);
  h.hub.licenses.sweep();
  L = (await c.get('/api/admin/licenses/' + lic.id)).json.license;
  assert.equal(L.status, 'suspendida'); assert.equal(L.suspension, 'auto');
  await flush(h);
  assert.equal(tokenOf(h, lastHook(h)).mode, 'restricted');
  assert.ok(h.hub.db.all("SELECT template FROM notifications WHERE license_id = ?", lic.id).some((x) => x.template === 'suspension'));

  // 5. El cliente reporta un Yape desde su enlace → finanzas aprueba → se reactiva solo
  const inv = h.hub.billing.openInvoiceForLicense(h.hub.licenses.get(lic.id));
  const t2 = h.hub.billing.payToken(inv);
  const rep = await new Client(h.base).post(`/v1/public/pay/${t2}/report`, { method: 'yape', operation_ref: '00012345', amount: '150', paid_on: today });
  assert.equal(rep.status, 200, rep.text);
  const pend = (await c.get('/api/admin/payments?status=por_verificar')).json.payments;
  assert.equal(pend.length, 1);
  const dup = await new Client(h.base).post(`/v1/public/pay/${t2}/report`, { method: 'yape', operation_ref: '000-12345', amount: '150', paid_on: today });
  assert.equal(dup.status, 409, 'el mismo número de operación no se acepta dos veces');
  const ap = await c.post(`/api/admin/payments/${pend[0].id}/approve`);
  assert.equal(ap.status, 200, ap.text);
  L = ap.json.license;
  assert.equal(L.status, 'activa'); assert.equal(L.period_end_local, T.lastCoveredDay(today, 'month', 1, 1), 'tras un corte, el ciclo nuevo empieza el día del pago');
  await flush(h);
  assert.equal(tokenOf(h, lastHook(h)).status, 'activa');
  const tl = h.hub.db.all('SELECT from_status, to_status FROM license_events WHERE license_id = ? ORDER BY id', lic.id).map((e) => `${e.from_status || '∅'}→${e.to_status}`);
  assert.deepEqual(tl, ['∅→pendiente', 'pendiente→activa', 'activa→gracia', 'gracia→suspendida', 'suspendida→activa']);
});

test('pago en gracia continúa desde el vencimiento; reverso de pago devuelve la vigencia', async (t) => {
  const { h, c, u, cat } = await world(t);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cortesia', periods: 1, note: 'Cliente piloto' });
  assert.equal(r.status, 201, r.text);
  const id = r.json.license.id;
  shiftDays(h.hub, id, 33); h.hub.licenses.sweep();
  let L = h.hub.licenses.get(id); assert.equal(L.status, 'gracia');
  const before = T.localDate(L.period_end, L.timezone);
  const inv = (await c.post(`/api/admin/licenses/${id}/invoice`, { periods: 1 })).json.invoice;
  const p = await c.post('/api/admin/payments', { invoice_id: inv.id, method: 'transferencia', amount: '150', operation_ref: 'BCP-778899', approve: true });
  assert.equal(p.status, 201, p.text);
  L = h.hub.licenses.get(id);
  assert.equal(L.status, 'activa');
  assert.equal(T.localDate(L.period_end, L.timezone), T.lastCoveredDay(T.addDays(before, 1), 'month', 1, 1, L.anchor_day), 'continúa desde el fin del ciclo anterior');
  // reverso (requiere confirmación)
  h.hub.db.run('UPDATE sessions SET sudo_until = NULL');
  assert.equal((await c.post(`/api/admin/payments/${p.json.payment.id}/reverse`, { reason: 'Transferencia devuelta por el banco', kind: 'anulado' })).status, 403);
  await sudo(h, c, u);
  const rv = await c.post(`/api/admin/payments/${p.json.payment.id}/reverse`, { reason: 'Transferencia devuelta por el banco', kind: 'anulado' });
  assert.equal(rv.status, 200, rv.text);
  L = h.hub.licenses.get(id);
  assert.equal(T.localDate(L.period_end, L.timezone), before); assert.equal(L.status, 'gracia');
  assert.equal(h.hub.db.get('SELECT status FROM invoices WHERE id = ?', inv.id).status, 'pendiente');
  // un pago anulado ya no se puede tocar
  assert.throws(() => h.hub.db.run("UPDATE payments SET status = 'aprobado' WHERE id = ?", p.json.payment.id), /cerrado/);
});

test('pagos parciales, pago de más → saldo a favor que se aplica solo al siguiente cobro', async (t) => {
  const { h, c, cat } = await world(t);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' });
  const inv = r.json.invoice;
  await c.post('/api/admin/payments', { invoice_id: inv.id, method: 'yape', amount: '100', operation_ref: 'Y1', approve: true });
  let L = h.hub.licenses.get(r.json.license.id);
  assert.equal(L.status, 'pendiente', 'un pago parcial no activa');
  assert.equal(h.hub.db.get('SELECT status FROM invoices WHERE id = ?', inv.id).status, 'parcial');
  await c.post('/api/admin/payments', { invoice_id: inv.id, method: 'yape', amount: '100', operation_ref: 'Y2', approve: true });
  L = h.hub.licenses.get(r.json.license.id);
  assert.equal(L.status, 'activa');
  assert.equal(h.hub.billing.balance(cat.client.id), 5000, 'S/ 50 de saldo a favor');
  const inv2 = (await c.post(`/api/admin/licenses/${L.id}/invoice`, { periods: 1 })).json.invoice;
  assert.equal(inv2.credit_applied_cents, 5000); assert.equal(inv2.remaining_cents, 10000);
  assert.equal(h.hub.billing.balance(cat.client.id), 0);
});

test('control de cuatro ojos y permisos de aprobación', async (t) => {
  const { h, c, u, cat } = await world(t);
  const fin = await makeUser(h.hub, { email: 'fin@solvex.pe', name: 'Finanzas', role: 'finanzas' });
  const sop = await makeUser(h.hub, { email: 'sop@solvex.pe', name: 'Soporte', role: 'soporte' });
  await c.put('/api/admin/settings', { four_eyes: true });
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' });
  const cs = await login(h, sop);
  assert.equal((await cs.post('/api/admin/payments', { invoice_id: r.json.invoice.id, method: 'yape', amount: '150', operation_ref: 'Z1', approve: true })).status, 403, 'soporte no aprueba');
  const reg = await cs.post('/api/admin/payments', { invoice_id: r.json.invoice.id, method: 'yape', amount: '150', operation_ref: 'Z1' });
  assert.equal(reg.status, 201);
  assert.equal((await cs.post(`/api/admin/payments/${reg.json.payment.id}/approve`)).status, 403);
  const cf = await login(h, fin);
  const reg2 = await cf.post('/api/admin/payments', { invoice_id: r.json.invoice.id, method: 'plin', amount: '1', operation_ref: 'P1' });
  assert.equal((await cf.post(`/api/admin/payments/${reg2.json.payment.id}/approve`)).json.error, 'CUATRO_OJOS', 'quien registra no aprueba');
  assert.equal((await cf.post(`/api/admin/payments/${reg.json.payment.id}/approve`)).status, 200, 'otra persona sí');
  void u;
});

test('suspensión manual: un pago no la levanta; levantarla devuelve el estado por fechas', async (t) => {
  const { h, c, cat } = await world(t);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'don-corte', start: 'cortesia', note: 'Alta inicial' });
  const id = r.json.license.id;
  await c.post(`/api/admin/licenses/${id}/suspend`, { reason: 'Uso indebido reportado' });
  assert.equal(h.hub.licenses.get(id).status, 'suspendida');
  const inv = (await c.post(`/api/admin/licenses/${id}/invoice`, { periods: 1 })).json.invoice;
  await c.post('/api/admin/payments', { invoice_id: inv.id, method: 'efectivo', amount: '150', approve: true });
  const L = h.hub.licenses.get(id);
  assert.equal(L.status, 'suspendida'); assert.equal(L.suspension_kind, 'manual');
  await c.post(`/api/admin/licenses/${id}/resume`);
  assert.equal(h.hub.licenses.get(id).status, 'activa');
});

test('prueba gratuita: sin gracia al terminar; cobro de renovación y recordatorios automáticos', async (t) => {
  const { h, c, cat } = await world(t);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'prueba' });
  const id = r.json.license.id;
  assert.equal(r.json.license.status, 'prueba');
  assert.equal(r.json.license.period_end_local, T.addDays(T.localDate(Date.now(), 'America/Lima'), 29), '30 días contando hoy');
  shiftDays(h.hub, id, 26); // faltan 3 días
  assert.equal(h.hub.scheduler.renewals(), 1, 'cobro de renovación emitido');
  assert.equal(h.hub.scheduler.renewals(), 0, 'idempotente');
  assert.ok(h.hub.scheduler.reminders() >= 1, 'recordatorio a 3 días');
  assert.equal(h.hub.scheduler.reminders(), 0, 'no se repite');
  shiftDays(h.hub, id, 4); h.hub.licenses.sweep();
  assert.equal(h.hub.licenses.get(id).status, 'suspendida');
});

test('cancelación anula cobros abiertos; licencia movida de instancia avisa a la anterior', async (t) => {
  const { h, c, u, cat } = await world(t);
  await sudo(h, c, u);
  const ins2 = (await c.post('/api/admin/instances', { product_id: cat.product.id, name: 'Barbería SaaS 2', webhook_url: 'http://localhost:9999/otro/webhook' })).json.instance;
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'don-corte', start: 'cortesia', note: 'Alta inicial' });
  const id = r.json.license.id;
  await flush(h);
  const v = h.hub.licenses.get(id).version;
  const mv = await c.put('/api/admin/licenses/' + id, { instance_id: ins2.id, tenant_ref: 'don-corte', version: v });
  assert.equal(mv.status, 200, mv.text);
  await flush(h);
  const toOld = h.fetchImpl.calls.filter((x) => x.url.includes('/solvex/webhook')).pop();
  const toNew = h.fetchImpl.calls.filter((x) => x.url.includes('/otro/webhook')).pop();
  assert.equal(tokenOf(h, toOld).status, 'cancelada', 'la instancia anterior bloquea el negocio');
  assert.equal(tokenOf(h, toNew).status, 'activa');
  // versión vieja → conflicto
  assert.equal((await c.put('/api/admin/licenses/' + id, { label: 'Otro', version: v })).status, 409);
  const inv = (await c.post(`/api/admin/licenses/${id}/invoice`, { periods: 1 })).json.invoice;
  await sudo(h, c, u);
  await c.post(`/api/admin/licenses/${id}/cancel`, { reason: 'El cliente cerró su local' });
  assert.equal(h.hub.licenses.get(id).status, 'cancelada');
  assert.equal(h.hub.db.get('SELECT status FROM invoices WHERE id = ?', inv.id).status, 'anulada');
  assert.throws(() => h.hub.db.run('DELETE FROM licenses WHERE id = ?', id), /no se borran/);
});

test('el webhook fallido se reintenta con espera creciente y queda visible', async (t) => {
  const { h, c, cat } = await world(t);
  h.fetchImpl.responder = () => 500;
  await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'x1', start: 'cortesia', note: 'Alta inicial' });
  await flush(h);
  const d = h.hub.db.get("SELECT * FROM deliveries ORDER BY id DESC LIMIT 1");
  assert.equal(d.status, 'pendiente'); assert.equal(d.attempts, 1); assert.ok(d.next_attempt_at > T.nowIso());
  h.fetchImpl.responder = () => 200;
  h.hub.outbox.retry(d.id); await h.hub.outbox.run();
  assert.equal(h.hub.db.get('SELECT status FROM deliveries WHERE id = ?', d.id).status, 'entregado');
});

test('una extensión en días no acorta el siguiente ciclo pagado', async (t) => {
  const { h, c, u, cat } = await world(t);
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cortesia', note: 'Alta inicial' });
  const id = r.json.license.id;
  await sudo(h, c, u);
  await c.post(`/api/admin/licenses/${id}/extend`, { days: 5, note: 'Compensación por caída' });
  const before = h.hub.licenses.get(id);
  const inv = (await c.post(`/api/admin/licenses/${id}/invoice`, { periods: 1 })).json.invoice;
  await c.post('/api/admin/payments', { invoice_id: inv.id, method: 'efectivo', amount: '150', approve: true });
  const after = h.hub.licenses.get(id);
  const start = T.addDays(T.localDate(before.period_end, before.timezone), 1);
  assert.equal(T.localDate(after.period_end, after.timezone), T.lastCoveredDay(start, 'month', 1, 1), 'un mes completo desde el día siguiente');
});
