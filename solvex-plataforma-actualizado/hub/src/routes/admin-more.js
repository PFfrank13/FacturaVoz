'use strict';
/** API del panel: catálogo, integraciones, comercial, soporte, finanzas, reclamos, equipo, auditoría y configuración. */
const v = require('../lib/validate');
const T = require('../lib/time');
const C = require('../lib/crypto');
const jws = require('../lib/jws');
const sec = require('../http/security');
const { HttpError } = require('../http/app');
const { U, actor, page } = require('./_admin');
const { ROLES } = require('../services/auth');

module.exports = (app, s) => {
  const { db, vault, audit, config, bus } = s;
  const now = () => T.nowIso();

  /* ------------------------------------------------------------ productos y planes */
  const planOut = (p) => Object.assign({}, p, { features: JSON.parse(p.features || '{}'), public: !!p.public, active: !!p.active });
  const prodOut = (p) => Object.assign({}, p, { feature_keys: JSON.parse(p.feature_keys || '[]'), public: !!p.public,
    plans: db.all('SELECT * FROM plans WHERE product_id = ? ORDER BY price_cents', p.id).map(planOut),
    licenses: db.get("SELECT COUNT(*) n FROM licenses WHERE product_id = ? AND status IN ('prueba','activa','gracia')", p.id).n,
    instances: db.get('SELECT COUNT(*) n FROM instances WHERE product_id = ?', p.id).n });

  app.get('/api/admin/products', ...U(s, { perm: 'licenses.view' }), (ctx) => ctx.ok({ products: db.all('SELECT * FROM products ORDER BY created_at').map(prodOut) }));

  const prodSchema = {
    code: v.str({ min: 2, max: 30, pattern: /^[A-Z][A-Z0-9_]{1,29}$/ }), name: v.str({ min: 2, max: 80 }), kind: v.oneOf(['saas', 'instalable', 'a_medida']),
    status: v.oneOf(['borrador', 'activo', 'retirado'], { default: 'activo' }), description: v.str({ max: 500, optional: true, multiline: true }),
    feature_keys: v.arrayOf(v.str({ min: 2, max: 40, pattern: /^[a-z][a-z0-9_]{1,39}$/ }), { max: 40, optional: true }), public: v.bool({ default: false }),
  };
  app.post('/api/admin/products', ...U(s, { perm: 'products.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), prodSchema), id = C.newId('prd');
    db.tx(() => {
      db.run('INSERT INTO products (id,code,name,kind,status,description,feature_keys,public,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)', id, b.code, b.name, b.kind, b.status, b.description, JSON.stringify(b.feature_keys || []), b.public ? 1 : 0, now(), now());
      audit.log({ actor: actor(ctx), action: 'producto.creado', entity: ['product', id], ip: ctx.ip, data: { code: b.code } });
    });
    ctx.send(201, { product: prodOut(db.get('SELECT * FROM products WHERE id = ?', id)) });
  });
  app.put('/api/admin/products/:id', ...U(s, { perm: 'products.manage' }), async (ctx) => {
    const p = db.get('SELECT * FROM products WHERE id = ?', ctx.params.id); if (!p) throw new HttpError(404, 'NO_ENCONTRADO', 'Producto no encontrado.');
    const b = v.parse(Object.assign({ code: p.code }, await ctx.json()), prodSchema);
    if (b.kind !== p.kind && db.get('SELECT 1 FROM licenses WHERE product_id = ?', p.id)) throw new HttpError(409, 'EN_USO', 'No se cambia el tipo de un producto con licencias.');
    db.tx(() => {
      db.run('UPDATE products SET name=?, kind=?, status=?, description=?, feature_keys=?, public=?, updated_at=? WHERE id=?', b.name, b.kind, b.status, b.description, JSON.stringify(b.feature_keys || []), b.public ? 1 : 0, now(), p.id);
      audit.log({ actor: actor(ctx), action: 'producto.editado', entity: ['product', p.id], ip: ctx.ip });
    });
    ctx.ok({ product: prodOut(db.get('SELECT * FROM products WHERE id = ?', p.id)) });
  });

  const planSchema = {
    code: v.str({ min: 2, max: 30, pattern: /^[A-Z0-9][A-Z0-9_-]{1,29}$/ }), name: v.str({ min: 2, max: 80 }),
    interval_unit: v.oneOf(['day', 'month', 'year', 'none']), interval_count: v.int({ min: 1, max: 3650, default: 1 }),
    price: v.money(), setup: v.money({ default: 0 }), trial_days: v.int({ min: 0, max: 365, default: 0 }), grace_days: v.int({ min: 0, max: 90, default: 5 }),
    features: v.features(), public: v.bool({ default: false }), active: v.bool({ default: true }),
    tax_mode: v.oneOf(['incluido', 'mas_impuesto'], { default: 'incluido' }),
  };
  app.post('/api/admin/products/:id/plans', ...U(s, { perm: 'products.manage' }), async (ctx) => {
    const p = db.get('SELECT * FROM products WHERE id = ?', ctx.params.id); if (!p) throw new HttpError(404, 'NO_ENCONTRADO', 'Producto no encontrado.');
    const b = v.parse(await ctx.json(), planSchema), id = C.newId('pln');
    db.tx(() => {
      db.run(`INSERT INTO plans (id,product_id,code,name,interval_unit,interval_count,price_cents,setup_cents,trial_days,grace_days,features,public,active,tax_mode,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, id, p.id, b.code, b.name, b.interval_unit, b.interval_count, b.price, b.setup || 0, b.trial_days, b.grace_days, JSON.stringify(b.features || {}), b.public ? 1 : 0, b.active ? 1 : 0, b.tax_mode, now(), now());
      audit.log({ actor: actor(ctx), action: 'plan.creado', entity: ['plan', id], ip: ctx.ip, data: { product: p.code, code: b.code, price_cents: b.price } });
    });
    ctx.send(201, { plan: planOut(db.get('SELECT * FROM plans WHERE id = ?', id)) });
  });
  app.put('/api/admin/plans/:id', ...U(s, { perm: 'products.manage' }), async (ctx) => {
    const pl = db.get('SELECT * FROM plans WHERE id = ?', ctx.params.id); if (!pl) throw new HttpError(404, 'NO_ENCONTRADO', 'Plan no encontrado.');
    const b = v.parse(Object.assign({ code: pl.code }, await ctx.json()), planSchema);
    const used = db.get('SELECT 1 FROM licenses WHERE plan_id = ?', pl.id);
    if (used && (b.interval_unit !== pl.interval_unit || b.interval_count !== pl.interval_count)) throw new HttpError(409, 'EN_USO', 'El plan tiene licencias: crea un plan nuevo en lugar de cambiar su periodo.');
    db.tx(() => {
      db.run('UPDATE plans SET name=?, interval_unit=?, interval_count=?, price_cents=?, setup_cents=?, trial_days=?, grace_days=?, features=?, public=?, active=?, tax_mode=?, updated_at=? WHERE id=?',
        b.name, b.interval_unit, b.interval_count, b.price, b.setup || 0, b.trial_days, b.grace_days, JSON.stringify(b.features || {}), b.public ? 1 : 0, b.active ? 1 : 0, b.tax_mode, now(), pl.id);
      audit.log({ actor: actor(ctx), action: 'plan.editado', entity: ['plan', pl.id], ip: ctx.ip, data: { price_cents: b.price, nota: 'Las licencias existentes conservan su precio' } });
    });
    ctx.ok({ plan: planOut(db.get('SELECT * FROM plans WHERE id = ?', pl.id)) });
  });

  /* ------------------------------------------------------------ instancias (integraciones) */
  const instOut = (i) => ({
    id: i.id, product_id: i.product_id, product: db.get('SELECT code, name FROM products WHERE id = ?', i.product_id), name: i.name, environment: i.environment,
    webhook_url: i.webhook_url, api_key_prefix: i.api_key_prefix, allowed_ips: i.allowed_ips, status: i.status, last_seen_at: i.last_seen_at, last_seen_ip: i.last_seen_ip, app_version: i.app_version,
    created_at: i.created_at, licenses: db.get('SELECT COUNT(*) n FROM licenses WHERE instance_id = ?', i.id).n,
    deliveries: db.get("SELECT SUM(status='pendiente') pending, SUM(status='fallido') failed, SUM(status='entregado') ok FROM deliveries WHERE instance_id = ?", i.id),
  });
  const instSchema = {
    product_id: v.id('prd'), name: v.str({ min: 3, max: 80 }), environment: v.oneOf(['produccion', 'pruebas'], { default: 'produccion' }),
    webhook_url: v.url({ optional: true, allowHttpLocal: config.dev }), allowed_ips: v.str({ max: 500, optional: true, pattern: /^[0-9a-fA-F:.,/\s]*$/ }),
  };
  const checkWebhook = (url) => {
    if (!url || config.dev) return;
    if (!sec.isPublicHost(new URL(url).hostname)) throw new v.ValidationError('webhook_url', 'La URL apunta a una red privada.');
  };
  const newApiKey = () => { const pre = C.randomCode(8).toLowerCase(); return { key: `slxk_${pre}_${C.newSecret(32)}`, prefix: `slxk_${pre}` }; };

  app.get('/api/admin/instances', ...U(s, { perm: 'licenses.view' }), (ctx) => ctx.ok({ instances: db.all('SELECT * FROM instances ORDER BY created_at').map(instOut), keys: s.licenses.publicKeys(), hub_url: config.publicUrl }));

  app.post('/api/admin/instances', ...U(s, { perm: 'instances.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), instSchema); checkWebhook(b.webhook_url);
    if (!db.get('SELECT 1 FROM products WHERE id = ?', b.product_id)) throw new v.ValidationError('product_id', 'Producto no válido.');
    const id = C.newId('ins'), k = newApiKey(), wsec = 'whsec_' + C.newSecret(32);
    db.tx(() => {
      db.run(`INSERT INTO instances (id,product_id,name,environment,webhook_url,webhook_secret_enc,api_key_hash,api_key_prefix,allowed_ips,status,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?,?, 'activa', ?, ?)`, id, b.product_id, b.name, b.environment, b.webhook_url, vault.encrypt(wsec, 'instances.webhook_secret:' + id), C.sha256(k.key), k.prefix, (b.allowed_ips || '').replace(/\s/g, ''), now(), now());
      audit.log({ actor: actor(ctx), action: 'instancia.creada', entity: ['instance', id], ip: ctx.ip, data: { name: b.name } });
    });
    ctx.send(201, { instance: instOut(db.get('SELECT * FROM instances WHERE id = ?', id)), apiKey: k.key, webhookSecret: wsec });
  });

  app.put('/api/admin/instances/:id', ...U(s, { perm: 'instances.manage' }), async (ctx) => {
    const i = db.get('SELECT * FROM instances WHERE id = ?', ctx.params.id); if (!i) throw new HttpError(404, 'NO_ENCONTRADO', 'Instancia no encontrada.');
    const b = v.parse(Object.assign({ product_id: i.product_id }, await ctx.json()), Object.assign({}, instSchema, { status: v.oneOf(['activa', 'pausada', 'revocada'], { default: i.status }) }));
    checkWebhook(b.webhook_url);
    if (i.status === 'revocada' && b.status !== 'revocada') throw new HttpError(409, 'REVOCADA', 'Una instancia revocada no se reactiva: crea otra.');
    db.tx(() => {
      db.run('UPDATE instances SET name=?, environment=?, webhook_url=?, allowed_ips=?, status=?, updated_at=? WHERE id=?', b.name, b.environment, b.webhook_url, (b.allowed_ips || '').replace(/\s/g, ''), b.status, now(), i.id);
      audit.log({ actor: actor(ctx), action: 'instancia.editada', entity: ['instance', i.id], ip: ctx.ip, data: { status: b.status } });
    });
    ctx.ok({ instance: instOut(db.get('SELECT * FROM instances WHERE id = ?', i.id)) });
  });

  app.post('/api/admin/instances/:id/rotate', ...U(s, { perm: 'instances.manage', sudo: true }), async (ctx) => {
    const i = db.get('SELECT * FROM instances WHERE id = ?', ctx.params.id); if (!i) throw new HttpError(404, 'NO_ENCONTRADO', 'Instancia no encontrada.');
    const b = v.parse(await ctx.json(), { what: v.oneOf(['api_key', 'webhook_secret']) });
    const out = {};
    db.tx(() => {
      if (b.what === 'api_key') { const k = newApiKey(); db.run('UPDATE instances SET api_key_hash = ?, api_key_prefix = ?, updated_at = ? WHERE id = ?', C.sha256(k.key), k.prefix, now(), i.id); out.apiKey = k.key; }
      else { const w = 'whsec_' + C.newSecret(32); db.run('UPDATE instances SET webhook_secret_enc = ?, updated_at = ? WHERE id = ?', vault.encrypt(w, 'instances.webhook_secret:' + i.id), now(), i.id); out.webhookSecret = w; }
      audit.log({ actor: actor(ctx), action: 'instancia.secreto_rotado', entity: ['instance', i.id], ip: ctx.ip, data: { what: b.what } });
    });
    ctx.ok(out);
  });

  app.post('/api/admin/instances/:id/ping', ...U(s, { perm: 'instances.manage' }), (ctx) => {
    const i = db.get('SELECT * FROM instances WHERE id = ?', ctx.params.id); if (!i) throw new HttpError(404, 'NO_ENCONTRADO', 'Instancia no encontrada.');
    if (!i.webhook_url) throw new HttpError(400, 'SIN_URL', 'La instancia no tiene URL de webhook.');
    ctx.ok({ event: s.outbox.ping(i) });
  });

  app.post('/api/admin/instances/:id/resync', ...U(s, { perm: 'instances.manage' }), (ctx) => {
    const i = db.get('SELECT * FROM instances WHERE id = ?', ctx.params.id); if (!i) throw new HttpError(404, 'NO_ENCONTRADO', 'Instancia no encontrada.');
    let n = 0; db.tx(() => { for (const l of db.all('SELECT * FROM licenses WHERE instance_id = ?', i.id)) { s.outbox.licenseChanged(l, 'resincronización'); n++; } audit.log({ actor: actor(ctx), action: 'instancia.resincronizada', entity: ['instance', i.id], ip: ctx.ip, data: { n } }); });
    ctx.ok({ queued: n });
  });

  app.get('/api/admin/deliveries', ...U(s, { perm: 'licenses.view' }), (ctx) => {
    const st = ctx.query.get('status') || '', inst = ctx.query.get('instance') || '';
    const w = [], p = []; if (st) { w.push('d.status = ?'); p.push(st); } if (inst) { w.push('d.instance_id = ?'); p.push(inst); }
    ctx.ok({ deliveries: db.all(`SELECT d.*, o.topic, l.code license_code, l.label, i.name instance_name FROM deliveries d JOIN outbox o ON o.id = d.event_id LEFT JOIN licenses l ON l.id = o.license_id LEFT JOIN instances i ON i.id = d.instance_id ${w.length ? 'WHERE ' + w.join(' AND ') : ''} ORDER BY d.id DESC LIMIT 200`, ...p) });
  });
  app.post('/api/admin/deliveries/:id/retry', ...U(s, { perm: 'instances.manage' }), (ctx) => { s.outbox.retry(Number(ctx.params.id)); s.outbox.kick(); ctx.ok(); });

  /* ------------------------------------------------------------ solicitudes (leads) */
  const leadOut = (l) => ({ id: l.id, name: l.name_enc ? vault.decrypt(l.name_enc, 'leads.name:' + l.id) : '', business: l.business, sector: l.sector, branches: l.branches,
    contact: vault.decrypt(l.contact_enc, 'leads.contact:' + l.id), message: l.message_enc ? vault.decrypt(l.message_enc, 'leads.message:' + l.id) : '',
    status: l.status, source: l.source, client_id: l.client_id, created_at: l.created_at, updated_at: l.updated_at });
  app.get('/api/admin/leads', ...U(s, { perm: 'leads.manage' }), (ctx) => {
    const st = ctx.query.get('status') || '';
    ctx.ok({ leads: db.all(`SELECT * FROM leads ${st ? 'WHERE status = ?' : "WHERE status <> 'spam'"} ORDER BY created_at DESC LIMIT 300`, ...(st ? [st] : [])).map(leadOut) });
  });
  app.put('/api/admin/leads/:id', ...U(s, { perm: 'leads.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { status: v.oneOf(['nuevo', 'contactado', 'demo', 'cotizado', 'ganado', 'perdido', 'spam']), client_id: v.id('cli', { optional: true }) });
    const l = db.get('SELECT * FROM leads WHERE id = ?', ctx.params.id); if (!l) throw new HttpError(404, 'NO_ENCONTRADO', 'Solicitud no encontrada.');
    db.tx(() => { db.run('UPDATE leads SET status = ?, client_id = COALESCE(?, client_id), updated_at = ? WHERE id = ?', b.status, b.client_id, now(), l.id); audit.log({ actor: actor(ctx), action: 'solicitud.estado', entity: ['lead', l.id], ip: ctx.ip, data: { status: b.status } }); });
    ctx.ok({ lead: leadOut(db.get('SELECT * FROM leads WHERE id = ?', l.id)) });
  });

  /* ------------------------------------------------------------ soporte */
  const ticketOut = (t) => ({ ...t, client: t.client_id ? db.get('SELECT id, code, display_name name FROM clients WHERE id = ?', t.client_id) : null,
    license: t.license_id ? db.get('SELECT id, code, label FROM licenses WHERE id = ?', t.license_id) : null, assignee: t.assignee_id ? db.get('SELECT id, name FROM users WHERE id = ?', t.assignee_id) : null });
  app.get('/api/admin/tickets', ...U(s, { perm: 'tickets.manage' }), (ctx) => {
    const st = ctx.query.get('status') || '';
    ctx.ok({ tickets: db.all(`SELECT * FROM tickets ${st === 'abiertos' ? "WHERE status IN ('abierto','en_curso')" : st ? 'WHERE status = ?' : ''} ORDER BY CASE priority WHEN 'alta' THEN 0 WHEN 'media' THEN 1 ELSE 2 END, created_at DESC LIMIT 300`, ...(st && st !== 'abiertos' ? [st] : [])).map(ticketOut) });
  });
  app.post('/api/admin/tickets', ...U(s, { perm: 'tickets.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { client_id: v.id('cli', { optional: true }), license_id: v.id('lic', { optional: true }), subject: v.str({ min: 3, max: 160 }), priority: v.oneOf(['alta', 'media', 'baja'], { default: 'media' }), assignee_id: v.id('usr', { optional: true }), note: v.str({ max: 4000, optional: true, multiline: true }) });
    const id = C.newId('tkt');
    db.tx(() => {
      const number = 'T-' + String(db.nextSeq('ticket')).padStart(5, '0');
      db.run("INSERT INTO tickets (id,number,client_id,license_id,subject,priority,status,assignee_id,created_by,created_at,updated_at) VALUES (?,?,?,?,?,?,'abierto',?,?,?,?)", id, number, b.client_id, b.license_id, b.subject, b.priority, b.assignee_id, ctx.state.user.id, now(), now());
      if (b.note) { const nid = C.newId('tkn'); db.run('INSERT INTO ticket_notes (id,ticket_id,user_id,body_enc,created_at) VALUES (?,?,?,?,?)', nid, id, ctx.state.user.id, vault.encrypt(b.note, 'ticket_notes.body:' + nid), now()); }
      audit.log({ actor: actor(ctx), action: 'ticket.creado', entity: ['ticket', id], ip: ctx.ip, data: { number, priority: b.priority } });
    });
    bus.emit('admin', { type: 'ticket', id });
    ctx.send(201, { ticket: ticketOut(db.get('SELECT * FROM tickets WHERE id = ?', id)) });
  });
  app.get('/api/admin/tickets/:id', ...U(s, { perm: 'tickets.manage' }), (ctx) => {
    const t = db.get('SELECT * FROM tickets WHERE id = ?', ctx.params.id); if (!t) throw new HttpError(404, 'NO_ENCONTRADO', 'Ticket no encontrado.');
    ctx.ok({ ticket: ticketOut(t), notes: db.all('SELECT n.*, u.name user FROM ticket_notes n LEFT JOIN users u ON u.id = n.user_id WHERE ticket_id = ? ORDER BY n.created_at', t.id).map((n) => ({ id: n.id, user: n.user, body: vault.decrypt(n.body_enc, 'ticket_notes.body:' + n.id), created_at: n.created_at })) });
  });
  app.put('/api/admin/tickets/:id', ...U(s, { perm: 'tickets.manage' }), async (ctx) => {
    const t = db.get('SELECT * FROM tickets WHERE id = ?', ctx.params.id); if (!t) throw new HttpError(404, 'NO_ENCONTRADO', 'Ticket no encontrado.');
    const b = v.parse(await ctx.json(), { status: v.oneOf(['abierto', 'en_curso', 'resuelto', 'cerrado']), priority: v.oneOf(['alta', 'media', 'baja']), assignee_id: v.id('usr', { optional: true }), note: v.str({ max: 4000, optional: true, multiline: true }) });
    db.tx(() => {
      db.run('UPDATE tickets SET status=?, priority=?, assignee_id=?, updated_at=?, resolved_at = CASE WHEN ? IN (\'resuelto\',\'cerrado\') THEN COALESCE(resolved_at, ?) ELSE NULL END WHERE id=?', b.status, b.priority, b.assignee_id, now(), b.status, now(), t.id);
      if (b.note) { const nid = C.newId('tkn'); db.run('INSERT INTO ticket_notes (id,ticket_id,user_id,body_enc,created_at) VALUES (?,?,?,?,?)', nid, t.id, ctx.state.user.id, vault.encrypt(b.note, 'ticket_notes.body:' + nid), now()); }
      audit.log({ actor: actor(ctx), action: 'ticket.actualizado', entity: ['ticket', t.id], ip: ctx.ip, data: { status: b.status, priority: b.priority, nota: !!b.note } });
    });
    ctx.ok({ ticket: ticketOut(db.get('SELECT * FROM tickets WHERE id = ?', t.id)) });
  });

  /* ------------------------------------------------------------ finanzas (gastos) */
  const expSchema = { concept: v.str({ min: 2, max: 120 }), category: v.oneOf(['Infraestructura', 'Comunicación', 'Marketing', 'Sueldos', 'Herramientas', 'Impuestos', 'Otros']), amount: v.money({ min: 0.01 }), spent_on: v.date(), product_id: v.id('prd', { optional: true }), license_id: v.id('lic', { optional: true }) };
  app.get('/api/admin/expenses', ...U(s, { perm: 'expenses.manage' }), (ctx) => {
    const from = ctx.query.get('from') || T.addDays(T.localDate(Date.now(), config.defaultTimezone), -365);
    ctx.ok({ expenses: db.all('SELECT e.*, p.name product_name, l.code license_code FROM expenses e LEFT JOIN products p ON p.id = e.product_id LEFT JOIN licenses l ON l.id = e.license_id WHERE e.deleted_at IS NULL AND e.spent_on >= ? ORDER BY e.spent_on DESC LIMIT 500', from) });
  });
  app.post('/api/admin/expenses', ...U(s, { perm: 'expenses.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), expSchema), id = C.newId('exp');
    db.tx(() => { db.run('INSERT INTO expenses (id,concept,category,amount_cents,spent_on,product_id,license_id,created_by,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)', id, b.concept, b.category, b.amount, b.spent_on, b.product_id, b.license_id, ctx.state.user.id, now(), now()); audit.log({ actor: actor(ctx), action: 'gasto.registrado', entity: ['expense', id], ip: ctx.ip, data: { amount_cents: b.amount, category: b.category } }); });
    ctx.send(201, { id });
  });
  app.put('/api/admin/expenses/:id', ...U(s, { perm: 'expenses.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), expSchema);
    db.tx(() => { const r = db.run('UPDATE expenses SET concept=?, category=?, amount_cents=?, spent_on=?, product_id=?, license_id=?, updated_at=? WHERE id=? AND deleted_at IS NULL', b.concept, b.category, b.amount, b.spent_on, b.product_id, b.license_id, now(), ctx.params.id); if (!r.changes) throw new HttpError(404, 'NO_ENCONTRADO', 'Gasto no encontrado.'); audit.log({ actor: actor(ctx), action: 'gasto.editado', entity: ['expense', ctx.params.id], ip: ctx.ip, data: { amount_cents: b.amount } }); });
    ctx.ok();
  });
  app.del('/api/admin/expenses/:id', ...U(s, { perm: 'expenses.manage' }), (ctx) => {
    db.tx(() => { db.run('UPDATE expenses SET deleted_at = ? WHERE id = ?', now(), ctx.params.id); audit.log({ actor: actor(ctx), action: 'gasto.eliminado', entity: ['expense', ctx.params.id], ip: ctx.ip }); });
    ctx.ok();
  });
  app.get('/api/admin/finance', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const tz = config.defaultTimezone;
    const rows = db.all(`SELECT p.amount_cents, p.reviewed_at, p.method, pr.name product FROM payments p LEFT JOIN licenses l ON l.id = p.license_id LEFT JOIN products pr ON pr.id = l.product_id
      WHERE p.status = 'aprobado' AND p.currency = 'PEN' AND p.reviewed_at > ?`, T.nowIso(Date.now() - 400 * 864e5));
    const byMonth = {}, byProduct = {}, byMethod = {};
    for (const r of rows) { const m = T.localDate(r.reviewed_at, tz).slice(0, 7); byMonth[m] = (byMonth[m] || 0) + r.amount_cents; byProduct[r.product || 'Otros'] = (byProduct[r.product || 'Otros'] || 0) + r.amount_cents; byMethod[r.method] = (byMethod[r.method] || 0) + r.amount_cents; }
    const exp = {}; for (const e of db.all('SELECT amount_cents, spent_on FROM expenses WHERE deleted_at IS NULL')) { const m = e.spent_on.slice(0, 7); exp[m] = (exp[m] || 0) + e.amount_cents; }
    const expProd = db.all('SELECT COALESCE(p.name, pl.name, \'General\') product, SUM(e.amount_cents) c FROM expenses e LEFT JOIN products p ON p.id = e.product_id LEFT JOIN licenses li ON li.id = e.license_id LEFT JOIN products pl ON pl.id = li.product_id WHERE e.deleted_at IS NULL GROUP BY 1');
    // Ventas según comprobantes emitidos (base e IGV por mes; las notas de crédito restan).
    const taxByMonth = {};
    for (const d of db.all("SELECT kind, subtotal_cents, tax_cents, issue_date FROM fiscal_documents WHERE status IN ('aceptado','enviado') AND issue_date >= ?", T.localDate(Date.now() - 400 * 864e5, tz))) {
      const m = d.issue_date.slice(0, 7), k = d.kind === 'nota_credito' ? -1 : 1; taxByMonth[m] = taxByMonth[m] || { base: 0, igv: 0 }; taxByMonth[m].base += k * d.subtotal_cents; taxByMonth[m].igv += k * d.tax_cents;
    }
    const mor = db.all("SELECT currency, SUM(amount_cents) c, COUNT(*) n FROM payments WHERE status = 'aprobado' AND method = 'mor' GROUP BY currency");
    ctx.ok({ income_by_month: byMonth, expense_by_month: exp, income_by_product: byProduct, income_by_method: byMethod, expense_by_product: expProd, credits_total: db.get('SELECT COALESCE(SUM(amount_cents),0) c FROM credits').c, tax_by_month: taxByMonth, mor_income: mor });
  });

  /* ------------------------------------------------------------ libro de reclamaciones */
  const cmpOut = (c, full) => {
    const o = { id: c.id, number: c.number, kind: c.kind, good_type: c.good_type, amount_cents: c.amount_cents, status: c.status, due_on: c.due_on, responded_at: c.responded_at, created_at: c.created_at };
    if (full) Object.assign(o, { consumer: JSON.parse(vault.decrypt(c.consumer_enc, 'complaints.consumer:' + c.id)), description: vault.decrypt(c.description_enc, 'complaints.description:' + c.id), request: vault.decrypt(c.request_enc, 'complaints.request:' + c.id), response: c.response_enc ? vault.decrypt(c.response_enc, 'complaints.response:' + c.id) : '' });
    else o.consumer_name = JSON.parse(vault.decrypt(c.consumer_enc, 'complaints.consumer:' + c.id)).name;
    return o;
  };
  app.get('/api/admin/complaints', ...U(s, { perm: 'complaints.manage' }), (ctx) => ctx.ok({ complaints: db.all('SELECT * FROM complaints ORDER BY created_at DESC LIMIT 300').map((c) => cmpOut(c, false)) }));
  app.get('/api/admin/complaints/:id', ...U(s, { perm: 'complaints.manage' }), (ctx) => {
    const c = db.get('SELECT * FROM complaints WHERE id = ?', ctx.params.id); if (!c) throw new HttpError(404, 'NO_ENCONTRADO', 'Reclamo no encontrado.');
    if (c.status === 'recibido') db.run("UPDATE complaints SET status = 'en_revision' WHERE id = ?", c.id);
    ctx.ok({ complaint: cmpOut(db.get('SELECT * FROM complaints WHERE id = ?', c.id), true) });
  });
  app.post('/api/admin/complaints/:id/respond', ...U(s, { perm: 'complaints.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { response: v.str({ min: 20, max: 5000, multiline: true }) });
    const c = db.get('SELECT * FROM complaints WHERE id = ?', ctx.params.id); if (!c) throw new HttpError(404, 'NO_ENCONTRADO', 'Reclamo no encontrado.');
    if (c.status === 'respondido') throw new HttpError(409, 'RESPONDIDO', 'Ya fue respondido. La respuesta no se modifica (queda como constancia).');
    const consumer = JSON.parse(vault.decrypt(c.consumer_enc, 'complaints.consumer:' + c.id));
    db.tx(() => {
      db.run("UPDATE complaints SET status = 'respondido', response_enc = ?, responded_at = ?, responded_by = ? WHERE id = ?", vault.encrypt(b.response, 'complaints.response:' + c.id), now(), ctx.state.user.id, c.id);
      s.notifier.queue({ template: 'reclamo_respuesta', client: null, to: { email: consumer.email, name: consumer.name }, channels: ['email'], dedupe: 'reclamo_resp:' + c.id, vars: { tipo: c.kind, numero: c.number, respuesta: b.response } });
      audit.log({ actor: actor(ctx), action: 'reclamo.respondido', entity: ['complaint', c.id], ip: ctx.ip, data: { number: c.number } });
    });
    ctx.ok();
  });

  /* ------------------------------------------------------------ equipo */
  app.get('/api/admin/team', ...U(s, { perm: 'dashboard.view' }), (ctx) => ctx.ok({ users: db.all('SELECT * FROM users ORDER BY created_at').map((u) => s.auth.publicUser(u)), roles: Object.entries(ROLES).map(([k, r]) => ({ key: k, label: r.label, perms: r.perms })) }));
  app.post('/api/admin/team', ...U(s, { perm: 'team.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { email: v.email(), name: v.str({ min: 2, max: 80 }), role: v.oneOf(Object.keys(ROLES)) });
    if (db.get('SELECT 1 FROM users WHERE email = ?', b.email)) throw new HttpError(409, 'DUPLICADO', 'Ya existe un usuario con ese correo.');
    const temp = C.randomCode(4) + '-' + C.randomCode(4) + '-' + C.randomCode(4) + '-' + C.randomCode(4);
    const u = await s.auth.createUser({ email: b.email, name: b.name, role: b.role, password: temp }, actor(ctx), ctx.ip);
    ctx.send(201, { user: s.auth.publicUser(u), tempPassword: temp });
  });
  app.put('/api/admin/team/:id', ...U(s, { perm: 'team.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { role: v.oneOf(Object.keys(ROLES)), active: v.bool(), name: v.str({ min: 2, max: 80 }) });
    const u = db.get('SELECT * FROM users WHERE id = ?', ctx.params.id); if (!u) throw new HttpError(404, 'NO_ENCONTRADO', 'Usuario no encontrado.');
    if (u.role === 'propietario' && u.active && (b.role !== 'propietario' || !b.active) && s.auth.activeOwners() <= 1) throw new HttpError(409, 'ULTIMO_PROPIETARIO', 'Debe quedar al menos un propietario activo.');
    db.tx(() => {
      db.run('UPDATE users SET role = ?, active = ?, name = ?, updated_at = ? WHERE id = ?', b.role, b.active ? 1 : 0, b.name, now(), u.id);
      if (!b.active || b.role !== u.role) s.auth.revokeAllSessions(u.id);
      audit.log({ actor: actor(ctx), action: 'usuario.editado', entity: ['user', u.id], ip: ctx.ip, data: { role: b.role, active: b.active } });
    });
    ctx.ok({ user: s.auth.publicUser(db.get('SELECT * FROM users WHERE id = ?', u.id)) });
  });
  app.post('/api/admin/team/:id/reset', ...U(s, { perm: 'team.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { what: v.oneOf(['password', '2fa', 'unlock']) });
    const u = db.get('SELECT * FROM users WHERE id = ?', ctx.params.id); if (!u) throw new HttpError(404, 'NO_ENCONTRADO', 'Usuario no encontrado.');
    const out = {};
    if (b.what === 'password') {
      const temp = C.randomCode(4) + '-' + C.randomCode(4) + '-' + C.randomCode(4) + '-' + C.randomCode(4);
      const h = await C.hashPassword(temp);
      db.run('UPDATE users SET password_hash = ?, must_change_password = 1, updated_at = ? WHERE id = ?', h, now(), u.id); out.tempPassword = temp;
    } else if (b.what === '2fa') db.run("UPDATE users SET totp_enabled = 0, totp_secret_enc = NULL, totp_last_counter = -1, recovery_codes = '[]', updated_at = ? WHERE id = ?", now(), u.id);
    else db.run('UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ?', u.id);
    s.auth.revokeAllSessions(u.id);
    audit.log({ actor: actor(ctx), action: 'usuario.reinicio_' + b.what, entity: ['user', u.id], ip: ctx.ip });
    ctx.ok(out);
  });

  /* ------------------------------------------------------------ auditoría */
  app.get('/api/admin/audit', ...U(s, { perm: 'audit.view' }), (ctx) => {
    const q = (ctx.query.get('q') || '').trim(), et = ctx.query.get('entity_type') || '', eid = ctx.query.get('entity_id') || '';
    const w = [], p = [];
    if (q) { const like = '%' + q.replace(/[%_]/g, '') + '%'; w.push('(action LIKE ? OR actor_label LIKE ? OR data LIKE ? OR entity_id LIKE ?)'); p.push(like, like, like, like); }
    if (et) { w.push('entity_type = ?'); p.push(et); } if (eid) { w.push('entity_id = ?'); p.push(eid); }
    const { limit, offset } = page(ctx);
    ctx.ok({ total: db.get(`SELECT COUNT(*) n FROM audit_log ${w.length ? 'WHERE ' + w.join(' AND ') : ''}`, ...p).n,
      rows: db.all(`SELECT seq, at, actor_type, actor_label, action, entity_type, entity_id, ip, data FROM audit_log ${w.length ? 'WHERE ' + w.join(' AND ') : ''} ORDER BY seq DESC LIMIT ? OFFSET ?`, ...p, limit, offset) });
  });
  app.post('/api/admin/audit/verify', ...U(s, { perm: 'audit.view' }), (ctx) => {
    const r = audit.verify();
    audit.log({ actor: actor(ctx), action: 'auditoria.verificada', ip: ctx.ip, data: { ok: r.ok, count: r.count } });
    ctx.ok(r);
  });

  /* ------------------------------------------------------------ configuración */
  app.get('/api/admin/settings', ...U(s, { perm: 'dashboard.view' }), (ctx) => ctx.ok({ settings: s.settings.all() }));
  app.put('/api/admin/settings', ...U(s, { perm: 'settings.manage' }), async (ctx) => {
    const b = await ctx.json();
    const schemas = {
      company: (x) => v.parse(x, { name: v.str({ min: 2, max: 80 }), legal_name: v.str({ max: 160, optional: true }), ruc: v.str({ max: 11, optional: true, pattern: /^\d{11}$/ }), address: v.str({ max: 200, optional: true }), email: v.email({ optional: true }), phone: v.str({ max: 20, optional: true }), website: v.str({ max: 120, optional: true }) }),
      payment_instructions: (x) => {
        const o = v.parse(x, { yape_number: v.str({ max: 15, optional: true, pattern: /^9\d{8}$/ }), yape_holder: v.str({ max: 80, optional: true }), plin_number: v.str({ max: 15, optional: true, pattern: /^9\d{8}$/ }), plin_holder: v.str({ max: 80, optional: true }), note: v.str({ max: 300, optional: true }) });
        o.bank_accounts = (Array.isArray(x.bank_accounts) ? x.bank_accounts : []).slice(0, 6).map((a, i) => v.parse(a, { bank: v.str({ min: 2, max: 40 }), currency: v.oneOf(['PEN', 'USD'], { default: 'PEN' }), account: v.str({ min: 5, max: 30, pattern: /^[0-9-]+$/ }), cci: v.str({ max: 30, optional: true, pattern: /^[0-9-]+$/ }), holder: v.str({ min: 2, max: 80 }) }));
        return o;
      },
      reminders_days: (x) => v.parse({ x }, { x: v.arrayOf(v.int({ min: 1, max: 60 }), { max: 6 }) }).x,
      renewal_notice_days: (x) => v.parse({ x }, { x: v.int({ min: 1, max: 60 }) }).x,
      four_eyes: (x) => v.parse({ x }, { x: v.bool() }).x,
      restore_anchor: (x) => v.parse({ x }, { x: v.oneOf(['fecha_pago', 'continuar']) }).x,
      allow_client_reports: (x) => v.parse({ x }, { x: v.bool() }).x,
      complaint_days: (x) => v.parse({ x }, { x: v.int({ min: 1, max: 30 }) }).x,
      tax: (x) => v.parse(x, { regime: v.oneOf(['nrus', 'rer', 'mype', 'general']), export_registered: v.bool({ default: false }) }),
      einvoice: (x) => {
        const o = v.parse(x, { enabled: v.bool({ default: false }), send_to_client: v.bool({ default: true }),
          series_factura: v.str({ min: 4, max: 4, pattern: /^F[A-Z0-9]{3}$/ }), series_boleta: v.str({ min: 4, max: 4, pattern: /^B[A-Z0-9]{3}$/ }),
          series_nc_factura: v.str({ min: 4, max: 4, pattern: /^F[A-Z0-9]{3}$/ }), series_nc_boleta: v.str({ min: 4, max: 4, pattern: /^B[A-Z0-9]{3}$/ }) });
        if (new Set([o.series_factura, o.series_boleta, o.series_nc_factura, o.series_nc_boleta]).size !== 4) throw new v.ValidationError('series_nc_factura', 'Cada tipo de comprobante necesita su propia serie.');
        if (o.enabled && !s.einvoice.provider) throw new v.ValidationError('enabled', 'Primero configura el proveedor de comprobantes en el .env (EINVOICE_PROVIDER, NUBEFACT_URL, NUBEFACT_TOKEN).');
        return o;
      },
    };
    // Los ajustes que cambian cómo se cobra o se declara requieren el permiso más alto y confirmar con el código 2FA.
    if ((b.tax !== undefined || b.einvoice !== undefined) && !(ctx.state.session && ctx.state.session.sudo_until && ctx.state.session.sudo_until > new Date().toISOString())) {
      throw new HttpError(403, 'CONFIRMAR', 'Confirma con tu código de verificación para cambiar impuestos o comprobantes.', { needSudo: true });
    }
    const changed = [];
    db.tx(() => {
      for (const [k, fn] of Object.entries(schemas)) if (b[k] !== undefined) { s.settings.set(k, fn(b[k]), ctx.state.user.id); changed.push(k); }
      audit.log({ actor: actor(ctx), action: 'configuracion.editada', ip: ctx.ip, data: { claves: changed } });
    });
    ctx.ok({ settings: s.settings.all() });
  });

  app.get('/api/admin/system', ...U(s, { perm: 'dashboard.view' }), (ctx) => {
    const warn = [];
    if (config.dev) warn.push('El Hub está en modo DESARROLLO: no lo uses con datos reales.');
    if (!config.culqi) warn.push('Culqi no está configurado: solo se reciben pagos manuales (Yape, Plin, transferencia).');
    else if (/^sk_test_/.test(config.culqi.secretKey)) warn.push('Culqi usa llaves de PRUEBA.');
    if (config.email.provider === 'log') warn.push('Los correos no se envían (EMAIL_PROVIDER=log).');
    if (!config.whatsapp) warn.push('WhatsApp no está configurado.');
    if (!config.backupKey) warn.push('Falta BACKUP_KEY: no se pueden generar respaldos cifrados.');
    if (!config.adminAllowedIps.length && config.production) warn.push('El panel acepta conexiones desde cualquier IP (recomendado: ADMIN_ALLOWED_IPS o Cloudflare Access).');
    const tx = s.settings.get('tax'), ei = s.settings.get('einvoice');
    if (!s.einvoice.provider) warn.push('No hay proveedor de comprobantes electrónicos (EINVOICE_PROVIDER): las boletas y facturas se emiten fuera del Hub.');
    else if (!ei.enabled) warn.push('La emisión automática de boletas y facturas está apagada (Configuración → Impuestos y comprobantes).');
    else if (s.einvoice.provider.name === 'simulado') warn.push('Comprobantes en modo SIMULADO: no se envían a SUNAT.');
    if (tx.regime === 'nrus') warn.push('Régimen Nuevo RUS: el Hub no cobra IGV ni emite facturas. Si pasas a otro régimen, cámbialo en Impuestos y comprobantes.');
    if (!tx.export_registered && db.get("SELECT 1 FROM clients WHERE country <> 'PE' AND deleted_at IS NULL LIMIT 1")) warn.push('Tienes clientes del extranjero y Solvex no figura inscrito en el Registro de Exportadores de Servicios: se les cobra IGV.');
    const bad = db.get("SELECT COUNT(*) n FROM fiscal_documents WHERE status IN ('error','rechazado')").n;
    if (bad) warn.push(`${bad} comprobante(s) con error o rechazados: revisa Cobros y pagos → Comprobantes.`);
    const lastBackup = db.get("SELECT value FROM settings WHERE key = 'last_backup'");
    ctx.ok({ einvoice_provider: s.einvoice.provider ? s.einvoice.provider.name : null, mor: s.mor.enabled(), version: '3.1.0', dev: config.dev, timezone: config.defaultTimezone, channels: s.notifier.channels(), gateway: s.gateway ? s.gateway.name : null, signing_kid: config.signing.kid, warnings: warn, last_backup: lastBackup ? JSON.parse(lastBackup.value) : null, hub_url: config.publicUrl });
  });

  /* utilidades de listas para formularios */
  app.get('/api/admin/lookups', ...U(s, { perm: 'dashboard.view' }), (ctx) => ctx.ok({
    products: db.all("SELECT id, code, name, kind, status FROM products WHERE status <> 'retirado' ORDER BY name"),
    plans: db.all('SELECT id, product_id, code, name, price_cents, interval_unit, interval_count, trial_days, grace_days, active, tax_mode FROM plans ORDER BY price_cents').map((p) => Object.assign(p, { active: !!p.active })),
    mor: s.mor.enabled(),
    instances: db.all("SELECT id, product_id, name, environment, status FROM instances WHERE status <> 'revocada'"),
    users: db.all('SELECT id, name, role FROM users WHERE active = 1 ORDER BY name'),
    timezone: config.defaultTimezone, signing_kid: config.signing.kid, me: ctx.state.user.id,
  }));
  app.get('/api/admin/clients-lite', ...U(s, { perm: 'clients.view' }), (ctx) => ctx.ok({ clients: db.all('SELECT id, code, display_name name FROM clients WHERE deleted_at IS NULL ORDER BY display_name LIMIT 2000') }));
  void jws;
};
