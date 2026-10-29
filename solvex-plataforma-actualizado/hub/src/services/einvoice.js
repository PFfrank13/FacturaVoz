'use strict';
/**
 * Comprobantes electrónicos SUNAT: boleta, factura y nota de crédito.
 *
 *  - Uno por cada pago aprobado, por el monto recibido (en servicios, el comprobante se emite al percibir la
 *    retribución). Un abono parcial lleva su propio comprobante; un pago de más se documenta completo y el saldo
 *    a favor que genera ya no vuelve a documentarse cuando se aplica.
 *  - Factura si el cliente tiene RUC o es del extranjero (exportación); boleta si es persona con DNI/CE/pasaporte.
 *  - Reembolso → nota de crédito "06 devolución total". Pago anulado por error → nota de crédito "01 anulación".
 *  - El número se asigna en la misma transacción que aprueba el pago (correlativo por serie, nunca se reutiliza).
 *    El envío al proveedor es asíncrono con reintentos: si el proveedor o SUNAT no responden, el pago y la
 *    licencia no se detienen. Antes de reenviar, se consulta si el proveedor ya lo tiene (no hay duplicados).
 *  - Si faltan datos del cliente (razón social o dirección para una factura), el comprobante queda "con error"
 *    con un mensaje claro; al corregir al cliente, "Reintentar" toma los datos nuevos.
 */
const C = require('../lib/crypto');
const T = require('../lib/time');
const { HttpError } = require('../http/app');
const { portion } = require('./tax');
const { money } = require('./notify');

const OPERATION = { venta_interna: 'venta_interna', no_domiciliado: 'no_domiciliado', exportacion: 'exportacion', extranjero: 'exportacion', nrus: 'nrus' };
const LABEL = { factura: 'Factura', boleta: 'Boleta', nota_credito: 'Nota de crédito' };
const BACKOFF_MIN = [1, 2, 5, 10, 30, 60, 120, 240, 360];

class Einvoice {
  constructor({ db, vault, audit, settings, config, bus, billing, tax, provider, log = console }) {
    Object.assign(this, { db, vault, audit, settings, cfg: config, bus, billing, tax, provider, log });
    this.running = false; this.pendingKick = false;
    billing.einvoice = this;
  }

  get conf() { return this.settings.get('einvoice') || {}; }
  active() { return !!(this.conf.enabled && this.provider); }
  customerOf(doc) { return JSON.parse(this.vault.decrypt(doc.customer_enc, 'fiscal_documents.customer:' + doc.id)); }

  /** Datos mínimos que exige SUNAT/el proveedor. Devuelve el problema o null. */
  validate(kind, c, operation) {
    if (!c || !c.name || c.name.length < 2) return 'Falta el nombre o razón social del cliente.';
    if (!c.doc_number) return 'Falta el número de documento del cliente.';
    if (kind === 'factura' && operation === 'venta_interna' && c.doc_type !== 'RUC') return 'Una factura nacional requiere RUC del cliente.';
    if (kind === 'factura' && !c.address) return 'Falta la dirección fiscal del cliente (obligatoria en una factura). Complétala en su ficha y reintenta.';
    if (kind === 'boleta' && c.doc_type === 'RUC') return 'Un cliente con RUC recibe factura, no boleta.';
    return null;
  }

  seriesFor(kind, relatedKind) {
    const c = this.conf;
    if (kind === 'factura') return c.series_factura || 'F001';
    if (kind === 'boleta') return c.series_boleta || 'B001';
    return relatedKind === 'factura' ? (c.series_nc_factura || 'FC01') : (c.series_nc_boleta || 'BC01');
  }

