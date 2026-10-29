// Integración real: Solvex Hub (en memoria) ⇄ cliente de licencias de FacturaVoz (src/lib/solvex.ts compilado).
process.chdir('/home/claude/hub_src/solvex-plataforma/hub');
const { startHub, makeUser, login, sudo } = require('/home/claude/hub_src/solvex-plataforma/hub/test/helpers.js');
const crypto = require('node:crypto');
(async () => {
  const h = await startHub();
  const u = await makeUser(h.hub);
  const c = await login(h, u);
  const p = await c.post('/api/admin/products', { code: 'FACTURAVOZ', name: 'FacturaVoz', kind: 'saas', public: true, feature_keys: [] });
  if (p.status !== 201) throw new Error(p.text); const pid = p.json.product.id;
  await c.post(`/api/admin/products/${pid}/plans`, { code: 'EMPRESA', name: 'Empresa', interval_unit: 'month', interval_count: 1, price: '119', trial_days: 3, grace_days: 5, public: true, features: { copiloto: true, max_users: -1 } });
  await sudo(h, c, u);
  const ins = await c.post('/api/admin/instances', { product_id: pid, name: 'FacturaVoz prod', environment: 'produccion', webhook_url: 'http://localhost:9999/api/solvex/webhook' });
  if (ins.status !== 201) throw new Error('instancia: ' + ins.text);
  const { hubConfig, requestTrial, syncAll, verifyWebhook } = await import('/home/claude/work/vt/out/src/lib/solvex.js');
  Object.assign(process.env, { NODE_ENV: 'development', SOLVEX_HUB_URL: h.base, SOLVEX_API_KEY: ins.json.apiKey, SOLVEX_INSTANCE_ID: ins.json.instance.id, SOLVEX_WEBHOOK_SECRET: ins.json.webhookSecret });
  const cfg = hubConfig();
  console.log('config ok:', !!cfg, '(llaves desde /.well-known)');
  const org = crypto.randomUUID();
  const r = await requestTrial(cfg, { tenant: org, ruc: '20100047218', businessName: 'Bodega Demo' });
  console.log('trial:', r.status, r.data && r.data.payload.status, r.data && r.data.payload.mode, r.data && r.data.payload.plan);
  const again = await requestTrial(cfg, { tenant: crypto.randomUUID(), ruc: '20100047218', businessName: 'Otra' });
  console.log('mismo RUC, otra empresa:', again.status);
  const s = await syncAll(cfg);
  console.log('sync:', s.ok.length, 'licencia(s), tenant coincide:', s.ok[0].tenant === org, 'tokens malos:', s.bad);
  // Webhook real que el Hub enviaría (despachador del outbox con fetch simulado)
  await new Promise((r) => setImmediate(r)); await h.hub.outbox.run();
  const hook = h.fetchImpl.calls.filter((x) => /webhook/.test(x.url)).pop();
  console.log('webhook del Hub verificado por FacturaVoz:', verifyWebhook({ secret: cfg.webhookSecret, timestamp: hook.headers['Solvex-Timestamp'], signature: hook.headers['Solvex-Signature'], rawBody: hook.opts.body }));
  await h.stop(); process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
