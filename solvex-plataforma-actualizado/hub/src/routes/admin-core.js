'use strict';
/** API del panel: tablero, tiempo real, clientes y licencias. */
const v = require('../lib/validate');
const T = require('../lib/time');
const jws = require('../lib/jws');
const { HttpError } = require('../http/app');
const { U, actor, page } = require('./_admin');
const { effective } = require('../services/licenses');
const { money } = require('../services/notify');

const monthly = (l) => {
  if (l.interval_unit === 'month') return l.price_cents / l.interval_count;
  if (l.interval_unit === 'year') return l.price_cents / (12 * l.interval_count);
  if (l.interval_unit === 'day') return (l.price_cents * 30) / l.interval_count;
  return 0;
};

module.exports = (app, s) => {
  const { db, views, clients, licenses, billing, bus, config } = s;
  const tz = config.defaultTimezone;

  /* ------------------------------------------------------------ tablero */
  app.get('/api/admin/dashboard', ...U(s, { perm: 'dashboard.view' }), (ctx) => {
    const now = Date.now();
    const all = db.all("SELECT * FROM licenses WHERE status <> 'cancelada' OR cancelled_at > ?", T.nowIso(now - 30 * 864e5));
    const byStatus = { pendiente: 0, prueba: 0, activa: 0, gracia: 0, suspendida: 0, cancelada: 0 };
    let mrr = 0; const expiring = [], grace = [], suspended = [];
    for (const l of all) {
      const e = effective(l, now); byStatus[e.status]++;
      if (['activa', 'gracia'].includes(e.status)) mrr += monthly(l);
      const lv = () => views.license(l, now);
      if (['activa', 'prueba'].includes(e.status) && l.period_end && Date.parse(l.period_end) - now <= 7 * 864e5) expiring.push(lv());
      if (e.status === 'gracia') grace.push(lv());
      if (e.status === 'suspendida' && l.status_changed_at > T.nowIso(now - 30 * 864e5)) suspended.push(lv());
    }
    const ym = (ms) => T.localDate(ms, tz).slice(0, 7);
    const months = []; { const [y, m] = ym(now).split('-').map(Number); for (let i = 5; i >= 0; i--) { const d = new Date(Date.UTC(y, m - 1 - i, 1)); months.push(d.toISOString().slice(0, 7)); } }
    const inc = {}; const exp = {};
    for (const p of db.all("SELECT amount_cents, reviewed_at FROM payments WHERE status = 'aprobado' AND currency = 'PEN' AND reviewed_at > ?", T.nowIso(now - 200 * 864e5))) { const k = ym(Date.parse(p.reviewed_at)); inc[k] = (inc[k] || 0) + p.amount_cents; }
    for (const e of db.all('SELECT amount_cents, spent_on FROM expenses WHERE deleted_at IS NULL AND spent_on >= ?', months[0] + '-01')) { const k = e.spent_on.slice(0, 7); exp[k] = (exp[k] || 0) + e.amount_cents; }
    const forecast = []; { const [y, m] = ym(now).split('-').map(Number); for (let i = 0; i < 3; i++) forecast.push({ month: new Date(Date.UTC(y, m - 1 + i, 1)).toISOString().slice(0, 7), cents: 0, count: 0 }); }
    for (const l of all) {
      const e = effective(l, now);
      if (!['activa', 'gracia', 'prueba'].includes(e.status) || !l.period_end || !(l.price_cents > 0) || l.interval_unit === 'none') continue;
      let d = T.localDate(l.period_end, l.timezone), guard = 0;
      while (guard++ < 100) {
        const k = d.slice(0, 7), f = forecast.find((x) => x.month === k);
        if (k > forecast[2].month) break;
        if (f) { f.cents += l.price_cents; f.count++; }
        d = T.lastCoveredDay(T.addDays(d, 1), l.interval_unit, l.interval_count, 1, l.anchor_day);
      }
    }
    const one = (sql, ...p) => db.get(sql, ...p);
    const thisMonth = months[5];
    ctx.ok({
      kpis: {
        mrr_cents: Math.round(mrr), by_status: byStatus,
        income_month_cents: inc[thisMonth] || 0, income_prev_month_cents: inc[months[4]] || 0,
        pending_payments: one("SELECT COUNT(*) n FROM payments WHERE status = 'por_verificar'").n,
        overdue: one("SELECT COUNT(*) n, COALESCE(SUM(amount_cents - paid_cents - credit_applied_cents),0) c FROM invoices WHERE status IN ('pendiente','parcial') AND due_at < ?", T.nowIso(now)),
        failed_deliveries: one("SELECT COUNT(*) n FROM deliveries WHERE status = 'fallido'").n,
        failed_notifications: one("SELECT COUNT(*) n FROM notifications WHERE status = 'fallido'").n,
        clients: one('SELECT COUNT(*) n FROM clients WHERE deleted_at IS NULL').n,
        new_leads: one("SELECT COUNT(*) n FROM leads WHERE status = 'nuevo'").n,
        open_tickets: one("SELECT COUNT(*) n FROM tickets WHERE status IN ('abierto','en_curso')").n,
        complaints_due: one("SELECT COUNT(*) n FROM complaints WHERE status <> 'respondido'").n,
        // IGV de los comprobantes del mes (las notas de crédito restan): lo que habrá que declarar.
        igv_month_cents: one("SELECT COALESCE(SUM(CASE WHEN kind = 'nota_credito' THEN -tax_cents ELSE tax_cents END),0) c FROM fiscal_documents WHERE status IN ('aceptado','enviado') AND issue_date LIKE ?", thisMonth + '-%').c,
        fiscal_problems: one("SELECT COUNT(*) n FROM fiscal_documents WHERE status IN ('error','rechazado')").n,
      },
      series: months.map((m) => ({ month: m, income_cents: inc[m] || 0, expense_cents: exp[m] || 0 })),
      forecast,
      expiring: expiring.sort((a, b) => (a.period_end < b.period_end ? -1 : 1)).slice(0, 20),
      grace: grace.sort((a, b) => (String(a.cut_at) < String(b.cut_at) ? -1 : 1)),
      suspended: suspended.slice(0, 20),
      pending_payments: db.all("SELECT * FROM payments WHERE status = 'por_verificar' ORDER BY created_at LIMIT 10").map(views.payment),
      activity: db.all('SELECT seq, at, actor_type, actor_label, action, entity_type, entity_id FROM audit_log ORDER BY seq DESC LIMIT 15'),
    });
  });

  /* ------------------------------------------------------------ tiempo real (SSE) */
  app.get('/api/admin/stream', ...U(s), (ctx) => {
    const res = ctx.res;
    res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
    res.write('retry: 5000\n: conectado\n\n');
    const sid = ctx.state.session.id;
    const send = (e) => { try { res.write('data: ' + JSON.stringify(e) + '\n\n'); } catch (_) { /* cerrado */ } };
    const hb = setInterval(() => {
      // si la sesión se cerró o venció, se corta el canal
      const ok = db.get('SELECT 1 FROM sessions WHERE id = ? AND revoked_at IS NULL AND expires_at > ?', sid, T.nowIso());
      if (!ok) { cleanup(); res.end(); return; }
      res.write(': ping\n\n');
    }, 25_000);
    const cleanup = () => { clearInterval(hb); bus.off('admin', send); };
    bus.on('admin', send);
    ctx.req.on('close', cleanup);
  });

  /* ------------------------------------------------------------ clientes */
  app.get('/api/admin/clients', ...U(s, { perm: 'clients.view' }), (ctx) => {
    const r = clients.search({ q: ctx.query.get('q') || '', verification: ctx.query.get('verification') || '', ...page(ctx) });
    const counts = new Map(db.all("SELECT client_id, COUNT(*) n, SUM(status IN ('prueba','activa','gracia')) live FROM licenses GROUP BY client_id").map((x) => [x.client_id, x]));
    ctx.ok({ total: r.total, clients: r.rows.map((c) => Object.assign(views.client(c), { licenses: counts.get(c.id)?.n || 0, live_licenses: counts.get(c.id)?.live || 0, balance_cents: billing.balance(c.id) })) });
  });

  app.post('/api/admin/clients', ...U(s, { perm: 'clients.edit' }), async (ctx) => {
    const c = clients.create(await ctx.json(), actor(ctx), ctx.ip);
    ctx.send(201, { client: views.client(c, { full: true }) });
  });

  app.get('/api/admin/clients/:id', ...U(s, { perm: 'clients.view' }), (ctx) => {
    const c = clients.must(ctx.params.id);
    s.audit.log({ actor: actor(ctx), action: 'cliente.consultado', entity: ['client', c.id], ip: ctx.ip });
    ctx.ok({
      client: views.client(c, { full: true }), balance_cents: billing.balance(c.id),
      licenses: db.all('SELECT * FROM licenses WHERE client_id = ? ORDER BY created_at DESC', c.id).map((l) => views.license(l)),
      invoices: db.all('SELECT * FROM invoices WHERE client_id = ? ORDER BY created_at DESC LIMIT 100', c.id).map((i) => views.invoice(i, { withLink: true })),
      payments: db.all('SELECT * FROM payments WHERE client_id = ? ORDER BY created_at DESC LIMIT 100', c.id).map(views.payment),
      credits: db.all('SELECT amount_cents, reason, created_at FROM credits WHERE client_id = ? ORDER BY created_at DESC LIMIT 50', c.id),
      contacts: clients.contacts(c.id),
      tickets: db.all('SELECT id, number, subject, status, priority, created_at FROM tickets WHERE client_id = ? ORDER BY created_at DESC LIMIT 50', c.id),
    });
  });

  app.put('/api/admin/clients/:id', ...U(s, { perm: 'clients.edit' }), async (ctx) => {
    const b = await ctx.json();
    const c = clients.update(ctx.params.id, b, b.version != null ? Number(b.version) : null, actor(ctx), ctx.ip);
    // Si cambió el país o el documento, los cobros aún sin pagos se recalculan con el impuesto correcto.
    const recalculated = billing.refreshOpenForClient(c.id);
    ctx.ok({ client: views.client(c, { full: true }), recalculated });
  });

  app.post('/api/admin/clients/:id/verify', ...U(s, { perm: 'clients.verify' }), async (ctx) => {
    const b = await ctx.json();
    const c = clients.verify(ctx.params.id, { verification: b.verification, checklist: b.checklist, note: b.note ? v.clean(String(b.note)).slice(0, 300) : null }, actor(ctx), ctx.ip);
    ctx.ok({ client: views.client(c, { full: true }) });
  });

  app.post('/api/admin/clients/:id/contacts', ...U(s, { perm: 'clients.edit' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { channel: v.oneOf(['WhatsApp', 'Llamada', 'Correo', 'Visita', 'Reunión']), note: v.str({ min: 3, max: 2000, multiline: true }) });
    clients.addContact(ctx.params.id, b, actor(ctx), ctx.ip);
    ctx.ok({ contacts: clients.contacts(ctx.params.id) });
  });

  app.post('/api/admin/clients/:id/credit', ...U(s, { perm: 'invoices.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { amount: v.str({ min: 1, max: 14, pattern: /^-?\d{1,9}(\.\d{1,2})?$/ }), reason: v.str({ min: 5, max: 200 }) });
    const neg = b.amount.startsWith('-'); const cents = v.parse({ a: b.amount.replace('-', '') }, { a: v.money({ min: 0.01 }) }).a * (neg ? -1 : 1);
    const c = clients.must(ctx.params.id);
    db.tx(() => {
      db.run('INSERT INTO credits (id,client_id,amount_cents,reason,actor,created_at) VALUES (?,?,?,?,?,?)', require('../lib/crypto').newId('crd'), c.id, cents, b.reason, ctx.state.user.name, T.nowIso());
      s.audit.log({ actor: actor(ctx), action: 'saldo.ajuste', entity: ['client', c.id], ip: ctx.ip, data: { amount_cents: cents, reason: b.reason } });
    });
    ctx.ok({ balance_cents: billing.balance(c.id) });
  });

  app.get('/api/admin/clients/:id/export', ...U(s, { perm: 'clients.export', sudo: true }), (ctx) => {
    const data = clients.exportData(ctx.params.id, views);
    s.audit.log({ actor: actor(ctx), action: 'cliente.exportado', entity: ['client', ctx.params.id], ip: ctx.ip });
    ctx.set('Content-Disposition', `attachment; filename="cliente-${data.client.code}.json"`);
    ctx.ok(data);
  });

  app.post('/api/admin/clients/:id/anonymize', ...U(s, { perm: 'clients.delete', sudo: true }), (ctx) => {
    clients.anonymize(ctx.params.id, actor(ctx), ctx.ip); ctx.ok();
  });

  /* ------------------------------------------------------------ licencias */
  app.get('/api/admin/licenses', ...U(s, { perm: 'licenses.view' }), (ctx) => {
    const q = (ctx.query.get('q') || '').trim().toLowerCase();
    const st = ctx.query.get('status') || '', prod = ctx.query.get('product') || '', cli = ctx.query.get('client') || '', inst = ctx.query.get('instance') || '';
    const where = ['1=1'], p = [];
    if (prod) { where.push('product_id = ?'); p.push(prod); }
    if (cli) { where.push('client_id = ?'); p.push(cli); }
    if (inst) { where.push('instance_id = ?'); p.push(inst); }
    let rows = db.all(`SELECT * FROM licenses WHERE ${where.join(' AND ')} ORDER BY created_at DESC`, ...p).map((l) => views.license(l));
    if (st) rows = rows.filter((l) => l.status === st);
    if (q) rows = rows.filter((l) => (l.code + ' ' + l.label + ' ' + l.client.name + ' ' + l.client.code + ' ' + (l.tenant_ref || '')).toLowerCase().includes(q));
    const { limit, offset } = page(ctx);
    ctx.ok({ total: rows.length, licenses: rows.slice(offset, offset + limit) });
  });

  const createSchema = {
    client_id: v.id('cli'), plan_id: v.id('pln'), instance_id: v.id('ins', { optional: true }),
    tenant_ref: v.str({ max: 80, optional: true, pattern: /^[A-Za-z0-9._:-]{1,80}$/ }), label: v.str({ max: 120, optional: true }),
    start: v.oneOf(['pendiente', 'prueba', 'cobro', 'cortesia']), periods: v.int({ min: 1, max: 36, default: 1 }), note: v.str({ max: 300, optional: true }),
    start_date: v.date({ optional: true }), timezone: v.str({ max: 64, optional: true }), grace_days: v.int({ min: 0, max: 90, optional: true }),
    auto_cut: v.bool({ default: true }), auto_invoice: v.bool({ default: true }), price: v.money({ optional: true }), max_activations: v.int({ min: 1, max: 100, default: 1 }),
    features: v.features(), tax_mode: v.oneOf(['incluido', 'mas_impuesto'], { optional: true }),
    billing_provider: v.oneOf(['hub', 'paddle', 'lemonsqueezy', 'stripe'], { default: 'hub' }),
  };
  app.post('/api/admin/licenses', ...U(s, { perm: 'licenses.edit' }), async (ctx) => {
    const b = v.parse(await ctx.json(), createSchema);
    if (b.start === 'cortesia' && !require('../services/auth').can(ctx.state.user, 'invoices.manage')) throw new HttpError(403, 'SIN_PERMISO', 'Activar sin cobro requiere permiso de finanzas.');
    const r = licenses.create(Object.assign({}, b, { price_cents: b.price, features: Object.keys(b.features || {}).length ? b.features : undefined }), actor(ctx), ctx.ip);
    ctx.send(201, { license: views.license(r.license), invoice: views.invoice(r.invoice, { withLink: true }), licenseKey: r.licenseKey });
  });

  app.get('/api/admin/licenses/:id', ...U(s, { perm: 'licenses.view' }), (ctx) => {
    const l = licenses.must(ctx.params.id);
    const token = licenses.token(l, { aud: l.instance_id || 'vista-previa' });
    const inst = l.instance_id ? db.get('SELECT id, name, environment, status, last_seen_at FROM instances WHERE id = ?', l.instance_id) : null;
    ctx.ok({
      license: views.license(l),
      instance: inst,
      grants: db.all('SELECT * FROM license_grants WHERE license_id = ? ORDER BY created_at DESC', l.id),
      events: db.all('SELECT * FROM license_events WHERE license_id = ? ORDER BY id DESC LIMIT 100', l.id),
      invoices: db.all('SELECT * FROM invoices WHERE license_id = ? ORDER BY created_at DESC', l.id).map((i) => views.invoice(i, { withLink: true })),
      payments: db.all('SELECT * FROM payments WHERE license_id = ? ORDER BY created_at DESC', l.id).map(views.payment),
      activations: db.all('SELECT id, label, ip, first_seen_at, last_seen_at, revoked_at FROM activations WHERE license_id = ? ORDER BY last_seen_at DESC', l.id),
      deliveries: db.all('SELECT d.id, d.status, d.attempts, d.last_status, d.last_error, d.created_at, d.delivered_at FROM deliveries d JOIN outbox o ON o.id = d.event_id WHERE o.license_id = ? ORDER BY d.id DESC LIMIT 15', l.id),
      token_preview: jws.decodeUnsafe(token).payload,
      plans: db.all('SELECT id, code, name, price_cents, interval_unit, interval_count FROM plans WHERE product_id = ? AND active = 1', l.product_id),
    });
  });

  app.put('/api/admin/licenses/:id', ...U(s, { perm: 'licenses.edit' }), async (ctx) => {
    const raw = await ctx.json();
    const b = v.parse(raw, {
      label: v.str({ max: 120, optional: true }), tenant_ref: v.str({ max: 80, optional: true, pattern: /^[A-Za-z0-9._:-]{1,80}$/ }), instance_id: v.id('ins', { optional: true }),
      auto_cut: v.bool({ optional: true }), auto_invoice: v.bool({ optional: true }), grace_days: v.int({ min: 0, max: 90, optional: true }), timezone: v.str({ max: 64, optional: true }),
      price: v.money({ optional: true }), max_activations: v.int({ min: 1, max: 100, optional: true }), plan_id: v.id('pln', { optional: true }), features: v.features(), version: v.int({ min: 1 }),
      tax_mode: v.oneOf(['incluido', 'mas_impuesto'], { optional: true }), billing_provider: v.oneOf(['hub', 'paddle', 'lemonsqueezy', 'stripe'], { optional: true }),
    });
    if ((b.tax_mode || b.billing_provider) && !require('../services/auth').can(ctx.state.user, 'invoices.manage')) throw new HttpError(403, 'SIN_PERMISO', 'Cambiar impuestos o quién cobra requiere permiso de finanzas.');
    const patch = Object.assign({}, b, { price_cents: b.price, auto_cut: b.auto_cut == null ? undefined : (b.auto_cut ? 1 : 0), auto_invoice: b.auto_invoice == null ? undefined : (b.auto_invoice ? 1 : 0), features: raw.features ? b.features : null });
    if (raw.instance_id === '') { patch.instance_id = undefined; patch.tenant_ref = undefined; patch.clear_instance = true; }
    if (patch.price_cents != null && !require('../services/auth').can(ctx.state.user, 'invoices.manage')) throw new HttpError(403, 'SIN_PERMISO', 'Cambiar el precio requiere permiso de finanzas.');
    const l = licenses.update(ctx.params.id, patch, b.version, actor(ctx), ctx.ip);
    ctx.ok({ license: views.license(l) });
  });

  app.post('/api/admin/licenses/:id/activate', ...U(s, { perm: 'licenses.edit' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { mode: v.oneOf(['prueba', 'cobro', 'cortesia']), periods: v.int({ min: 1, max: 36, default: 1 }), note: v.str({ max: 300, optional: true }), start_date: v.date({ optional: true }) });
    if (b.mode === 'cortesia' && !require('../services/auth').can(ctx.state.user, 'invoices.manage')) throw new HttpError(403, 'SIN_PERMISO', 'Activar sin cobro requiere permiso de finanzas.');
    const r = licenses.activate(ctx.params.id, { mode: b.mode, periods: b.periods, note: b.note, startDate: b.start_date }, actor(ctx), ctx.ip);
    ctx.ok({ license: views.license(r.license), invoice: views.invoice(r.invoice, { withLink: true }) });
  });

  app.post('/api/admin/licenses/:id/extend', ...U(s, { perm: 'invoices.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { periods: v.int({ min: 1, max: 24, optional: true }), days: v.int({ min: 1, max: 366, optional: true }), note: v.str({ min: 5, max: 300 }) });
    if (!b.periods && !b.days) throw new v.ValidationError('periods', 'Indica ciclos o días.');
    const l = licenses.grant(ctx.params.id, { kind: 'cortesia', periods: b.periods || 1, days: b.days, note: b.note }, actor(ctx), ctx.ip);
    ctx.ok({ license: views.license(l) });
  });

  app.post('/api/admin/licenses/:id/suspend', ...U(s, { perm: 'licenses.suspend' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { reason: v.str({ min: 5, max: 300 }) });
    ctx.ok({ license: views.license(licenses.suspend(ctx.params.id, b.reason, actor(ctx), ctx.ip)) });
  });
  app.post('/api/admin/licenses/:id/resume', ...U(s, { perm: 'licenses.suspend' }), (ctx) => ctx.ok({ license: views.license(licenses.resume(ctx.params.id, actor(ctx), ctx.ip)) }));
  app.post('/api/admin/licenses/:id/cancel', ...U(s, { perm: 'licenses.suspend', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { reason: v.str({ min: 5, max: 300 }) });
    ctx.ok({ license: views.license(licenses.cancel(ctx.params.id, b.reason, actor(ctx), ctx.ip)) });
  });
  app.post('/api/admin/licenses/:id/reopen', ...U(s, { perm: 'licenses.suspend', sudo: true }), (ctx) => ctx.ok({ license: views.license(licenses.reopen(ctx.params.id, actor(ctx), ctx.ip)) }));
  app.post('/api/admin/licenses/:id/rotate-key', ...U(s, { perm: 'licenses.keys', sudo: true }), (ctx) => ctx.ok({ licenseKey: licenses.rotateKey(ctx.params.id, actor(ctx), ctx.ip) }));
  app.post('/api/admin/licenses/:id/push', ...U(s, { perm: 'licenses.edit' }), (ctx) => {
    const l = licenses.must(ctx.params.id);
    db.tx(() => { s.outbox.licenseChanged(l, 'reenvío manual'); s.audit.log({ actor: actor(ctx), action: 'licencia.reenviada', entity: ['license', l.id], ip: ctx.ip }); });
    ctx.ok();
  });

  app.post('/api/admin/licenses/:id/invoice', ...U(s, { perm: 'invoices.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { periods: v.int({ min: 1, max: 36, default: 1 }), due_date: v.date({ optional: true }) });
    const l = licenses.must(ctx.params.id);
    if (l.interval_unit === 'none' || !(l.price_cents > 0)) throw new HttpError(400, 'NO_APLICA', 'La licencia no tiene cuota periódica.');
    if (l.billing_provider !== 'hub') throw new HttpError(409, 'COBRA_MOR', 'Esta licencia se cobra por un Merchant of Record: el cobro lo emite ese proveedor.');
    const inv = billing.createInvoice({ client_id: l.client_id, license_id: l.id, kind: l.activated_at ? 'renovacion' : 'alta', periods: b.periods, amount_cents: l.price_cents * b.periods, tax_mode: l.tax_mode, due_date: b.due_date,
      description: `${l.activated_at ? 'Renovación' : 'Alta'} · ${l.label} · ${b.periods} ciclo(s)` }, actor(ctx), ctx.ip);
    ctx.send(201, { invoice: views.invoice(inv, { withLink: true }) });
  });

  app.post('/api/admin/licenses/:id/send-link', ...U(s, { perm: 'billing.view' }), async (ctx) => {
    const l = licenses.must(ctx.params.id);
    const inv = billing.openInvoiceForLicense(l, { create: !!l.auto_invoice && !!l.activated_at });
    if (!inv) throw new HttpError(409, 'SIN_COBRO', 'No hay un cobro abierto para esta licencia.');
    const client = db.get('SELECT * FROM clients WHERE id = ?', l.client_id);
    const product = db.get('SELECT name FROM products WHERE id = ?', l.product_id);
    const vars = { servicio: `${product.name} (${l.label})`, monto: money(billing.remaining(inv)), enlace: billing.payUrl(inv) };
    const ids = s.notifier.queue({ template: 'enlace_pago', client, license: l, vars });
    s.notifier.run().catch(() => {});
    s.audit.log({ actor: actor(ctx), action: 'cobro.enlace_enviado', entity: ['invoice', inv.id], ip: ctx.ip, data: { canales: ids.length } });
    const contact = s.notifier.contactOf(client);
    const text = `Hola ${(contact.name || '').split(' ')[0]}, te escribimos de ${config.company.name}. Tu enlace de pago para ${vars.servicio} por ${vars.monto}: ${vars.enlace}`;
    ctx.ok({ queued: ids.length, whatsapp_link: contact.phone ? `https://wa.me/${contact.phone}?text=${encodeURIComponent(text)}` : null, pay_url: vars.enlace, text });
  });

  app.post('/api/admin/activations/:id/revoke', ...U(s, { perm: 'licenses.keys' }), (ctx) => {
    const a = db.get('SELECT * FROM activations WHERE id = ?', ctx.params.id);
    if (!a) throw new HttpError(404, 'NO_ENCONTRADO', 'Activación no encontrada.');
    db.tx(() => { db.run('UPDATE activations SET revoked_at = ? WHERE id = ?', T.nowIso(), a.id); s.audit.log({ actor: actor(ctx), action: 'activacion.revocada', entity: ['license', a.license_id], ip: ctx.ip }); });
    ctx.ok();
  });
};