  _insert({ kind, inv, payment, related = null, reason = null, amounts, operation, description, customer, rate, treatment, actor }) {
    const series = this.seriesFor(kind, related && related.kind);
    if (!/^[FB][A-Z0-9]{3}$/.test(series) || (kind !== 'nota_credito' && series[0] !== (kind === 'factura' ? 'F' : 'B')) || (related && series[0] !== related.series[0])) {
      throw new HttpError(500, 'SERIE', `Serie no válida para ${LABEL[kind]}: ${series}. Revisa Configuración → Comprobantes.`);
    }
    const id = C.newId('cpe'), number = this.db.nextSeq('cpe:' + series), now = T.nowIso();
    const problem = this.validate(related ? related.kind : kind, customer, operation);
    this.db.run(`INSERT INTO fiscal_documents (id,kind,series,number,invoice_id,payment_id,client_id,related_id,note_reason,operation,currency,subtotal_cents,tax_cents,total_cents,tax_rate_bp,tax_treatment,
        customer_enc,description,status,provider,attempts,next_attempt_at,last_error,created_by,created_at,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?,?,?,?)`, id, kind, series, number, inv.id, payment.id, inv.client_id, related ? related.id : null, reason, operation, payment.currency || 'PEN',
    amounts.subtotal, amounts.tax, amounts.total, rate, treatment, this.vault.encrypt(JSON.stringify(customer), 'fiscal_documents.customer:' + id), description.slice(0, 250),
    problem ? 'error' : 'pendiente', this.provider ? this.provider.name : 'ninguno', now, problem, actor ? actor.label : 'Sistema', now, now);
    this.audit.log({ actor: actor || { type: 'sistema', label: 'Comprobantes' }, action: 'comprobante.creado', entity: ['fiscal_document', id], data: { doc: `${series}-${number}`, kind, total_cents: amounts.total, tax_cents: amounts.tax, problema: problem || undefined } });
    if (problem) this.bus.emit('admin', { type: 'warning', message: `${LABEL[kind]} ${series}-${number}: ${problem}` });
    this.bus.emit('admin', { type: 'fiscal', id });
    return this.db.get('SELECT * FROM fiscal_documents WHERE id = ?', id);
  }

  /** Se llama dentro de la transacción que aprueba un pago. */
  onPaymentApproved(p, inv) {
    if (!this.active()) return null;
    if (p.method === 'mor' || inv.tax_treatment === 'mor' || inv.fiscal_doc === 'ninguno') return null;
    if (inv.tax_operation === 'nrus') { this.bus.emit('admin', { type: 'warning', message: `Pago ${p.number}: en el Nuevo RUS la boleta se emite fuera del Hub.` }); return null; }
    if ((p.currency || 'PEN') !== 'PEN') { this.bus.emit('admin', { type: 'warning', message: `Pago ${p.number} en ${p.currency}: emite su comprobante manualmente (falta el tipo de cambio).` }); return null; }
    if (this.db.get("SELECT 1 FROM fiscal_documents WHERE payment_id = ? AND kind IN ('factura','boleta') AND status <> 'rechazado'", p.id)) return null;
    let amounts = portion(p.amount_cents, inv);
    // Si Solvex cobra un impuesto extranjero, ante SUNAT es exportación: el comprobante va por la base, sin ese impuesto.
    if (inv.tax_treatment === 'impuesto_extranjero') amounts = { subtotal: amounts.subtotal, tax: 0, total: amounts.subtotal };
    const partial = p.amount_cents < inv.amount_cents;
    const customer = this.billing.billTo(this.db.get('SELECT * FROM clients WHERE id = ?', inv.client_id));
    return this._insert({
      kind: inv.fiscal_doc, inv, payment: p, amounts, operation: OPERATION[inv.tax_operation] || 'venta_interna', customer,
      rate: inv.tax_treatment === 'gravado' ? inv.tax_rate_bp : 0, treatment: inv.tax_treatment === 'impuesto_extranjero' ? 'exportacion' : inv.tax_treatment,
      description: (partial ? `Pago a cuenta (${inv.number}) · ` : '') + inv.description, actor: { type: 'sistema', label: 'Comprobantes' },
    });
  }

