'use strict';
/** Impuestos (IGV / exportación / Nuevo RUS), comprobantes electrónicos, Merchant of Record y migración. */
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { split, portion, decide } = require('../src/services/tax');
const migrations = require('../src/db/migrations');
const { Db } = require('../src/db');
const { startHub, Client, makeUser, login, sudo, catalog } = require('./helpers');

const PADDLE = 'pdl_ntfset_secreto_de_pruebas_0123456789';
const LEMON = 'lemon_secreto_de_pruebas_0123456789';
const IGV = { code: 'PE-IGV', label: 'IGV', rate_bp: 1800 };

/* ------------------------------------------------------------ cálculo puro */
test('cálculo: precio con IGV incluido, más IGV, exportación y abonos parciales', () => {
  assert.deepEqual(split(15000, 'incluido', 1800, 1800), { subtotal: 12712, tax: 2288, total: 15000 }, 'S/ 150 con IGV = 127.12 + 22.88');
  assert.deepEqual(split(10000, 'mas_impuesto', 1800, 1800), { subtotal: 10000, tax: 1800, total: 11800 });
  assert.deepEqual(split(15000, 'incluido', 0, 1800), { subtotal: 12712, tax: 0, total: 12712 }, 'exportación: se cobra solo la base');
  assert.deepEqual(split(9900, 'mas_impuesto', 0, 1800), { subtotal: 9900, tax: 0, total: 9900 });
  assert.deepEqual(split(1, 'incluido', 1800, 1800), { subtotal: 1, tax: 0, total: 1 }, 'un céntimo no se parte');
  for (let p = 1; p < 50000; p += 37) { const r = split(p, 'incluido', 1800, 1800); assert.equal(r.subtotal + r.tax, p); assert.ok(Math.abs(r.tax - p * 0.18 / 1.18) <= 1); }
  const inv = { amount_cents: 15000, subtotal_cents: 12712, tax_cents: 2288 };
  assert.deepEqual(portion(15000, inv), { subtotal: 12712, tax: 2288, total: 15000 });
  const a = portion(5000, inv), b = portion(10000, inv);
  assert.equal(a.subtotal + a.tax, 5000); assert.equal(a.subtotal + b.subtotal + (a.tax + b.tax), 15000);
  assert.ok(Math.abs(a.tax + b.tax - 2288) <= 1, 'dos abonos suman el IGV del cobro (±1 céntimo)');
});

test('decisión: factura/boleta, exportación, no domiciliado sin registro, Nuevo RUS, impuesto extranjero', () => {
  const ctx = { regime: 'mype', exportRegistered: false, peRule: IGV, foreignRule: null };
  let d = decide({ country: 'PE', doc_type: 'RUC' }, ctx); assert.equal(d.treatment, 'gravado'); assert.equal(d.fiscal_doc, 'factura'); assert.equal(d.rate, 1800);
  d = decide({ country: 'PE', doc_type: 'DNI' }, ctx); assert.equal(d.fiscal_doc, 'boleta');
  d = decide({ country: 'CO', doc_type: 'EXT' }, ctx); assert.equal(d.operation, 'no_domiciliado'); assert.equal(d.rate, 1800, 'sin inscripción no califica como exportación');
  d = decide({ country: 'CO', doc_type: 'EXT' }, { ...ctx, exportRegistered: true }); assert.equal(d.treatment, 'exportacion'); assert.equal(d.rate, 0); assert.equal(d.fiscal_doc, 'factura');
  d = decide({ country: 'CL', doc_type: 'EXT' }, { ...ctx, exportRegistered: true, foreignRule: { code: 'CL-IVA', label: 'IVA', rate_bp: 1900 } }); assert.equal(d.treatment, 'impuesto_extranjero'); assert.equal(d.rate, 1900);
  d = decide({ country: 'PE', doc_type: 'RUC' }, { ...ctx, regime: 'nrus' }); assert.equal(d.rate, 0); assert.equal(d.fiscal_doc, 'boleta');
  assert.throws(() => decide({ country: 'PE' }, { ...ctx, peRule: null }), /IGV/);
});

