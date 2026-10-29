'use strict';
/**
 * API del panel: comprobantes electrónicos, reglas de impuesto y registro de ventas.
 * Y el webhook público de los Merchant of Record: POST /webhooks/mor/:proveedor (paddle | lemonsqueezy).
 */
const v = require('../lib/validate');
const C = require('../lib/crypto');
const T = require('../lib/time');
const sec = require('../http/security');
const { HttpError } = require('../http/app');
const { U, actor, page } = require('./_admin');

module.exports = (app, s) => {
  const { db, einvoice, tax, audit, mor, config } = s;

  /* ------------------------------------------------------------ comprobantes */
  app.get('/api/admin/fiscal-documents', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const st = ctx.query.get('status') || '', month = ctx.query.get('month') || '', q = (ctx.query.get('q') || '').trim();
    const where = ['1=1'], p = [];
    if (st === 'problemas') where.push("status IN ('error','rechazado')");
    else if (st) { where.push('status = ?'); p.push(st); }
    if (/^\d{4}-\d{2}$/.test(month)) { where.push('(issue_date LIKE ? OR (issue_date IS NULL AND created_at LIKE ?))'); p.push(month + '-%', month + '-%'); }
    if (q) { where.push("(series || '-' || number LIKE ? OR client_id IN (SELECT id FROM clients WHERE display_name LIKE ? OR code LIKE ?))"); const like = '%' + q.replace(/[%_]/g, '') + '%'; p.push(like, like, like); }
    const { limit, offset } = page(ctx);
    const total = db.get(`SELECT COUNT(*) n FROM fiscal_documents WHERE ${where.join(' AND ')}`, ...p).n;
    const rows = db.all(`SELECT * FROM fiscal_documents WHERE ${where.join(' AND ')} ORDER BY created_at DESC LIMIT ? OFFSET ?`, ...p, limit, offset);
    ctx.ok({ total, documents: rows.map((d) => einvoice.view(d)), active: einvoice.active(), provider: einvoice.provider ? einvoice.provider.name : null,
      counts: Object.fromEntries(db.all('SELECT status, COUNT(*) n FROM fiscal_documents GROUP BY status').map((r) => [r.status, r.n])) });
  });

  app.get('/api/admin/fiscal-documents/:id', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const d = db.get('SELECT * FROM fiscal_documents WHERE id = ?', ctx.params.id);
    if (!d) throw new HttpError(404, 'NO_ENCONTRADO', 'Comprobante no encontrado.');
    audit.log({ actor: actor(ctx), action: 'comprobante.consultado', entity: ['fiscal_document', d.id], ip: ctx.ip });
    ctx.ok({ document: einvoice.view(d, { full: true }), notes: db.all('SELECT * FROM fiscal_documents WHERE related_id = ?', d.id).map((x) => einvoice.view(x)) });
  });

  app.post('/api/admin/fiscal-documents/:id/retry', ...U(s, { perm: 'payments.approve' }), (ctx) => {
    ctx.ok({ document: einvoice.view(einvoice.retry(ctx.params.id, actor(ctx), ctx.ip)) });
  });

  /** Registro de ventas del mes en CSV (para el contador). */
  app.get('/api/admin/sales-register', ...U(s, { perm: 'billing.view' }), (ctx) => {
    const month = ctx.query.get('month') || T.localDate(Date.now(), config.defaultTimezone).slice(0, 7);
    const r = einvoice.salesCsv(month);
    audit.log({ actor: actor(ctx), action: 'comprobantes.exportados', ip: ctx.ip, data: { month, count: r.count } });
    ctx.set('Content-Disposition', `attachment; filename="registro-ventas-${month}.csv"`);
    ctx.set('Cache-Control', 'no-store');
    ctx.send(200, r.csv, 'text/csv; charset=utf-8');
  });

  /* ------------------------------------------------------------ impuestos */
  /** Vista previa: cuánto se cobraría a un cliente por un precio dado (lo usa el formulario de cobro). */
  app.post('/api/admin/tax/preview', ...U(s, { perm: 'billing.view' }), async (ctx) => {
    const b = v.parse(await ctx.json(), { client_id: v.id('cli'), price: v.money({ min: 0.01 }), tax_mode: v.oneOf(['incluido', 'mas_impuesto'], { default: 'incluido' }) });
    const client = db.get('SELECT * FROM clients WHERE id = ? AND deleted_at IS NULL', b.client_id);
    if (!client) throw new HttpError(404, 'NO_ENCONTRADO', 'Cliente no encontrado.');
    const q = tax.quote({ client, price_cents: b.price, tax_mode: b.tax_mode });
    ctx.ok({ quote: { subtotal_cents: q.subtotal, tax_cents: q.tax, total_cents: q.total, rate_bp: q.rate, label: q.label, treatment: q.treatment, fiscal_doc: q.fiscal_doc, note: q.note } });
  });

  app.get('/api/admin/tax-rules', ...U(s, { perm: 'billing.view' }), (ctx) => ctx.ok({ rules: db.all('SELECT * FROM tax_rules ORDER BY country, valid_from DESC'), settings: s.settings.get('tax') }));

  app.post('/api/admin/tax-rules', ...U(s, { perm: 'settings.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), {
      country: v.str({ min: 2, max: 2, pattern: /^[A-Za-z]{2}$/ }), region: v.str({ max: 60, optional: true }), code: v.str({ min: 3, max: 30, pattern: /^[A-Za-z0-9_-]+$/ }),
      label: v.str({ min: 2, max: 30 }), rate: v.str({ min: 1, max: 6, pattern: /^\d{1,2}([.,]\d{1,2})?$/ }), customer_kind: v.oneOf(['todos', 'empresa', 'persona'], { default: 'todos' }),
      valid_from: v.date(), note: v.str({ max: 300, optional: true }),
    });
    const rate = Math.round(Number(b.rate.replace(',', '.')) * 100);
    if (!(rate >= 0 && rate <= 5000)) throw new v.ValidationError('rate', 'Tasa entre 0 y 50 %.');
    const country = b.country.toUpperCase(), id = C.newId('txr'), now = T.nowIso();
    db.tx(() => {
      // La regla vigente del mismo país, región y tipo de cliente se cierra el día anterior: queda el historial.
      const prev = db.get("SELECT * FROM tax_rules WHERE country = ? AND region IS ? AND customer_kind = ? AND active = 1 AND valid_to IS NULL", country, b.region || null, b.customer_kind);
      if (prev) {
        if (prev.valid_from >= b.valid_from) throw new v.ValidationError('valid_from', `Ya hay una regla desde el ${prev.valid_from}: la nueva debe empezar después.`);
        db.run('UPDATE tax_rules SET valid_to = ?, updated_at = ? WHERE id = ?', T.addDays(b.valid_from, -1), now, prev.id);
      }
      db.run(`INSERT INTO tax_rules (id,country,region,code,label,rate_bp,customer_kind,valid_from,valid_to,active,note,created_by,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,NULL,1,?,?,?,?)`,
        id, country, b.region || null, b.code.toUpperCase(), b.label, rate, b.customer_kind, b.valid_from, b.note || null, ctx.state.user.name, now, now);
      audit.log({ actor: actor(ctx), action: 'impuesto.regla_creada', entity: ['tax_rule', id], ip: ctx.ip, data: { country, code: b.code, rate_bp: rate, desde: b.valid_from, reemplaza: prev ? prev.id : undefined } });
    });
    ctx.send(201, { rule: db.get('SELECT * FROM tax_rules WHERE id = ?', id) });
  });

  app.post('/api/admin/tax-rules/:id/close', ...U(s, { perm: 'settings.manage', sudo: true }), async (ctx) => {
    const b = v.parse(await ctx.json(), { valid_to: v.date() });
    const r = db.get('SELECT * FROM tax_rules WHERE id = ?', ctx.params.id);
    if (!r) throw new HttpError(404, 'NO_ENCONTRADO', 'Regla no encontrada.');
    if (r.country === 'PE' && !db.get("SELECT 1 FROM tax_rules WHERE country = 'PE' AND id <> ? AND active = 1 AND valid_from > ?", r.id, b.valid_to)) throw new HttpError(409, 'IGV', 'El IGV del Perú no se puede cerrar sin otra regla que la reemplace (crea primero la nueva tasa).');
    if (b.valid_to < r.valid_from) throw new v.ValidationError('valid_to', 'La fecha de fin no puede ser anterior al inicio.');
    db.tx(() => {
      db.run('UPDATE tax_rules SET valid_to = ?, updated_at = ? WHERE id = ?', b.valid_to, T.nowIso(), r.id);
      audit.log({ actor: actor(ctx), action: 'impuesto.regla_cerrada', entity: ['tax_rule', r.id], ip: ctx.ip, data: { code: r.code, hasta: b.valid_to } });
    });
    ctx.ok({ rule: db.get('SELECT * FROM tax_rules WHERE id = ?', r.id) });
  });

  /* ------------------------------------------------------------ webhooks de Merchant of Record */
  const api = sec.headers('api', { production: config.production });
  const limHook = sec.rateLimit({ max: 300, windowMs: 60e3, name: 'morhook' });
  app.post('/webhooks/mor/:provider', limHook, async (ctx) => {
    api(ctx);
    const provider = String(ctx.params.provider || '').toLowerCase();
    const raw = await ctx.raw(512 * 1024); // firma sobre el cuerpo CRUDO: no se interpreta antes de verificarla
    const r = mor.handle(provider, raw, ctx.req.headers);
    if (r.status === 404) throw new HttpError(404, 'NO_ENCONTRADO', 'No encontrado.');
    if (r.status === 503) ctx.set('Retry-After', '60');
    ctx.send(r.status, { received: r.status < 300, outcome: r.outcome });
  });
};