  /** Pago reembolsado o anulado: nota de crédito por el total del comprobante (aunque la emisión esté apagada hoy). */
  onPaymentReversed(p, kind, reason, actor) {
    const orig = this.db.get("SELECT * FROM fiscal_documents WHERE payment_id = ? AND kind IN ('factura','boleta') AND status <> 'rechazado'", p.id);
    if (!orig) return null;
    const existing = this.db.get("SELECT * FROM fiscal_documents WHERE related_id = ? AND kind = 'nota_credito' AND status <> 'rechazado'", orig.id);
    if (existing) return existing;
    const code = kind === 'reembolsado' ? '06' : '01';
    const inv = this.db.get('SELECT * FROM invoices WHERE id = ?', orig.invoice_id);
    return this._insert({
      kind: 'nota_credito', inv, payment: p, related: orig, reason: code, amounts: { subtotal: orig.subtotal_cents, tax: orig.tax_cents, total: orig.total_cents },
      operation: orig.operation, customer: this.customerOf(orig), rate: orig.tax_rate_bp, treatment: orig.tax_treatment,
      description: `${code === '06' ? 'Devolución total' : 'Anulación de la operación'} de ${orig.series}-${orig.number}: ${reason}`, actor,
    });
  }

  /** Datos para el proveedor (independientes de cuál sea). */
  payloadOf(doc) {
    const related = doc.related_id ? this.db.get('SELECT kind, series, number FROM fiscal_documents WHERE id = ?', doc.related_id) : null;
    const igv = this.tax.rule('PE', { date: doc.issue_date });
    return { kind: doc.kind, series: doc.series, number: doc.number, issue_date: doc.issue_date, operation: doc.operation, currency: doc.currency,
      subtotal_cents: doc.subtotal_cents, tax_cents: doc.tax_cents, total_cents: doc.total_cents, tax_rate_bp: doc.tax_rate_bp, igv_rate_bp: igv ? igv.rate_bp : doc.tax_rate_bp,
      customer: this.customerOf(doc), description: doc.description, related, note_reason: doc.note_reason, send_to_client: this.conf.send_to_client !== false };
  }

  kick() {
    if (!this.provider || this.pendingKick || this.closed) return;
    this.pendingKick = true;
    setImmediate(() => { this.pendingKick = false; if (this.closed) return; this.run().catch((e) => this.log.error('comprobantes', e.message)); });
  }

  /** Envía los pendientes y consulta los que esperan respuesta de SUNAT. Lo llama el programador cada minuto. */
  async run(now = Date.now()) {
    if (!this.provider || this.running || this.closed) return { sent: 0, polled: 0 };
    this.running = true;
    const out = { sent: 0, polled: 0 };
    try {
      const iso = T.nowIso(now);
      for (const doc of this.db.all("SELECT * FROM fiscal_documents WHERE status = 'pendiente' AND next_attempt_at <= ? ORDER BY created_at, number LIMIT 25", iso)) {
        if (doc.related_id) {
          const orig = this.db.get('SELECT * FROM fiscal_documents WHERE id = ?', doc.related_id);
          if (orig.status === 'rechazado') { this._update(doc, { status: 'error', last_error: 'El comprobante que modifica fue rechazado por SUNAT: no corresponde nota de crédito.' }); continue; }
          if (orig.status !== 'aceptado') { this._update(doc, { next_attempt_at: T.nowIso(now + 120e3) }); continue; } // espera a que SUNAT acepte el original
        }
        await this.send(doc, now); out.sent++;
      }
      for (const doc of this.db.all("SELECT * FROM fiscal_documents WHERE status = 'enviado' AND next_attempt_at <= ? ORDER BY created_at LIMIT 25", iso)) { await this.poll(doc, now); out.polled++; }
    } finally { this.running = false; }
    return out;
  }

  _update(doc, fields) {
    const keys = Object.keys(fields);
    this.db.run(`UPDATE fiscal_documents SET ${keys.map((k) => k + ' = ?').join(', ')}, updated_at = ? WHERE id = ?`, ...keys.map((k) => fields[k]), T.nowIso(), doc.id);
    this.bus.emit('admin', { type: 'fiscal', id: doc.id });
  }