/* ------------------------------------------------------------ cobros con impuesto + comprobantes */
async function world(t, env = {}) {
  const h = await startHub({ env: Object.assign({ PADDLE_WEBHOOK_SECRET: PADDLE, LEMONSQUEEZY_WEBHOOK_SECRET: LEMON }, env) }); t.after(h.stop);
  const u = await makeUser(h.hub); const c = await login(h, u); const cat = await catalog(h, c, u);
  return { h, u, c, cat };
}
const tick = () => new Promise((r) => setTimeout(r, 15));
async function emit(h) { await tick(); return h.hub.einvoice.run(); }
const enable = (h, extra = {}) => h.hub.settings.set('einvoice', Object.assign({}, h.hub.settings.get('einvoice'), { enabled: true }, extra));

test('cliente con RUC: IGV incluido → factura al pagar; reembolso → nota de crédito; registro de ventas cuadra', async (t) => {
  const { h, c, u, cat } = await world(t);
  // activar comprobantes por la API exige confirmar con 2FA
  h.hub.db.run('UPDATE sessions SET sudo_until = NULL');
  let r = await c.put('/api/admin/settings', { einvoice: Object.assign({}, h.hub.settings.get('einvoice'), { enabled: true }) });
  assert.equal(r.status, 403); assert.equal(r.json.needSudo, true);
  await sudo(h, c, u);
  r = await c.put('/api/admin/settings', { einvoice: Object.assign({}, h.hub.settings.get('einvoice'), { enabled: true }) });
  assert.equal(r.status, 200, r.text);
  await c.put('/api/admin/clients/' + cat.client.id, { kind: 'empresa', display_name: 'Barbería Don Corte', legal_name: 'DON CORTE S.A.C.', doc_type: 'RUC', doc_number: '20100047218', address: 'Av. Grau 123, Ica', email: 'luis@doncorte.pe', version: cat.client.version });

  r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'don-corte', start: 'cobro' });
  const inv = r.json.invoice, lic = r.json.license;
  assert.equal(inv.amount_cents, 15000); assert.equal(inv.subtotal_cents, 12712); assert.equal(inv.tax_cents, 2288);
  assert.equal(inv.fiscal_doc, 'factura'); assert.equal(inv.tax_treatment, 'gravado'); assert.match(inv.tax_label, /IGV 18/);

  const token = inv.pay_url.split('/p/')[1];
  const page = await (await fetch(h.base + '/p/' + token)).text();
  assert.match(page, /Valor de venta/); assert.match(page, /S\/ 127\.12/); assert.match(page, /S\/ 22\.88/); assert.match(page, /factura electrónica/i);
  assert.doesNotMatch(page, /20100047218/, 'el documento se muestra enmascarado');

  const pay = await new Client(h.base).post(`/v1/public/pay/${token}/card`, { token: 'tkn_ok_1234567', email: 'luis@doncorte.pe' });
  assert.equal(pay.status, 200, pay.text);
  await emit(h);
  let docs = (await c.get('/api/admin/fiscal-documents')).json.documents;
  assert.equal(docs.length, 1); const f = docs[0];
  assert.equal(f.kind, 'factura'); assert.equal(f.doc, 'F001-00000001'); assert.equal(f.status, 'aceptado');
  assert.equal(f.subtotal_cents, 12712); assert.equal(f.tax_cents, 2288); assert.equal(f.total_cents, 15000);
  const sent = h.hub.einvoice.provider.calls.pop();
  assert.equal(sent.customer.doc_type, 'RUC'); assert.equal(sent.customer.address, 'Av. Grau 123, Ica'); assert.equal(sent.igv_rate_bp, 1800);

  // con dinero aplicado, el desglose no se puede tocar ni por SQL
  assert.throws(() => h.hub.db.run('UPDATE invoices SET tax_cents = 0, subtotal_cents = amount_cents WHERE id = ?', inv.id), /no se modifica/);
  assert.throws(() => h.hub.db.run("UPDATE fiscal_documents SET total_cents = 1 WHERE id = ?", f.id), /no se modifica/);
  assert.throws(() => h.hub.db.run('DELETE FROM fiscal_documents WHERE id = ?', f.id), /nota de crédito/);

  // reembolso → nota de crédito 06 que referencia la factura, y la licencia se revierte
  const p = (await c.get('/api/admin/payments')).json.payments[0];
  await sudo(h, c, u);
  r = await c.post(`/api/admin/payments/${p.id}/reverse`, { reason: 'Cliente desistió en la primera semana', kind: 'reembolsado' });
  assert.equal(r.status, 200, r.text);
  await emit(h);
  docs = (await c.get('/api/admin/fiscal-documents')).json.documents;
  const nc = docs.find((d) => d.kind === 'nota_credito');
  assert.equal(nc.doc, 'FC01-00000001'); assert.equal(nc.related.doc, 'F001-00000001'); assert.equal(nc.note_reason, '06'); assert.equal(nc.status, 'aceptado');
  assert.equal((await c.get('/api/admin/licenses/' + lic.id)).json.license.status, 'suspendida', 'sin pago que la cubra, se corta');

  const month = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date()).slice(0, 7);
  const csv = await c.get('/api/admin/sales-register?month=' + month);
  assert.equal(csv.status, 200); assert.match(csv.headers.get('content-type'), /text\/csv/);
  assert.match(csv.text, /Factura,F001,1,RUC,20100047218,DON CORTE S\.A\.C\./); assert.match(csv.text, /Nota de crédito,FC01,1.*-22\.88/);
  assert.equal(h.hub.einvoice.salesCsv(month).totals.igv, 0, 'factura menos nota de crédito = 0 de IGV');
  const dash = (await c.get('/api/admin/dashboard')).json.kpis; assert.equal(dash.igv_month_cents, 0);
});

