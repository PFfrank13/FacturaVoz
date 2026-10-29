'use strict';
/**
 * Rutas públicas:
 *  - /v1/public/*   lo usa el sitio web (formulario, catálogo, pedir enlace de pago, libro de reclamaciones).
 *  - /p/:token      página de pago de un cobro (enlace personal e imposible de adivinar: 256 bits).
 *  - /webhooks/culqi/:secreto  avisos de la pasarela.
 *  - /.well-known/solvex-license-keys.json  llaves públicas para verificar tokens.
 */
const fs = require('node:fs');
const path = require('node:path');
const v = require('../lib/validate');
const T = require('../lib/time');
const C = require('../lib/crypto');
const sec = require('../http/security');
const { HttpError } = require('../http/app');
const { money, fecha } = require('../services/notify');

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/** Suma días hábiles (lunes a viernes) para el plazo del Libro de Reclamaciones. */
function addBusinessDays(date, n) { let d = date, k = 0; while (k < n) { d = T.addDays(d, 1); const wd = new Date(d + 'T12:00:00Z').getUTCDay(); if (wd !== 0 && wd !== 6) k++; } return d; }

module.exports = (app, s) => {
  const { db, vault, billing, licenses, audit, config, settings, notifier, bus } = s;
  const api = sec.headers('api', { production: config.production });
  const cors = sec.cors(config.siteOrigins);
  const pub = (ctx) => { api(ctx); cors(ctx); };
  const limLead = sec.rateLimit({ max: 5, windowMs: 3600e3, name: 'lead', message: 'Ya recibimos tus solicitudes. Te contactaremos pronto.' });
  const limLink = sec.rateLimit({ max: 5, windowMs: 3600e3, name: 'paylink' });
  const limCmp = sec.rateLimit({ max: 5, windowMs: 3600e3, name: 'complaint' });
  const limPage = sec.rateLimit({ max: 60, windowMs: 60e3, name: 'paypage' });
  const limPay = sec.rateLimit({ max: 8, windowMs: 10 * 60e3, name: 'pay', message: 'Demasiados intentos de pago. Espera unos minutos.' });
  const limHook = sec.rateLimit({ max: 300, windowMs: 60e3, name: 'hook' });
  const ipH = (ctx) => sec.ipHash(ctx.ip, config.auditKey);

  /** Cloudflare Turnstile (opcional): si hay TURNSTILE_SECRET, el formulario debe traer un token válido. */
  async function human(ctx, token) {
    if (!config.turnstileSecret) return true;
    try {
      const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ secret: config.turnstileSecret, response: String(token || ''), remoteip: ctx.ip }), signal: AbortSignal.timeout(8000) });
      return !!(await r.json()).success;
    } catch (_) { return false; }
  }

  for (const p of ['/v1/public/leads', '/v1/public/catalog', '/v1/public/pay-link', '/v1/public/complaints']) app.add('OPTIONS', p, pub);

  /* ------------------------------------------------------------ formulario de contacto */
  app.post('/v1/public/leads', pub, limLead, async (ctx) => {
    const raw = await ctx.json(8 * 1024);
    // Trampas para robots: campo oculto y tiempo mínimo de llenado. Al robot se le responde "ok" igual.
    if (raw.website || Number(raw.elapsed_ms) < 2500) return ctx.ok({ ok: true });
    if (!(await human(ctx, raw.captcha))) throw new HttpError(400, 'CAPTCHA', 'No pudimos verificar que no eres un robot. Recarga la página.');
    const b = v.parse(raw, { name: v.str({ max: 80, optional: true }), business: v.str({ max: 100, optional: true }), sector: v.str({ max: 40, optional: true }), branches: v.str({ max: 30, optional: true }), contact: v.str({ min: 6, max: 80 }), message: v.str({ max: 1000, optional: true, multiline: true }), consent: v.bool() });
    if (!b.consent) throw new v.ValidationError('consent', 'Necesitamos tu autorización para contactarte.');
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(b.contact) && !/^\+?[\d\s-]{9,15}$/.test(b.contact)) throw new v.ValidationError('contact', 'Escribe un celular o correo válido.');
    if (/https?:\/\//i.test((b.message || '') + (b.business || ''))) return ctx.ok({ ok: true }); // enlaces = casi siempre spam
    const id = C.newId('led');
    db.tx(() => {
      db.run('INSERT INTO leads (id,name_enc,business,sector,branches,contact_enc,message_enc,status,source,ip_hash,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        id, vault.encrypt(b.name, 'leads.name:' + id), b.business, b.sector, b.branches, vault.encrypt(b.contact, 'leads.contact:' + id), vault.encrypt(b.message, 'leads.message:' + id), 'nuevo', 'web', ipH(ctx), T.nowIso(), T.nowIso());
      audit.log({ actor: { type: 'publico', label: 'Sitio web' }, action: 'solicitud.recibida', entity: ['lead', id], data: { sector: b.sector } });
    });
    bus.emit('admin', { type: 'lead', id });
    ctx.ok({ ok: true });
  });

  /* ------------------------------------------------------------ catálogo público */
  app.get('/v1/public/catalog', pub, (ctx) => {
    ctx.set('Cache-Control', 'public, max-age=300');
    const products = db.all("SELECT id, code, name, kind, description FROM products WHERE public = 1 AND status = 'activo' ORDER BY name").map((p) => ({
      code: p.code, name: p.name, kind: p.kind, description: p.description,
      plans: db.all('SELECT code, name, interval_unit, interval_count, price_cents, setup_cents, trial_days, features, tax_mode, currency FROM plans WHERE product_id = ? AND public = 1 AND active = 1 ORDER BY price_cents', p.id).map((x) => Object.assign(x, { features: JSON.parse(x.features || '{}') })),
    }));
    // Precio que ve un cliente del Perú (la web es para el Perú): "incluido" ya trae IGV; "mas_impuesto" se muestra + IGV.
    const igv = s.tax.rule('PE'); const regime = (settings.get('tax') || {}).regime;
    ctx.ok({ company: settings.get('company').name || config.company.name, products, igv_rate_bp: regime === 'nrus' ? 0 : (igv ? igv.rate_bp : 0) });
  });

  /* ------------------------------------------------------------ "¿Ya eres cliente? Recibe tu enlace de pago" */
  app.post('/v1/public/pay-link', pub, limLink, async (ctx) => {
    const raw = await ctx.json(2048);
    const generic = { ok: true, message: 'Si los datos coinciden con un servicio activo, te enviamos el enlace de pago a tu correo y WhatsApp registrados.' };
    if (raw.website) return ctx.ok(generic);
    const b = v.parse(raw, { license_code: v.str({ min: 5, max: 20, pattern: /^LIC-\d{5,}$/i }), doc_number: v.str({ min: 8, max: 11, pattern: /^\d{8}(\d{3})?$/ }) });
    const l = db.get('SELECT * FROM licenses WHERE code = ?', b.license_code.toUpperCase());
    // Misma respuesta y tiempo similar exista o no: no revela qué códigos o documentos existen.
    if (l && l.status !== 'cancelada') {
      const c = db.get('SELECT * FROM clients WHERE id = ? AND deleted_at IS NULL', l.client_id);
      const okDoc = c && [vault.bidx('doc', 'RUC:' + b.doc_number), vault.bidx('doc', 'DNI:' + b.doc_number)].includes(c.doc_bidx);
      if (okDoc) {
        const inv = billing.openInvoiceForLicense(l, { create: !!l.auto_invoice && !!l.activated_at });
        if (inv) {
          const product = db.get('SELECT name FROM products WHERE id = ?', l.product_id);
          notifier.queue({ template: 'enlace_pago', client: c, license: l, dedupe: `enlace:${inv.id}:${T.localDate(Date.now())}`, vars: { servicio: `${product.name} (${l.label})`, monto: money(billing.remaining(inv), inv.currency), enlace: billing.payUrl(inv) } });
          notifier.run().catch(() => {});
        }
        audit.log({ actor: { type: 'publico', label: 'Sitio web' }, action: 'cobro.enlace_solicitado', entity: ['license', l.id], data: { enviado: !!inv } });
      } else audit.log({ actor: { type: 'publico', label: 'Sitio web' }, action: 'cobro.enlace_rechazado', entity: ['license', l.id], data: { motivo: 'documento no coincide', ip: ipH(ctx) } });
    }
    ctx.ok(generic);
  });

  /* ------------------------------------------------------------ Libro de Reclamaciones */
  app.post('/v1/public/complaints', pub, limCmp, async (ctx) => {
    const raw = await ctx.json(16 * 1024);
    if (raw.website) return ctx.ok({ ok: true, number: 'R-0000000' });
    const b = v.parse(raw, {
      kind: v.oneOf(['reclamo', 'queja']), name: v.str({ min: 3, max: 120 }), doc_type: v.oneOf(['DNI', 'CE', 'PAS', 'RUC']), doc_number: v.str({ min: 6, max: 15 }),
      email: v.email(), phone: v.str({ max: 20, optional: true }), address: v.str({ min: 5, max: 200 }), minor_guardian: v.str({ max: 120, optional: true }),
      good_type: v.oneOf(['producto', 'servicio']), amount: v.money({ optional: true }), good_description: v.str({ min: 3, max: 300 }),
      description: v.str({ min: 10, max: 3000, multiline: true }), request: v.str({ min: 5, max: 1500, multiline: true }), accept: v.bool(),
    });
    if (!b.accept) throw new v.ValidationError('accept', 'Debes aceptar el envío de la constancia.');
    v.docNumber(b.doc_type, b.doc_number, 'doc_number');
    const id = C.newId('cmp'), today = T.localDate(Date.now(), config.defaultTimezone);
    const due = addBusinessDays(today, Number(settings.get('complaint_days')) || 15);
    let number;
    db.tx(() => {
      number = today.slice(0, 4) + '-' + String(db.nextSeq('complaint_' + today.slice(0, 4))).padStart(5, '0');
      const consumer = { name: b.name, doc_type: b.doc_type, doc_number: b.doc_number, email: b.email, phone: b.phone, address: b.address, guardian: b.minor_guardian };
      db.run('INSERT INTO complaints (id,number,kind,consumer_enc,good_type,description_enc,request_enc,amount_cents,status,due_on,ip_hash,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        id, number, b.kind, vault.encrypt(JSON.stringify(consumer), 'complaints.consumer:' + id), b.good_type, vault.encrypt(b.good_description + '\n\n' + b.description, 'complaints.description:' + id),
        vault.encrypt(b.request, 'complaints.request:' + id), b.amount, 'recibido', due, ipH(ctx), T.nowIso());
      notifier.queue({ template: 'reclamo_recibido', client: null, to: { email: b.email, name: b.name }, channels: ['email'], dedupe: 'reclamo:' + id,
        vars: { tipo: b.kind, numero: number, fecha: fecha(T.nowIso(), config.defaultTimezone), detalle: b.description.slice(0, 500), pedido: b.request.slice(0, 300), plazo: fecha(T.endOfLocalDay(due, config.defaultTimezone), config.defaultTimezone) } });
      audit.log({ actor: { type: 'publico', label: 'Libro de Reclamaciones' }, action: 'reclamo.recibido', entity: ['complaint', id], data: { number, kind: b.kind } });
    });
    notifier.run().catch(() => {});
    bus.emit('admin', { type: 'complaint', id });
    ctx.ok({ ok: true, number, due_on: due });
  });

  /* ------------------------------------------------------------ llaves públicas */
  app.get('/.well-known/solvex-license-keys.json', (ctx) => { api(ctx); ctx.set('Cache-Control', 'public, max-age=3600'); ctx.set('Access-Control-Allow-Origin', '*'); ctx.ok({ issuer: 'solvex-hub', keys: licenses.publicKeys() }); });

  /* ------------------------------------------------------------ página de pago */
  const payCss = fs.readFileSync(path.join(__dirname, '..', '..', 'panel', 'pay.css'), 'utf8');
  const payJs = fs.readFileSync(path.join(__dirname, '..', '..', 'panel', 'pay.js'), 'utf8');
  app.get('/static/pay.css', (ctx) => { sec.headers('panel', { production: config.production })(ctx); ctx.set('Cache-Control', 'public, max-age=3600'); ctx.send(200, payCss, 'text/css; charset=utf-8'); });
  app.get('/static/pay.js', (ctx) => { sec.headers('panel', { production: config.production })(ctx); ctx.set('Cache-Control', 'public, max-age=3600'); ctx.send(200, payJs, 'application/javascript; charset=utf-8'); });

  const DOC = { factura: 'Factura electrónica', boleta: 'Boleta electrónica' };
  const masked = (n) => (n ? '•'.repeat(Math.max(0, String(n).length - 3)) + String(n).slice(-3) : '');
  function payPage(ctx, inv) {
    const client = db.get('SELECT display_name FROM clients WHERE id = ?', inv.client_id);
    const m = (c) => money(c, inv.currency);
    const bt = billing.billToOf(inv) || {};
    const docs = db.all("SELECT kind, series, number, status, pdf_url, link FROM fiscal_documents WHERE invoice_id = ? AND kind <> 'nota_credito' AND status IN ('aceptado','enviado') ORDER BY created_at", inv.id);
    const breakdown = inv.tax_treatment === 'mor' ? '' : `<div class="tax"><div><span>Valor de venta</span><b>${esc(m(inv.subtotal_cents))}</b></div>
<div><span>${esc(inv.tax_treatment === 'exportacion' ? 'IGV (exportación de servicios)' : inv.tax_treatment === 'no_sujeto' ? 'IGV (no aplica)' : inv.tax_label || 'Impuesto')}</span><b>${esc(m(inv.tax_cents))}</b></div>
<div class="tot"><span>Total</span><b>${esc(m(inv.amount_cents))}</b></div></div>
${DOC[inv.fiscal_doc] && settings.get('einvoice').enabled ? `<p class="muted">Recibirás una ${esc(DOC[inv.fiscal_doc].toLowerCase())} a nombre de ${esc(bt.name || client.display_name)} (${esc(bt.doc_type || '')} ${esc(masked(bt.doc_number))}). Si los datos no son correctos, avísanos antes de pagar.</p>` : ''}`;
    const lic = inv.license_id ? licenses.get(inv.license_id) : null;
    const product = lic ? db.get('SELECT name FROM products WHERE id = ?', lic.product_id) : null;
    const pi = settings.get('payment_instructions');
    const company = settings.get('company').name || config.company.name;
    const remaining = billing.remaining(inv);
    const tz = lic ? lic.timezone : config.defaultTimezone;
    const gw = s.gateway && (s.gateway.name === 'culqi' ? config.culqi.publicKey : (config.dev ? 'simulada' : ''));
    const paid = inv.status === 'pagada', voided = inv.status === 'anulada';
    const lastReceipt = paid ? db.get("SELECT number, method, card_label, reviewed_at FROM payments WHERE invoice_id = ? AND status = 'aprobado' ORDER BY reviewed_at DESC LIMIT 1", inv.id) : null;
    const pending = db.get("SELECT COUNT(*) n FROM payments WHERE invoice_id = ? AND status = 'por_verificar'", inv.id).n;
    const banks = (pi.bank_accounts || []).map((a) => `<li><b>${esc(a.bank)}</b> (${esc(a.currency)}) · Cuenta ${esc(a.account)}${a.cci ? ' · CCI ' + esc(a.cci) : ''} · ${esc(a.holder)}</li>`).join('');
    const manual = (pi.yape_number || pi.plin_number || banks);
    ctx.html(200, `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow">
<title>Pagar ${esc(inv.number)} · ${esc(company)}</title><link rel="stylesheet" href="/static/pay.css"></head><body>
<main class="card" id="app" data-token="${esc(ctx.params.token)}" data-amount="${remaining}" data-currency="${esc(inv.currency)}" data-pk="${esc(gw)}" data-company="${esc(company)}" data-number="${esc(inv.number)}">
<p class="brand">${esc(company)}</p>
${voided ? `<h1>Este cobro fue anulado</h1><p class="muted">Si necesitas pagar tu servicio, solicita un enlace nuevo.</p>` : paid ? `<div class="ok"><span>✓</span></div><h1>Pagado</h1>
<dl><div><dt>Cobro</dt><dd>${esc(inv.number)}</dd></div><div><dt>Recibo</dt><dd>${esc(lastReceipt ? lastReceipt.number : '—')}</dd></div>
${docs.map((d) => `<div><dt>${esc(DOC[d.kind] || 'Comprobante')}</dt><dd>${d.pdf_url || d.link ? `<a href="${esc(d.pdf_url || d.link)}" rel="noopener noreferrer" target="_blank">${esc(d.series + '-' + d.number)}</a>` : esc(d.series + '-' + d.number)}</dd></div>`).join('')}
${lic && lic.period_end ? `<div><dt>Servicio vigente hasta</dt><dd>${esc(fecha(lic.period_end, tz))}</dd></div>` : ''}</dl><p class="muted">Puedes cerrar esta página.</p>` : `
<h1>${esc(m(remaining))}</h1>
<p class="muted">${esc(inv.description)}</p>
${breakdown}
<dl><div><dt>Cliente</dt><dd>${esc(client.display_name)}</dd></div>${product ? `<div><dt>Servicio</dt><dd>${esc(product.name)} · ${esc(lic.label)}</dd></div>` : ''}
<div><dt>Cobro</dt><dd>${esc(inv.number)}</dd></div>${inv.due_at ? `<div><dt>Vence</dt><dd>${esc(fecha(inv.due_at, tz))}</dd></div>` : ''}
${inv.paid_cents + inv.credit_applied_cents > 0 ? `<div><dt>Ya abonado</dt><dd>${esc(m(inv.paid_cents + inv.credit_applied_cents))}</dd></div>` : ''}</dl>
${pending ? `<p class="note">Tienes ${pending} pago(s) reportado(s) en revisión. Te avisaremos al aprobarse.</p>` : ''}
${gw ? `<section><h2>Tarjeta o Yape</h2><p class="muted">Pago seguro procesado por ${s.gateway.name === 'culqi' ? 'Culqi' : 'la pasarela de pruebas'}. ${esc(company)} no ve ni guarda los datos de tu tarjeta.</p>
<label for="em">Correo para tu comprobante</label><input id="em" type="email" autocomplete="email" maxlength="254" placeholder="tu@correo.com">
<button id="pay" type="button">Pagar ${esc(m(remaining))}</button>${s.gateway.name !== 'culqi' ? '<p class="note">Modo de pruebas: el pago se simula.</p>' : ''}</section>` : ''}
${manual && settings.get('allow_client_reports') ? `<section><h2>${gw ? 'O paga por Yape, Plin o transferencia' : 'Paga por Yape, Plin o transferencia'}</h2><ul class="pi">
${pi.yape_number ? `<li><b>Yape</b> ${esc(pi.yape_number)}${pi.yape_holder ? ' · ' + esc(pi.yape_holder) : ''}</li>` : ''}${pi.plin_number ? `<li><b>Plin</b> ${esc(pi.plin_number)}${pi.plin_holder ? ' · ' + esc(pi.plin_holder) : ''}</li>` : ''}${banks}</ul>
<p class="muted">${esc(pi.note || '')}</p>
<details><summary>Ya pagué: enviar número de operación</summary><form id="rep" novalidate>
<label for="rm">Medio</label><select id="rm"><option value="yape">Yape</option><option value="plin">Plin</option><option value="transferencia">Transferencia</option><option value="deposito">Depósito</option></select>
<label for="ro">Número de operación</label><input id="ro" maxlength="40" inputmode="numeric" autocomplete="off" required>
<label for="ra">Monto pagado (${esc(inv.currency)})</label><input id="ra" inputmode="decimal" maxlength="12" value="${(remaining / 100).toFixed(2)}">
<label for="rd">Fecha del pago</label><input id="rd" type="date" value="${T.localDate(Date.now(), tz)}">
<input id="rw" class="hp" tabindex="-1" autocomplete="off" aria-hidden="true">
<button type="submit">Enviar para verificación</button></form></details></section>` : ''}
`}
<div id="msg" role="status" aria-live="polite"></div>
<p class="foot">Enlace personal: no lo compartas. ¿Dudas? ${config.company.supportPhone ? 'WhatsApp ' + esc(config.company.supportPhone) : esc(config.company.supportEmail || company)}</p>
</main>
${gw && !paid && !voided && s.gateway.name === 'culqi' ? '<script src="https://checkout.culqi.com/js/v4"></script>' : ''}<script src="/static/pay.js"></script></body></html>`);
  }

  app.get('/p/:token', limPage, (ctx) => {
    sec.headers('pay', { production: config.production })(ctx);
    let inv = billing.invoiceByToken(ctx.params.token);
    if (inv) inv = billing.refreshTax(inv); // si cambiaron los datos del cliente y aún no pagó, el impuesto se ajusta
    if (!inv) { ctx.html(404, '<!doctype html><meta charset="utf-8"><title>Enlace no válido</title><p style="font-family:system-ui;padding:24px">Enlace de pago no válido o vencido. Solicita uno nuevo.</p>'); return; }
    payPage(ctx, inv);
  });

  const inflight = new Set();
  app.post('/v1/public/pay/:token/card', limPay, async (ctx) => {
    api(ctx);
    const inv = billing.invoiceByToken(ctx.params.token);
    if (!inv) throw new HttpError(404, 'NO_ENCONTRADO', 'Enlace de pago no válido.');
    if (!s.gateway) throw new HttpError(400, 'SIN_PASARELA', 'El pago con tarjeta no está disponible.');
    const b = v.parse(await ctx.json(2048), { token: v.str({ min: 8, max: 120, pattern: /^[A-Za-z0-9_]+$/ }), email: v.email() });
    if (!['pendiente', 'parcial'].includes(inv.status)) throw new HttpError(409, 'COBRO_CERRADO', inv.status === 'pagada' ? 'Este cobro ya está pagado.' : 'Este cobro fue anulado.');
    if (inflight.has(inv.id)) throw new HttpError(409, 'EN_PROCESO', 'Ya hay un pago en proceso. Espera unos segundos.');
    inflight.add(inv.id);
    try {
      const fresh = billing.refreshTax(billing.invoiceByToken(ctx.params.token)); // impuesto vigente antes de cobrar
      if (fresh.amount_cents !== inv.amount_cents) throw new HttpError(409, 'MONTO_CAMBIO', 'El monto se actualizó. Recarga la página para ver el nuevo total.');
      if (inv.tax_treatment === 'mor') throw new HttpError(409, 'COBRA_MOR', 'Este cobro lo gestiona otra plataforma de pago.');
      const amount = billing.remaining(inv); // el monto SIEMPRE sale de la base
      const lic = inv.license_id ? licenses.get(inv.license_id) : null;
      let c;
      try {
        c = await s.gateway.createCharge({ amountCents: amount, currency: inv.currency, email: b.email, token: b.token, description: `${inv.number} ${inv.description}`.slice(0, 80), metadata: { invoice_id: inv.id, invoice_number: inv.number, license_code: lic ? lic.code : '' } });
      } catch (e) {
        audit.log({ actor: { type: 'pasarela', label: s.gateway.name }, action: 'pago.tarjeta_rechazada', entity: ['invoice', inv.id], data: { status: e.status || null } });
        throw new HttpError(402, 'RECHAZADO', e.userMessage || 'La pasarela rechazó el pago. Verifica tus datos o usa otro medio.');
      }
      if (!c.paid) throw new HttpError(402, 'RECHAZADO', 'El pago no fue aprobado.');
      const r = billing.applyGatewayCharge(Object.assign({}, c, { email: b.email }), { invoice_id: inv.id }, ctx.ip);
      s.notifier.run().catch(() => {});
      const lic2 = inv.license_id ? licenses.get(inv.license_id) : null;
      ctx.ok({ ok: true, receipt: r.payment.number, period_end: lic2 && lic2.period_end ? fecha(lic2.period_end, lic2.timezone) : null });
    } finally { inflight.delete(inv.id); }
  });

  app.post('/v1/public/pay/:token/report', limPay, async (ctx) => {
    api(ctx);
    const inv = billing.invoiceByToken(ctx.params.token);
    if (!inv) throw new HttpError(404, 'NO_ENCONTRADO', 'Enlace de pago no válido.');
    if (!settings.get('allow_client_reports')) throw new HttpError(403, 'NO_DISPONIBLE', 'Reporte de pagos no disponible.');
    const raw = await ctx.json(2048);
    if (raw.website) return ctx.ok({ ok: true });
    const b = v.parse(raw, { method: v.oneOf(['yape', 'plin', 'transferencia', 'deposito']), operation_ref: v.str({ min: 4, max: 40, pattern: /^[A-Za-z0-9 -]+$/ }), amount: v.money({ min: 0.01 }), paid_on: v.date() });
    const today = T.localDate(Date.now(), config.defaultTimezone);
    if (b.paid_on > today || b.paid_on < T.addDays(today, -60)) throw new v.ValidationError('paid_on', 'Fecha no válida.');
    const p = billing.registerPayment({ invoice_id: inv.id, method: b.method, amount_cents: b.amount, operation_ref: b.operation_ref, paid_on: b.paid_on, source: 'cliente', note: 'Reportado por el cliente desde el enlace de pago' }, { type: 'publico', id: null, label: 'Cliente (enlace de pago)' }, ctx.ip);
    const client = db.get('SELECT * FROM clients WHERE id = ?', inv.client_id);
    notifier.queue({ template: 'pago_reportado', client, channels: ['email'], dedupe: 'reporte:' + p.id, vars: { servicio: inv.description, monto: money(b.amount, inv.currency) } });
    ctx.ok({ ok: true, message: 'Recibimos tu reporte. Lo verificaremos y tu servicio se actualizará automáticamente al aprobarse.' });
  });

  /* ------------------------------------------------------------ webhook de Culqi */
  app.post('/webhooks/culqi/:secret', limHook, async (ctx) => {
    api(ctx);
    if (!config.culqi || !C.safeEqual(ctx.params.secret, config.culqi.webhookSecret)) { audit.log({ actor: { type: 'publico', label: 'desconocido' }, action: 'webhook.secreto_invalido', data: { ip: ipH(ctx) } }); throw new HttpError(404, 'NO_ENCONTRADO', 'No encontrado.'); }
    let body; try { body = await ctx.json(64 * 1024); } catch (_) { body = {}; }
    ctx.ok({ received: true }); // se responde de inmediato; se procesa después
    const eventId = v.clean(String(body.id || '')).slice(0, 80);
    if (!eventId) return;
    let data = body.data; if (typeof data === 'string') { try { data = JSON.parse(data); } catch (_) { data = null; } }
    const chargeId = data && typeof data === 'object' ? String((typeof data.id === 'string' && data.id.startsWith('chr_') ? data.id : data.charge_id) || '') : '';
    if (db.run('INSERT OR IGNORE INTO gateway_events (id,provider,type,charge_id,received_at) VALUES (?,?,?,?,?)', eventId, 'culqi', v.clean(String(body.type || '')).slice(0, 60), chargeId.slice(0, 80), T.nowIso()).changes === 0) return;
    setImmediate(async () => {
      try {
        if (!/^[A-Za-z0-9_]{6,80}$/.test(chargeId)) { db.run("UPDATE gateway_events SET outcome = 'sin_cargo', processed_at = ? WHERE id = ?", T.nowIso(), eventId); return; }
        const c = await s.gateway.getCharge(chargeId); // la verdad sale de la API, no del aviso
        let out = 'ignorado';
        const existing = db.get("SELECT * FROM payments WHERE method = 'culqi' AND operation_norm = ?", chargeId.toUpperCase().replace(/[^A-Z0-9]/g, ''));
        if (c.refunded && existing && existing.status === 'aprobado') { billing.reversePayment(existing.id, { reason: 'Reembolso/contracargo informado por Culqi', kind: 'reembolsado' }, { type: 'pasarela', label: 'Culqi' }); out = 'reembolsado'; }
        else if (c.paid && !existing && /^inv_[a-z0-9]{20}$/.test(String(c.metadata.invoice_id || ''))) { billing.applyGatewayCharge(c, { invoice_id: c.metadata.invoice_id }); out = 'aplicado'; }
        else if (existing) out = 'ya_registrado';
        db.run('UPDATE gateway_events SET outcome = ?, processed_at = ? WHERE id = ?', out, T.nowIso(), eventId);
      } catch (e) {
        s.log.error('webhook culqi', eventId, e.message);
        db.run('DELETE FROM gateway_events WHERE id = ?', eventId); // permite que el reintento de Culqi lo procese
      }
    });
  });

  app.get('/', (ctx) => { api(ctx); ctx.html(200, '<!doctype html><meta charset="utf-8"><title>Solvex Hub</title><p style="font-family:system-ui;padding:24px">Solvex Hub</p>'); });
  app.get('/robots.txt', (ctx) => { ctx.send(200, 'User-agent: *\nDisallow: /\n', 'text/plain'); });
};

module.exports.addBusinessDays = addBusinessDays;