  async send(doc, now = Date.now()) {
    const issue = T.localDate(now, 'America/Lima');
    this._update(doc, { issue_date: issue, attempts: doc.attempts + 1 });
    const d = this.payloadOf(Object.assign({}, doc, { issue_date: issue }));
    try {
      // En un reintento, primero se pregunta si el proveedor ya lo recibió (el intento anterior pudo llegar sin respuesta).
      let r = doc.attempts > 0 ? await this.provider.consult(d) : null;
      if (!r) {
        try { r = await this.provider.send(d); }
        catch (e) { if (e.exists) r = await this.provider.consult(d); if (!r) throw e; }
      }
      this.apply(doc, r, now);
    } catch (e) {
      const attempts = doc.attempts + 1;
      if (e.retryable && attempts < 30) {
        const wait = BACKOFF_MIN[Math.min(attempts - 1, BACKOFF_MIN.length - 1)] * 60e3;
        this._update(doc, { last_error: String(e.message).slice(0, 500), next_attempt_at: T.nowIso(now + wait) });
      } else {
        this._update(doc, { status: 'error', last_error: String(e.message).slice(0, 500) });
        this.audit.log({ actor: { type: 'sistema', label: 'Comprobantes' }, action: 'comprobante.error', entity: ['fiscal_document', doc.id], data: { doc: `${doc.series}-${doc.number}`, error: String(e.message).slice(0, 200) } });
        this.bus.emit('admin', { type: 'warning', message: `${LABEL[doc.kind]} ${doc.series}-${doc.number} no se pudo emitir: ${e.message}` });
      }
    }
  }

  async poll(doc, now = Date.now()) {
    try {
      const r = await this.provider.consult(this.payloadOf(doc));
      if (r) this.apply(doc, r, now); else this._update(doc, { next_attempt_at: T.nowIso(now + 30 * 60e3) });
    } catch (e) { this._update(doc, { last_error: String(e.message).slice(0, 500), next_attempt_at: T.nowIso(now + 30 * 60e3) }); }
  }

  apply(doc, r, now = Date.now()) {
    const f = { status: r.state, sunat_code: r.code || null, sunat_description: r.description || null, hash: r.hash || doc.hash, qr: r.qr || doc.qr, link: r.link || doc.link,
      pdf_url: r.pdf || doc.pdf_url, xml_url: r.xml || doc.xml_url, cdr_url: r.cdr || doc.cdr_url, last_error: null, sent_at: doc.sent_at || T.nowIso(now) };
    if (r.state === 'aceptado') f.accepted_at = T.nowIso(now);
    if (r.state === 'enviado') f.next_attempt_at = T.nowIso(now + 10 * 60e3); // las boletas, p. ej., se aceptan en el resumen diario
    this._update(doc, f);
    if (r.state !== doc.status) this.audit.log({ actor: { type: 'sistema', label: 'Comprobantes' }, action: 'comprobante.' + r.state, entity: ['fiscal_document', doc.id], data: { doc: `${doc.series}-${doc.number}`, sunat: r.code || undefined } });
    if (r.state === 'rechazado') this.bus.emit('admin', { type: 'warning', message: `SUNAT rechazó ${LABEL[doc.kind]} ${doc.series}-${doc.number}: ${r.description || r.code}. Revisa Cobros → Comprobantes.` });
  }

  /** Reintento manual. Si nunca fue aceptado, toma los datos actuales del cliente (por si se corrigieron). */
  retry(id, actor, ip) {
    const doc = this.db.get('SELECT * FROM fiscal_documents WHERE id = ?', id);
    if (!doc) throw new HttpError(404, 'NO_ENCONTRADO', 'Comprobante no encontrado.');
    if (!['error', 'pendiente'].includes(doc.status)) throw new HttpError(409, 'ESTADO', 'Solo se reintenta un comprobante pendiente o con error.');
    if (!this.provider) throw new HttpError(400, 'SIN_PROVEEDOR', 'No hay proveedor de comprobantes configurado (EINVOICE_PROVIDER).');
    const relatedKind = doc.related_id ? this.db.get('SELECT kind FROM fiscal_documents WHERE id = ?', doc.related_id).kind : doc.kind;
    let customer = this.customerOf(doc);
    if (!doc.related_id) customer = this.billing.billTo(this.db.get('SELECT * FROM clients WHERE id = ?', doc.client_id));
    const problem = this.validate(relatedKind, customer, doc.operation);
    if (problem) throw new HttpError(400, 'DATOS', problem);
    this._update(doc, { status: 'pendiente', next_attempt_at: T.nowIso(), last_error: null, customer_enc: this.vault.encrypt(JSON.stringify(customer), 'fiscal_documents.customer:' + doc.id) });
    this.audit.log({ actor, action: 'comprobante.reintento', entity: ['fiscal_document', id], ip, data: { doc: `${doc.series}-${doc.number}` } });
    this.kick();
    return this.db.get('SELECT * FROM fiscal_documents WHERE id = ?', id);
  }