test('cliente del extranjero: IGV sin inscripción de exportador; exportación al 0 % cuando se inscribe (recalcula el cobro abierto)', async (t) => {
  const { h, c, cat } = await world(t);
  enable(h);
  let r = await c.post('/api/admin/clients', { kind: 'empresa', display_name: 'Barber Co', legal_name: 'BARBER CO LLC', doc_type: 'EXT', doc_number: '12-3456789', country: 'us', address: '100 Main St, Miami FL', email: 'ap@barber.co' });
  assert.equal(r.status, 201, r.text); const cl = r.json.client; assert.equal(cl.country, 'US');
  assert.equal((await c.post('/api/admin/clients', { kind: 'empresa', display_name: 'X', doc_type: 'RUC', doc_number: '20100047218', country: 'US' })).status, 400, 'RUC solo con país Perú');

  r = await c.post('/api/admin/licenses', { client_id: cl.id, plan_id: cat.plan.id, start: 'cobro' });
  let inv = r.json.invoice;
  assert.equal(inv.tax_operation, 'no_domiciliado'); assert.equal(inv.amount_cents, 15000); assert.equal(inv.tax_cents, 2288);
  assert.ok((await c.get('/api/admin/system')).json.warnings.some((w) => /Registro de Exportadores/.test(w)));

  h.hub.settings.set('tax', { regime: 'mype', export_registered: true });
  const page = await (await fetch(h.base + '/p/' + inv.pay_url.split('/p/')[1])).text(); // abrir el enlace recalcula
  assert.match(page, /exportación de servicios/i); assert.match(page, /S\/ 127\.12/);
  inv = (await c.get('/api/admin/invoices/' + inv.id)).json.invoice;
  assert.equal(inv.tax_treatment, 'exportacion'); assert.equal(inv.amount_cents, 12712); assert.equal(inv.tax_cents, 0); assert.equal(inv.fiscal_doc, 'factura');

  const pay = await new Client(h.base).post(`/v1/public/pay/${inv.pay_url.split('/p/')[1]}/card`, { token: 'tkn_ok_1234567', email: 'ap@barber.co' });
  assert.equal(pay.status, 200, pay.text);
  await emit(h);
  const doc = (await c.get('/api/admin/fiscal-documents')).json.documents[0];
  assert.equal(doc.operation, 'exportacion'); assert.equal(doc.tax_cents, 0); assert.equal(doc.total_cents, 12712); assert.equal(doc.status, 'aceptado');
  assert.equal(h.hub.einvoice.provider.calls.pop().customer.doc_type, 'EXT');
});

