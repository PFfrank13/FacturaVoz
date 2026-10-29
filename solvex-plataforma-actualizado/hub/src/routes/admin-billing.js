'use strict';
/** API del panel: cobros, pagos, avisos. */
const v = require('../lib/validate');
const { HttpError } = require('../http/app');
const { U, actor, page } = require('./_admin');
const { can } = require('../services/auth');

module.exports = (app, s) => {
  const { db, views, billing } = s;

  app.get('/api/admin/invoices', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const st = ctx.query.get('status') || '', q = (ctx.query.get('q') || '').trim();
    const where = ['1=1'], p = [];
    if (st === 'vencida') { where.push("status IN ('pendiente','parcial') AND due_at < ?"); p.push(new Date().toISOString()); }
    else if (st === 'abiertas') where.push("status IN ('pendiente','parcial')");
    else if (st) { where.push('status = ?'); p.push(st); }
    if (q) { where.push("(number LIKE ? OR description LIKE ? OR client_id IN (SELECT id FROM clients WHERE display_name LIKE ? OR code LIKE ?))"); const like = '%' + q.replace(/[%_]/g, '') + '%'; p.push(like, like, like, like); }
    const { limit, offset } = page(ctx);
    const total = db.get(`SELECT COUNT(*) n FROM invoices WHERE ${where.join(' AND ')}`, ...p).n;
    ctx.ok({ total, invoices: db.all(`SELECT * FROM invoices WHERE ${where.join(' AND ')} ORDER BY created_at DESC LIMIT ? OFFSET ?`, ...p, limit, offset).map((i) => views.invoice(i, { withLink: true })) });
  });

  app.get('/api/admin/invoices/:id', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const i = db.get('SELECT * FROM invoices WHERE id = ?', ctx.params.id);
    if (!i) throw new HttpError(404, 'NO_ENCONTRADO', 'Cobro no encontrado.');
    ctx.ok({ invoice: views.invoice(i, { withLink: true }), payments: db.all('SELECT * FROM payments WHERE invoice_id = ? ORDER BY created_at', i.id).map(views.payment) });
  });

  app.post('/api/admin/invoices', ...U(s, { perm: 'invoices.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), {
      client_id: v.id('cli'), license_id: v.id('lic', { optional: true }), kind: v.oneOf(['alta', 'implementacion', 'otro', 'renovacion'], { default: 'otro' }),
      description: v.str({ min: 3, max: 200 }), amount: v.money({ min: 0.01 }), periods: v.int({ min: 0, max: 36, default: 0 }), due_date: v.date({ optional: true }),
    });
    if (b.periods > 0 && !b.license_id) throw new v.ValidationError('periods', 'Para extender vigencia, el cobro debe estar ligado a una licencia.');
    const inv = billing.createInvoice({ client_id: b.client_id, license_id: b.license_id, kind: b.kind, description: b.description, amount_cents: b.amount, periods: b.periods, due_date: b.due_date }, actor(ctx), ctx.ip);
    ctx.send(201, { invoice: views.invoice(inv, { withLink: true }) });
  });

  app.post('/api/admin/invoices/:id/void', ...U(s, { perm: 'invoices.manage' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { reason: v.str({ min: 5, max: 300 }) });
    ctx.ok({ invoice: views.invoice(billing.voidInvoice(ctx.params.id, b.reason, actor(ctx), ctx.ip)) });
  });

  app.get('/api/admin/payments', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const st = ctx.query.get('status') || '';
    const where = st ? 'WHERE status = ?' : '', p = st ? [st] : [];
    const { limit, offset } = page(ctx);
    ctx.ok({
      total: db.get(`SELECT COUNT(*) n FROM payments ${where}`, ...p).n,
      payments: db.all(`SELECT * FROM payments ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`, ...p, limit, offset).map(views.payment),
      four_eyes: !!s.settings.get('four_eyes'),
    });
  });

  app.post('/api/admin/payments', ...U(s, { perm: 'payments.register' }), async (ctx) => {
    const b = v.parse(await ctx.json(), {
      invoice_id: v.id('inv'), method: v.oneOf(['yape', 'plin', 'transferencia', 'deposito', 'efectivo', 'otro']), amount: v.money({ min: 0.01 }),
      operation_ref: v.str({ max: 60, optional: true }), paid_on: v.date({ optional: true }), note: v.str({ max: 300, optional: true }), approve: v.bool({ default: false }),
    });
    if (b.approve && !can(ctx.state.user, 'payments.approve')) throw new HttpError(403, 'SIN_PERMISO', 'Tu rol no permite aprobar pagos: regístralo sin aprobar y lo revisará Finanzas.');
    if (b.approve && s.settings.get('four_eyes')) throw new HttpError(403, 'CUATRO_OJOS', 'Control de cuatro ojos activo: registra el pago y que otra persona lo apruebe.');
    const p = billing.registerPayment({ invoice_id: b.invoice_id, method: b.method, amount_cents: b.amount, operation_ref: b.operation_ref, paid_on: b.paid_on, note: b.note, source: 'panel' }, actor(ctx), ctx.ip);
    if (b.approve) {
      const r = billing.approvePayment(p.id, actor(ctx), ctx.ip);
      return ctx.send(201, { payment: views.payment(r.payment), license: r.license ? views.license(s.licenses.get(r.license.id)) : null });
    }
    ctx.send(201, { payment: views.payment(p) });
  });

  app.post('/api/admin/payments/:id/approve', ...U(s, { perm: 'payments.approve' }), (ctx) => {
    const r = billing.approvePayment(ctx.params.id, actor(ctx), ctx.ip);
    ctx.ok({ payment: views.payment(r.payment), license: r.license ? views.license(s.licenses.get(r.license.id)) : null });
  });

  app.post('/api/admin/payments/:id/reject', ...U(s, { perm: 'payments.approve' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { reason: v.str({ min: 5, max: 300 }) });
    ctx.ok({ payment: views.payment(billing.rejectPayment(ctx.params.id, b.reason, actor(ctx), ctx.ip)) });
  });

  app.post('/api/admin/payments/:id/reverse', ...U(s, { perm: 'payments.reverse', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { reason: v.str({ min: 5, max: 300 }), kind: v.oneOf(['anulado', 'reembolsado']) });
    ctx.ok({ payment: views.payment(billing.reversePayment(ctx.params.id, b, actor(ctx), ctx.ip)) });
  });

  /* ------------------------------------------------------------ avisos enviados */
  app.get('/api/admin/notifications', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const st = ctx.query.get('status') || '';
    const rows = db.all(`SELECT n.id, n.channel, n.to_hint, n.template, n.status, n.attempts, n.last_error, n.created_at, n.sent_at, c.display_name client, l.code license
      FROM notifications n LEFT JOIN clients c ON c.id = n.client_id LEFT JOIN licenses l ON l.id = n.license_id ${st ? 'WHERE n.status = ?' : ''} ORDER BY n.created_at DESC LIMIT 200`, ...(st ? [st] : []));
    ctx.ok({ channels: s.notifier.channels(), notifications: rows });
  });

  app.post('/api/admin/notifications/:id/retry', ...U(s, { perm: 'billing.view' }), (ctx) => {
    db.run("UPDATE notifications SET status = 'pendiente', next_attempt_at = ?, attempts = 0 WHERE id = ? AND status = 'fallido'", new Date().toISOString(), ctx.params.id);
    s.notifier.run().catch(() => {});
    ctx.ok();
  });
};