  view(d, { full = false } = {}) {
    if (!d) return null;
    const cust = this.customerOf(d);
    const inv = this.db.get('SELECT id, number, description FROM invoices WHERE id = ?', d.invoice_id);
    const rel = d.related_id ? this.db.get('SELECT id, kind, series, number FROM fiscal_documents WHERE id = ?', d.related_id) : null;
    const o = { id: d.id, kind: d.kind, label: LABEL[d.kind], doc: `${d.series}-${String(d.number).padStart(8, '0')}`, series: d.series, number: d.number, status: d.status,
      operation: d.operation, currency: d.currency, subtotal_cents: d.subtotal_cents, tax_cents: d.tax_cents, total_cents: d.total_cents, tax_rate_bp: d.tax_rate_bp,
      issue_date: d.issue_date, description: d.description, customer_name: cust.name, customer_doc: `${cust.doc_type} ${full ? cust.doc_number : '•••' + String(cust.doc_number || '').slice(-3)}`,
      invoice: inv, related: rel ? { id: rel.id, doc: `${rel.series}-${String(rel.number).padStart(8, '0')}`, kind: rel.kind } : null, note_reason: d.note_reason,
      attempts: d.attempts, last_error: d.last_error, sunat_code: d.sunat_code, sunat_description: d.sunat_description, link: d.link, pdf_url: d.pdf_url, xml_url: d.xml_url, cdr_url: d.cdr_url,
      provider: d.provider, created_at: d.created_at, accepted_at: d.accepted_at, payment_id: d.payment_id };
    if (full) o.customer = cust;
    return o;
  }

  /** Registro de ventas del mes (CSV para el contador). Las notas de crédito restan. */
  salesCsv(month) {
    if (!/^\d{4}-\d{2}$/.test(month)) throw new HttpError(400, 'MES', 'Mes no válido (AAAA-MM).');
    const rows = this.db.all("SELECT * FROM fiscal_documents WHERE issue_date LIKE ? AND status IN ('aceptado','enviado') ORDER BY kind, series, number", month + '-%');
    const q = (v) => { const s = String(v == null ? '' : v); return /[",\n;]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
    const sign = (d) => (d.kind === 'nota_credito' ? -1 : 1);
    const n = (c) => (c / 100).toFixed(2);
    const head = ['fecha', 'tipo', 'serie', 'numero', 'tipo_doc_cliente', 'doc_cliente', 'cliente', 'pais', 'operacion', 'moneda', 'base', 'igv', 'total', 'estado', 'modifica'];
    const lines = rows.map((d) => {
      const c = this.customerOf(d); const rel = d.related_id ? this.db.get('SELECT series, number FROM fiscal_documents WHERE id = ?', d.related_id) : null;
      return [d.issue_date, LABEL[d.kind], d.series, d.number, c.doc_type, c.doc_number, c.name, c.country, d.operation, d.currency, n(sign(d) * d.subtotal_cents), n(sign(d) * d.tax_cents), n(sign(d) * d.total_cents), d.status, rel ? `${rel.series}-${rel.number}` : ''].map(q).join(',');
    });
    const tot = rows.reduce((a, d) => ({ base: a.base + sign(d) * d.subtotal_cents, igv: a.igv + sign(d) * d.tax_cents, total: a.total + sign(d) * d.total_cents }), { base: 0, igv: 0, total: 0 });
    return { csv: '﻿' + [head.join(','), ...lines].join('\r\n') + '\r\n', totals: tot, count: rows.length, label: `${money(tot.igv)} de IGV` };
  }
}

module.exports = { Einvoice, LABEL };