test('factura sin dirección fiscal: queda con error claro; al corregir al cliente, se reintenta con los datos nuevos', async (t) => {
  const { h, c, cat } = await world(t);
  enable(h);
  let r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' });
  const token = r.json.invoice.pay_url.split('/p/')[1];
  await new Client(h.base).post(`/v1/public/pay/${token}/card`, { token: 'tkn_ok_1234567', email: 'luis@doncorte.pe' });
  await emit(h);
  let doc = (await c.get('/api/admin/fiscal-documents?status=problemas')).json.documents[0];
  assert.equal(doc.status, 'error'); assert.match(doc.last_error, /dirección fiscal/);
  assert.equal((await c.get('/api/admin/licenses/' + r.json.license.id)).json.license.status, 'activa', 'un problema del comprobante no frena la licencia');
  assert.equal((await c.post(`/api/admin/fiscal-documents/${doc.id}/retry`)).status, 400, 'sin corregir, no reintenta');
  const cl = (await c.get('/api/admin/clients/' + cat.client.id)).json.client;
  await c.put('/api/admin/clients/' + cl.id, Object.assign({}, cl, { address: 'Calle Lima 456, Ica', version: cl.version }));
  r = await c.post(`/api/admin/fiscal-documents/${doc.id}/retry`); assert.equal(r.status, 200, r.text);
  await emit(h);
  doc = (await c.get('/api/admin/fiscal-documents/' + doc.id)).json.document;
  assert.equal(doc.status, 'aceptado'); assert.equal(doc.customer.address, 'Calle Lima 456, Ica'); assert.equal(doc.doc, 'F001-00000001', 'conserva su número');
});

test('proveedor caído: se reintenta con espera y consulta antes de reenviar (no duplica); pago parcial lleva su propio comprobante', async (t) => {
  const { h, c } = await world(t);
  enable(h);
  const cl = (await c.post('/api/admin/clients', { kind: 'persona', display_name: 'Ana Ruiz', legal_name: 'Ana Ruiz Pérez', doc_type: 'DNI', doc_number: '45678912', email: 'ana@mail.pe' })).json.client;
  const inv = (await c.post('/api/admin/invoices', { client_id: cl.id, kind: 'implementacion', description: 'Implementación', amount: '300' })).json.invoice;
  assert.equal(inv.fiscal_doc, 'boleta'); assert.equal(inv.amount_cents, 30000);
  const prov = h.hub.einvoice.provider; prov.mode = 'caido';
  const r = await c.post('/api/admin/payments', { invoice_id: inv.id, method: 'yape', amount: '100', operation_ref: '7788991', approve: true });
  assert.equal(r.status, 201, r.text);
  await emit(h);
  let doc = h.hub.db.get('SELECT * FROM fiscal_documents');
  assert.equal(doc.status, 'pendiente'); assert.equal(doc.attempts, 1); assert.ok(doc.next_attempt_at > new Date().toISOString(), 'espera antes del reintento');
  assert.equal(doc.kind, 'boleta'); assert.equal(doc.total_cents, 10000); assert.equal(doc.subtotal_cents + doc.tax_cents, 10000);
  // el intento anterior SÍ llegó al proveedor aunque no hubo respuesta: al reintentar, se encuentra y no se duplica
  prov.mode = 'ok'; await prov.send(h.hub.einvoice.payloadOf(Object.assign({}, doc, { issue_date: '2026-10-19' })));
  const before = prov.calls.length;
  await h.hub.einvoice.run(Date.now() + 3600e3);
  doc = h.hub.db.get('SELECT * FROM fiscal_documents');
  assert.equal(doc.status, 'aceptado'); assert.equal(prov.calls.length, before, 'no se volvió a enviar');
});

test('Nuevo RUS: no se cobra IGV y la boleta queda fuera del Hub', async (t) => {
  const { h, c, cat } = await world(t);
  h.hub.settings.set('tax', { regime: 'nrus', export_registered: false });
  const r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'cobro' });
  assert.equal(r.json.invoice.amount_cents, 15000); assert.equal(r.json.invoice.tax_cents, 0); assert.equal(r.json.invoice.tax_operation, 'nrus');
  const cat2 = await c.get('/v1/public/catalog'); assert.equal(cat2.json.igv_rate_bp, 0);
});

test('reglas de impuesto: nueva tasa con vigencia cierra la anterior; el IGV no se puede quedar sin regla', async (t) => {
  const { h, c, u } = await world(t);
  h.hub.db.run('UPDATE sessions SET sudo_until = NULL');
  assert.equal((await c.post('/api/admin/tax-rules', { country: 'PE', code: 'PE-IGV', label: 'IGV', rate: '16', valid_from: '2030-01-01' })).status, 403, 'pide 2FA');
  await sudo(h, c, u);
  let r = await c.post('/api/admin/tax-rules', { country: 'PE', code: 'PE-IGV', label: 'IGV', rate: '16', valid_from: '2030-01-01', note: 'Supuesto de prueba' });
  assert.equal(r.status, 201, r.text);
  const rules = (await c.get('/api/admin/tax-rules')).json.rules.filter((x) => x.country === 'PE');
  assert.equal(rules.find((x) => x.rate_bp === 1800).valid_to, '2029-12-31');
  assert.equal(h.hub.tax.rule('PE', { date: '2029-12-31' }).rate_bp, 1800);
  assert.equal(h.hub.tax.rule('PE', { date: '2030-01-01' }).rate_bp, 1600);
  r = await c.post(`/api/admin/tax-rules/${r.json.rule.id}/close`, { valid_to: '2031-01-01' });
  assert.equal(r.status, 409);
});

/* ------------------------------------------------------------ Merchant of Record */
const paddleSig = (body, secret = PADDLE, ts = Math.floor(Date.now() / 1000)) => `ts=${ts};h1=${crypto.createHmac('sha256', secret).update(ts + ':' + body).digest('hex')}`;
const hook = (h, provider, body, headers) => fetch(h.base + '/webhooks/mor/' + provider, { method: 'POST', headers: Object.assign({ 'Content-Type': 'application/json' }, headers), body }).then(async (r) => ({ status: r.status, json: await r.json() }));

test('Paddle: firma, idempotencia, pago → licencia activa sin comprobante propio, reembolso revierte, licencia ajena se rechaza', async (t) => {
  const { h, c, cat } = await world(t);
  enable(h);
  let r = await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, instance_id: cat.instance.id, tenant_ref: 'don-corte', billing_provider: 'paddle', start: 'pendiente' });
  const lic = r.json.license; assert.equal(lic.billing_provider, 'paddle');
  assert.equal((await c.post(`/api/admin/licenses/${lic.id}/activate`, { mode: 'cobro' })).status, 409, 'la cobra Paddle, no el Hub');
  const other = (await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, start: 'pendiente' })).json.license; // cobrada por el Hub

  const txn = (id, code, total = 5900, tax = 900) => JSON.stringify({ event_id: 'evt_' + id, event_type: 'transaction.completed', occurred_at: new Date().toISOString(),
    data: { id: 'txn_' + id, subscription_id: 'sub_01', customer_id: 'ctm_01', currency_code: 'USD', origin: 'web', custom_data: { solvex_license: code }, details: { totals: { subtotal: String(total - tax), tax: String(tax), total: String(total) } } } });

  let body = txn('A1', lic.code);
  r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body, 'otro-secreto-cualquiera-123') }); assert.equal(r.status, 401);
  r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body, PADDLE, Math.floor(Date.now() / 1000) - 900) }); assert.equal(r.status, 401, 'aviso viejo (repetición) rechazado');
  r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body) }); assert.equal(r.status, 200); assert.equal(r.json.outcome, 'aplicado');
  r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body) }); assert.equal(r.json.outcome, 'duplicado');

  let L = (await c.get('/api/admin/licenses/' + lic.id)).json;
  assert.equal(L.license.status, 'activa'); assert.equal(L.license.external_subscription_id, 'sub_01');
  assert.equal(L.payments.length, 1); assert.equal(L.payments[0].method, 'mor'); assert.equal(L.payments[0].currency, 'USD');
  const inv = L.invoices[0]; assert.equal(inv.tax_treatment, 'mor'); assert.equal(inv.currency, 'USD'); assert.equal(inv.tax_cents, 900); assert.equal(inv.subtotal_cents, 5000);
  await emit(h);
  assert.equal(h.hub.db.get('SELECT COUNT(*) n FROM fiscal_documents').n, 0, 'al cliente final le factura el MoR');

  // una licencia que no está configurada para Paddle no se mueve aunque el checkout la nombre
  body = txn('B2', other.code);
  r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body) }); assert.equal(r.json.outcome, 'licencia_no_configurada');
  assert.equal((await c.get('/api/admin/licenses/' + other.id)).json.license.status, 'pendiente');

  // reembolso que llega antes que su pago → 503 para que Paddle reintente
  const adj = (id, txnId) => JSON.stringify({ event_id: 'evt_adj' + id, event_type: 'adjustment.created', data: { id: 'adj_' + id, action: 'refund', status: 'approved', transaction_id: txnId, currency_code: 'USD', totals: { total: '5900' } } });
  body = adj('1', 'txn_ZZ'); r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body) }); assert.equal(r.status, 503);
  body = adj('2', 'txn_A1'); r = await hook(h, 'paddle', body, { 'Paddle-Signature': paddleSig(body) }); assert.equal(r.json.outcome, 'reembolsado');
  L = (await c.get('/api/admin/licenses/' + lic.id)).json;
  assert.equal(L.payments[0].status, 'reembolsado'); assert.equal(L.license.status, 'suspendida', 'sin el pago, la licencia se corta');
});

test('Lemon Squeezy: firma X-Signature; order_created de una suscripción no se cuenta dos veces', async (t) => {
  const { h, c, cat } = await world(t);
  const lic = (await c.post('/api/admin/licenses', { client_id: cat.client.id, plan_id: cat.plan.id, billing_provider: 'lemonsqueezy', start: 'pendiente' })).json.license;
  const sign = (b) => crypto.createHmac('sha256', LEMON).update(b).digest('hex');
  const order = JSON.stringify({ meta: { event_name: 'order_created', custom_data: { solvex_license: lic.code } }, data: { type: 'orders', id: '901', attributes: { status: 'paid', total: 2900, tax: 0, currency: 'USD', created_at: '2026-10-19T10:00:00Z' } } });
  let r = await hook(h, 'lemonsqueezy', order, { 'X-Signature': sign(order) }); assert.equal(r.json.outcome, 'ignorado');
  const inv = JSON.stringify({ meta: { event_name: 'subscription_payment_success', custom_data: { solvex_license: lic.code } }, data: { type: 'subscription-invoices', id: '55', attributes: { status: 'paid', subscription_id: 77, customer_id: 88, total: 2900, tax: 0, currency: 'USD', billing_reason: 'initial', user_email: 'luis@doncorte.pe', created_at: '2026-10-19T10:00:00Z', updated_at: '2026-10-19T10:00:01Z' } } });
  r = await hook(h, 'lemonsqueezy', inv, { 'X-Signature': sign(inv).replace(/.$/, (x) => (x === '0' ? '1' : '0')) }); assert.equal(r.status, 401);
  r = await hook(h, 'lemonsqueezy', inv, { 'X-Signature': sign(inv) }); assert.equal(r.json.outcome, 'aplicado');
  assert.equal((await c.get('/api/admin/licenses/' + lic.id)).json.license.status, 'activa');
  assert.equal(h.hub.db.get("SELECT COUNT(*) n FROM payments WHERE method = 'mor'").n, 1);
  assert.equal((await hook(h, 'stripe', inv, {})).status, 404, 'proveedor sin secreto configurado: no existe');
});

/* ------------------------------------------------------------ actualización de una base existente */
test('migración v1 → v2: conserva clientes y pagos, desglosa los cobros antiguos y mantiene las llaves foráneas', () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'slx-')), 'hub.db');
  const raw = new DatabaseSync(file);
  raw.exec(migrations[0]); raw.exec('PRAGMA user_version = 1');
  const now = new Date().toISOString();
  raw.prepare("INSERT INTO clients (id,code,kind,display_name,doc_type,doc_number_enc,doc_bidx,created_at,updated_at) VALUES ('cli_1','CLI-0001','empresa','Don Corte','RUC','x','b1',?,?)").run(now, now);
  raw.prepare("INSERT INTO clients (id,code,kind,display_name,doc_type,doc_number_enc,doc_bidx,created_at,updated_at) VALUES ('cli_2','CLI-0002','persona','Ana','DNI','x','b2',?,?)").run(now, now);
  raw.prepare("INSERT INTO invoices (id,number,client_id,kind,description,amount_cents,paid_cents,status,created_by,created_at) VALUES ('inv_1','C-000001','cli_1','otro','Algo',15000,15000,'pagada','t',?)").run(now);
  raw.prepare("INSERT INTO invoices (id,number,client_id,kind,description,amount_cents,status,created_by,created_at) VALUES ('inv_2','C-000002','cli_2','otro','Algo',9900,'pendiente','t',?)").run(now);
  raw.prepare("INSERT INTO payments (id,number,invoice_id,client_id,method,source,amount_cents,status,operation_ref,operation_norm,created_at,updated_at) VALUES ('pay_1','R-000001','inv_1','cli_1','culqi','pasarela',15000,'aprobado','chr_1','CHR1',?,?)").run(now, now);
  raw.close();

  const db = new Db(file);
  assert.equal(db.get('PRAGMA user_version').user_version, migrations.length);
  assert.equal(db.get('PRAGMA foreign_keys').foreign_keys, 1);
  assert.equal(db.get("SELECT country FROM clients WHERE id = 'cli_1'").country, 'PE');
  const i1 = db.get("SELECT * FROM invoices WHERE id = 'inv_1'");
  assert.deepEqual([i1.subtotal_cents, i1.tax_cents, i1.fiscal_doc], [12712, 2288, 'factura']);
  assert.equal(db.get("SELECT fiscal_doc FROM invoices WHERE id = 'inv_2'").fiscal_doc, 'boleta');
  const p = db.get("SELECT * FROM payments WHERE id = 'pay_1'"); assert.equal(p.provider, 'culqi'); assert.equal(p.status, 'aprobado');
  assert.throws(() => db.run("UPDATE payments SET amount_cents = 1 WHERE id = 'pay_1'"), /pago cerrado/, 'el candado de pagos sigue activo');
  assert.throws(() => db.run("INSERT INTO payments (id,client_id,method,source,amount_cents,status,created_at,updated_at) VALUES ('pay_x','cli_nada','yape','panel',1,'por_verificar','x','x')"), /FOREIGN KEY/);
  db.close();
});
