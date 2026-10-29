'use strict';
/**
 * Cobros: facturas internas ("cobros"), pagos, saldo a favor y pasarela.
 *
 * Reglas de dinero:
 *  - Montos en céntimos enteros. El monto a cobrar SIEMPRE sale de la base, nunca del navegador.
 *  - Un pago aprobado nunca se edita ni se borra: se anula o se reembolsa (y se revierte la vigencia).
 *  - El mismo número de operación (Yape, transferencia, cargo de Culqi) no se acepta dos veces.
 *  - Un pago parcial no extiende la licencia; un pago de más queda como saldo a favor y se aplica solo
 *    al siguiente cobro. Ningún sol se pierde.
 *  - Cada cobro guarda su desglose de impuestos (base, IGV, total) calculado ANTES de cobrar por el motor
 *    de impuestos (services/tax.js). Mientras no entre dinero, se recalcula si cambian los datos del cliente;
 *    con dinero aplicado queda congelado (lo impide la base de datos).
 *  - Estos "cobros" y "recibos" son internos. Por cada pago aprobado se emite la boleta/factura electrónica
 *    de SUNAT con un proveedor autorizado (services/einvoice.js) — ver docs/06-impuestos-y-comprobantes.md.
 */
const C = require('../lib/crypto');
const T = require('../lib/time');
const { HttpError } = require('../http/app');
const { money, fecha } = require('./notify');

const MANUAL = ['yape', 'plin', 'transferencia', 'deposito', 'efectivo', 'otro'];
const normRef = (s) => (s ? String(s).toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 60) || null : null);

class Billing {
  constructor({ db, vault, audit, licenses, notifier, settings, config, bus, tax }) {
    Object.assign(this, { db, vault, audit, licenses, notifier, settings, cfg: config, bus, tax });
    this.einvoice = null; // se inyecta después (services/einvoice.js)
    licenses.billing = this;
  }

  /** Datos del adquirente tal como estaban al emitir (para el cobro y el comprobante). */
  billTo(client) {
    const dec = (k) => (client[k + '_enc'] ? this.vault.decrypt(client[k + '_enc'], `clients.${k}:${client.id}`) : '');
    return { name: dec('legal_name') || client.display_name, display_name: client.display_name, doc_type: client.doc_type, doc_number: dec('doc_number'),
      country: client.country || 'PE', region: client.region || null, address: dec('address'), email: dec('email'), kind: client.kind };
  }
  billToOf(inv) {
    if (!inv.bill_to_enc) { const c = this.db.get('SELECT * FROM clients WHERE id = ?', inv.client_id); return c ? this.billTo(c) : null; }
    return JSON.parse(this.vault.decrypt(inv.bill_to_enc, 'invoices.bill_to:' + inv.id));
  }

  remaining(inv) { return Math.max(0, inv.amount_cents - inv.paid_cents - inv.credit_applied_cents); }
  payToken(inv) { return inv.pay_token_enc ? this.vault.decrypt(inv.pay_token_enc, 'invoices.pay_token:' + inv.id) : null; }
  payUrl(inv) { const t = this.payToken(inv); return t ? `${this.cfg.publicUrl}/p/${t}` : ''; }
  balance(clientId) { return this.db.get('SELECT COALESCE(SUM(amount_cents),0) b FROM credits WHERE client_id = ?', clientId).b; }
  invoiceByToken(token) {
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{30,60}$/.test(token)) return null;
    return this.db.get('SELECT * FROM invoices WHERE pay_token_hash = ?', C.sha256(token));
  }

  /* ------------------------------------------------------------ cobros */
  /**
   * Emite un cobro. amount_cents es el PRECIO ingresado; el total a cobrar sale del motor de impuestos según
   * el cliente y tax_mode (incluido | mas_impuesto; por defecto el de la licencia, o "incluido").
   * taxOverride: desglose ya calculado por un tercero (Merchant of Record). No se usa para cobros del Hub.
   */
  createInvoice({ client_id, license_id = null, kind = 'otro', description, periods = 0, amount_cents, tax_mode = null, currency = 'PEN', due_date = null, for_period_end = null, taxOverride = null, external_ref = null }, actor, ip) {
    if (!(amount_cents > 0)) throw new HttpError(400, 'MONTO', 'El monto debe ser mayor a cero.');
    return this.db.tx(() => {
      const client = this.db.get('SELECT * FROM clients WHERE id = ? AND deleted_at IS NULL', client_id);
      if (!client) throw new HttpError(400, 'CLIENTE', 'Cliente no válido.');
      let lic = null;
      if (license_id) { lic = this.licenses.must(license_id); if (lic.client_id !== client_id) throw new HttpError(400, 'LICENCIA', 'La licencia no pertenece a ese cliente.'); }
      const mode = tax_mode || (lic ? lic.tax_mode : 'incluido');
      const tz = lic ? lic.timezone : this.cfg.defaultTimezone;
      const q = taxOverride || this.tax.quote({ client, price_cents: amount_cents, tax_mode: mode, date: T.localDate(Date.now(), tz) });
      if (!(q.total > 0)) throw new HttpError(400, 'MONTO', 'El total a cobrar debe ser mayor a cero.');
      const id = C.newId('inv'), number = 'C-' + String(this.db.nextSeq('invoice')).padStart(6, '0'), token = C.newSecret(32);
      const due = due_date ? T.endOfLocalDay(due_date, tz) : (for_period_end || T.endOfLocalDay(T.addDays(T.localDate(Date.now(), tz), 7), tz));
      this.db.run(`INSERT INTO invoices (id,number,license_id,client_id,kind,description,periods,for_period_end,amount_cents,currency,status,due_at,pay_token_hash,pay_token_enc,created_by,created_at,
          list_price_cents,tax_mode,subtotal_cents,tax_cents,tax_rate_bp,tax_treatment,tax_operation,tax_code,tax_label,tax_country,tax_note,fiscal_doc,bill_to_enc,external_ref)
        VALUES (?,?,?,?,?,?,?,?,?,?,'pendiente',?,?,?,?,?, ?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, id, number, license_id, client_id, kind, description, periods, for_period_end, q.total, currency, due,
      C.sha256(token), this.vault.encrypt(token, 'invoices.pay_token:' + id), actor.id || actor.label, T.nowIso(),
      q.list_price_cents ?? amount_cents, q.tax_mode || mode, q.subtotal, q.tax, q.rate, q.treatment, q.operation, q.code, q.label, q.country, q.note, q.fiscal_doc,
      this.vault.encrypt(JSON.stringify(this.billTo(client)), 'invoices.bill_to:' + id), external_ref);
      this.audit.log({ actor, action: 'cobro.creado', entity: ['invoice', id], ip, data: { number, amount_cents: q.total, subtotal_cents: q.subtotal, tax_cents: q.tax, tax: q.code, treatment: q.treatment, kind, periods, license: lic && lic.code } });
      // Saldo a favor del cliente: se aplica solo.
      // (El saldo está en soles y es dinero que ya recibió el Hub: no se aplica a cobros en otra moneda ni a los del MoR.)
      const bal = currency === 'PEN' && q.treatment !== 'mor' ? this.balance(client_id) : 0;
      if (bal > 0) {
        const use = Math.min(bal, q.total);
        this.db.run('INSERT INTO credits (id,client_id,amount_cents,reason,invoice_id,actor,created_at) VALUES (?,?,?,?,?,?,?)', C.newId('crd'), client_id, -use, 'Aplicado al cobro ' + number, id, 'Sistema', T.nowIso());
        this.db.run('UPDATE invoices SET credit_applied_cents = ? WHERE id = ?', use, id);
        this.settle(id, null, { type: 'sistema', label: 'Saldo a favor' }, ip);
      }
      this.bus.emit('admin', { type: 'invoice', id });
      return this.db.get('SELECT * FROM invoices WHERE id = ?', id);
    });
  }

  /** Cobro abierto de una licencia; si no hay y create=true, emite el de renovación del ciclo actual. */
  openInvoiceForLicense(l, { create = false } = {}) {
    const open = this.db.get("SELECT * FROM invoices WHERE license_id = ? AND status IN ('pendiente','parcial') ORDER BY created_at LIMIT 1", l.id);
    if (open || !create) return open || null;
    return this.createRenewal(l);
  }

  /** Cobro de renovación del ciclo vigente. Idempotente: el índice único impide duplicarlo. */
  createRenewal(l, actor = { type: 'sistema', label: 'Tareas automáticas' }) {
    if (l.interval_unit === 'none' || !(l.price_cents > 0) || l.status === 'cancelada') return null;
    // Si ya existe (aunque esté anulada a propósito por el equipo), no se vuelve a emitir sola para este ciclo.
    const exists = this.db.get("SELECT * FROM invoices WHERE license_id = ? AND kind = 'renovacion' AND for_period_end IS ? ORDER BY created_at DESC LIMIT 1", l.id, l.period_end);
    if (exists) return ['pendiente', 'parcial'].includes(exists.status) ? exists : null;
    const unit = { day: 'día(s)', month: 'mes(es)', year: 'año(s)' }[l.interval_unit];
    if (l.billing_provider && l.billing_provider !== 'hub') return null; // la cobra el Merchant of Record
    return this.createInvoice({
      client_id: l.client_id, license_id: l.id, kind: 'renovacion', periods: 1, amount_cents: l.price_cents, tax_mode: l.tax_mode, for_period_end: l.period_end,
      description: `Renovación · ${l.label} · ${l.interval_count} ${unit}` + (l.period_end ? ` desde el ${fecha(T.nowIso(Date.parse(l.period_end) + 1000), l.timezone)}` : ''),
    }, actor);
  }

  voidInvoice(id, reason, actor, ip) {
    return this.db.tx(() => {
      const inv = this.db.get('SELECT * FROM invoices WHERE id = ?', id);
      if (!inv) throw new HttpError(404, 'NO_ENCONTRADO', 'Cobro no encontrado.');
      if (inv.status === 'anulada') return inv;
      if (inv.paid_cents > 0) throw new HttpError(409, 'TIENE_PAGOS', 'El cobro tiene pagos: primero anula o reembolsa esos pagos.');
      if (inv.status === 'pagada') throw new HttpError(409, 'PAGADA', 'El cobro ya está pagado.');
      if (inv.credit_applied_cents > 0) this.db.run('INSERT INTO credits (id,client_id,amount_cents,reason,invoice_id,actor,created_at) VALUES (?,?,?,?,?,?,?)', C.newId('crd'), inv.client_id, inv.credit_applied_cents, 'Devuelto por anulación de ' + inv.number, id, actor.label, T.nowIso());
      this.db.run("UPDATE invoices SET status = 'anulada', voided_at = ?, void_reason = ?, credit_applied_cents = 0 WHERE id = ?", T.nowIso(), reason, id);
      this.audit.log({ actor, action: 'cobro.anulado', entity: ['invoice', id], ip, data: { number: inv.number, reason } });
      this.bus.emit('admin', { type: 'invoice', id });
      return this.db.get('SELECT * FROM invoices WHERE id = ?', id);
    });
  }

  /**
   * Vuelve a calcular el impuesto de un cobro que aún no recibió dinero (por ejemplo, si se corrigió el país
   * o el documento del cliente). Con cualquier abono, el desglose queda fijo. Devuelve el cobro actualizado.
   */
  refreshTax(inv) {
    if (!inv || inv.status !== 'pendiente' || inv.paid_cents > 0 || inv.credit_applied_cents > 0 || inv.tax_treatment === 'mor' || inv.list_price_cents == null) return inv;
    return this.db.tx(() => {
      const client = this.db.get('SELECT * FROM clients WHERE id = ?', inv.client_id);
      const lic = inv.license_id ? this.licenses.get(inv.license_id) : null;
      const q = this.tax.quote({ client, price_cents: inv.list_price_cents, tax_mode: inv.tax_mode, date: T.localDate(Date.now(), lic ? lic.timezone : this.cfg.defaultTimezone) });
      const billTo = this.vault.encrypt(JSON.stringify(this.billTo(client)), 'invoices.bill_to:' + inv.id);
      const same = q.total === inv.amount_cents && q.subtotal === inv.subtotal_cents && q.treatment === inv.tax_treatment && q.fiscal_doc === inv.fiscal_doc && q.operation === inv.tax_operation;
      this.db.run(`UPDATE invoices SET amount_cents=?, subtotal_cents=?, tax_cents=?, tax_rate_bp=?, tax_treatment=?, tax_operation=?, tax_code=?, tax_label=?, tax_country=?, tax_note=?, fiscal_doc=?, bill_to_enc=? WHERE id=?`,
        q.total, q.subtotal, q.tax, q.rate, q.treatment, q.operation, q.code, q.label, q.country, q.note, q.fiscal_doc, billTo, inv.id);
      if (!same) {
        this.audit.log({ actor: { type: 'sistema', label: 'Impuestos' }, action: 'cobro.impuesto_recalculado', entity: ['invoice', inv.id], data: { number: inv.number, de: inv.amount_cents, a: q.total, tax: q.code, treatment: q.treatment } });
        this.bus.emit('admin', { type: 'invoice', id: inv.id });
      }
      return this.db.get('SELECT * FROM invoices WHERE id = ?', inv.id);
    });
  }

  /** Recalcula los cobros abiertos sin pagos de un cliente (tras editar sus datos). */
  refreshOpenForClient(clientId) {
    let n = 0;
    for (const inv of this.db.all("SELECT * FROM invoices WHERE client_id = ? AND status = 'pendiente' AND paid_cents = 0 AND credit_applied_cents = 0", clientId)) {
      const before = inv.amount_cents; const after = this.refreshTax(inv); if (after.amount_cents !== before) n++;
    }
    return n;
  }

  /** Recalcula el estado de un cobro después de un abono. Si queda pagado, extiende la licencia. */
  settle(invoiceId, paymentId, actor, ip) {
    const inv = this.db.get('SELECT * FROM invoices WHERE id = ?', invoiceId);
    const covered = inv.paid_cents + inv.credit_applied_cents;
    if (inv.status === 'pagada') {
      // Llegó dinero a un cobro ya pagado (doble pago, pago tardío): todo va a saldo a favor.
      return { invoice: inv, extended: false };
    }
    if (covered < inv.amount_cents) {
      this.db.run("UPDATE invoices SET status = ? WHERE id = ?", covered > 0 ? 'parcial' : 'pendiente', invoiceId);
      return { invoice: this.db.get('SELECT * FROM invoices WHERE id = ?', invoiceId), extended: false };
    }
    this.db.run("UPDATE invoices SET status = 'pagada', paid_at = ? WHERE id = ?", T.nowIso(), invoiceId);
    const over = covered - inv.amount_cents;
    if (over > 0) this.db.run('INSERT INTO credits (id,client_id,amount_cents,reason,payment_id,invoice_id,actor,created_at) VALUES (?,?,?,?,?,?,?,?)', C.newId('crd'), inv.client_id, over, 'Pago en exceso en ' + inv.number, paymentId, invoiceId, 'Sistema', T.nowIso());
    let extended = false;
    if (inv.license_id && inv.periods > 0) {
      const lic = this.licenses.get(inv.license_id);
      if (lic.status === 'cancelada') this.bus.emit('admin', { type: 'warning', message: `Se pagó ${inv.number} de una licencia cancelada (${lic.code}). Revisa si corresponde reembolsar.` });
      else { this.licenses.grant(inv.license_id, { kind: 'pago', periods: inv.periods, invoice_id: invoiceId, payment_id: paymentId, note: 'Cobro ' + inv.number }, actor, ip); extended = true; }
    }
    return { invoice: this.db.get('SELECT * FROM invoices WHERE id = ?', invoiceId), extended };
  }

  /* ------------------------------------------------------------ pagos */
  registerPayment({ invoice_id, method, amount_cents, operation_ref = null, paid_on = null, note = null, source = 'panel', payer_email = null }, actor, ip) {
    if (!MANUAL.includes(method)) throw new HttpError(400, 'METODO', 'Medio de pago no válido.');
    if (!(amount_cents > 0)) throw new HttpError(400, 'MONTO', 'El monto debe ser mayor a cero.');
    if (['yape', 'plin', 'transferencia', 'deposito'].includes(method) && !normRef(operation_ref)) throw new HttpError(400, 'OPERACION', 'Indica el número de operación.');
    return this.db.tx(() => {
      const inv = this.db.get('SELECT * FROM invoices WHERE id = ?', invoice_id);
      if (!inv || !['pendiente', 'parcial'].includes(inv.status)) throw new HttpError(409, 'COBRO_CERRADO', 'Ese cobro no admite pagos (pagado o anulado).');
      const norm = normRef(operation_ref);
      if (norm && this.db.get("SELECT 1 FROM payments WHERE method = ? AND operation_norm = ? AND status IN ('por_verificar','aprobado','reembolsado')", method, norm)) {
        throw new HttpError(409, 'OPERACION_DUPLICADA', 'Ese número de operación ya fue registrado.');
      }
      // Un mismo cobro no acumula reportes pendientes sin fin (abuso del formulario público).
      if (source === 'cliente' && this.db.get("SELECT COUNT(*) n FROM payments WHERE invoice_id = ? AND status = 'por_verificar'", inv.id).n >= 3) throw new HttpError(429, 'DEMASIADOS', 'Ya hay reportes en revisión para este cobro. Te avisaremos pronto.');
      const id = C.newId('pay'), now = T.nowIso();
      this.db.run(`INSERT INTO payments (id,invoice_id,license_id,client_id,method,source,amount_cents,currency,status,operation_ref,operation_norm,paid_on,payer_email_enc,note,created_by,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?,'por_verificar',?,?,?,?,?,?,?,?)`, id, inv.id, inv.license_id, inv.client_id, method, source, amount_cents, inv.currency, operation_ref ? String(operation_ref).slice(0, 60) : null, norm, paid_on,
      payer_email ? this.vault.encrypt(payer_email, 'payments.payer_email:' + id) : null, note, actor.id || null, now, now);
      this.audit.log({ actor, action: 'pago.registrado', entity: ['payment', id], ip, data: { invoice: inv.number, method, amount_cents, source } });
      this.bus.emit('admin', { type: 'payment', id, status: 'por_verificar' });
      return this.db.get('SELECT * FROM payments WHERE id = ?', id);
    });
  }

  approvePayment(id, actor, ip, { skipFourEyes = false } = {}) {
    const res = this.db.tx(() => {
      const p = this.db.get('SELECT * FROM payments WHERE id = ?', id);
      if (!p) throw new HttpError(404, 'NO_ENCONTRADO', 'Pago no encontrado.');
      if (p.status !== 'por_verificar') throw new HttpError(409, 'ESTADO', 'Ese pago ya fue revisado.');
      if (!skipFourEyes && this.settings.get('four_eyes') && actor.id && p.created_by === actor.id) throw new HttpError(403, 'CUATRO_OJOS', 'Por control interno, otra persona debe aprobar el pago que registraste.');
      const number = 'R-' + String(this.db.nextSeq('receipt')).padStart(6, '0');
      this.db.run("UPDATE payments SET status = 'aprobado', number = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?", number, actor.id || actor.label, T.nowIso(), T.nowIso(), id);
      this.db.run('UPDATE invoices SET paid_cents = paid_cents + ? WHERE id = ?', p.amount_cents, p.invoice_id);
      const before = this.db.get('SELECT status FROM invoices WHERE id = ?', p.invoice_id).status;
      if (before === 'pagada') {
        this.db.run('INSERT INTO credits (id,client_id,amount_cents,reason,payment_id,invoice_id,actor,created_at) VALUES (?,?,?,?,?,?,?,?)', C.newId('crd'), p.client_id, p.amount_cents, 'Pago recibido sobre cobro ya pagado', id, p.invoice_id, 'Sistema', T.nowIso());
        this.bus.emit('admin', { type: 'warning', message: `Llegó un pago (${money(p.amount_cents)}) sobre un cobro ya pagado. Quedó como saldo a favor: revisa si corresponde reembolsar.` });
      }
      const r = this.settle(p.invoice_id, id, actor, ip);
      // Comprobante electrónico (boleta/factura) por el monto recibido. Se envía a SUNAT después, con reintentos.
      const doc = this.einvoice ? this.einvoice.onPaymentApproved(this.db.get('SELECT * FROM payments WHERE id = ?', id), this.db.get('SELECT * FROM invoices WHERE id = ?', p.invoice_id)) : null;
      this.audit.log({ actor, action: 'pago.aprobado', entity: ['payment', id], ip, data: { number, amount_cents: p.amount_cents, invoice: r.invoice.number, extended: r.extended, comprobante: doc ? `${doc.series}-${doc.number}` : undefined } });
      // Aviso de pago recibido (con la nueva fecha de vigencia).
      const client = this.db.get('SELECT * FROM clients WHERE id = ?', p.client_id);
      const lic = p.license_id ? this.licenses.get(p.license_id) : null;
      const product = lic ? this.db.get('SELECT name FROM products WHERE id = ?', lic.product_id) : null;
      if (client && !client.anonymized_at) this.notifier.queue({ template: 'pago_recibido', client, license: lic, dedupe: 'pago:' + id,
        vars: { monto: money(p.amount_cents, p.currency), servicio: lic ? `${product.name} (${lic.label})` : r.invoice.description, fecha: lic && lic.period_end ? fecha(lic.period_end, lic.timezone) : (lic ? 'sin vencimiento' : '—'), recibo: number } });
      this.bus.emit('admin', { type: 'payment', id, status: 'aprobado' });
      return { payment: this.db.get('SELECT * FROM payments WHERE id = ?', id), invoice: r.invoice, license: lic, document: doc };
    });
    if (res.document && this.einvoice) this.einvoice.kick();
    return res;
  }

  rejectPayment(id, reason, actor, ip) {
    return this.db.tx(() => {
      const p = this.db.get('SELECT * FROM payments WHERE id = ?', id);
      if (!p) throw new HttpError(404, 'NO_ENCONTRADO', 'Pago no encontrado.');
      if (p.status !== 'por_verificar') throw new HttpError(409, 'ESTADO', 'Ese pago ya fue revisado.');
      this.db.run("UPDATE payments SET status = 'rechazado', reject_reason = ?, reviewed_by = ?, reviewed_at = ?, updated_at = ? WHERE id = ?", reason, actor.id || actor.label, T.nowIso(), T.nowIso(), id);
      this.audit.log({ actor, action: 'pago.rechazado', entity: ['payment', id], ip, data: { reason } });
      const client = this.db.get('SELECT * FROM clients WHERE id = ?', p.client_id);
      const inv = this.db.get('SELECT description FROM invoices WHERE id = ?', p.invoice_id);
      if (client && !client.anonymized_at) this.notifier.queue({ template: 'pago_rechazado', client, dedupe: 'rechazo:' + id, vars: { monto: money(p.amount_cents), servicio: inv.description, motivo: reason } });
      this.bus.emit('admin', { type: 'payment', id, status: 'rechazado' });
      return this.db.get('SELECT * FROM payments WHERE id = ?', id);
    });
  }

  /** Anula o reembolsa un pago aprobado y revierte la vigencia que dio. */
  reversePayment(id, { reason, kind = 'anulado' }, actor, ip) {
    if (!['anulado', 'reembolsado'].includes(kind)) throw new HttpError(400, 'TIPO', 'Tipo no válido.');
    return this.db.tx(() => {
      const p = this.db.get('SELECT * FROM payments WHERE id = ?', id);
      if (!p) throw new HttpError(404, 'NO_ENCONTRADO', 'Pago no encontrado.');
      if (p.status === kind) return p;
      if (p.status !== 'aprobado') throw new HttpError(409, 'ESTADO', 'Solo se anula o reembolsa un pago aprobado.');
      const inv = this.db.get('SELECT * FROM invoices WHERE id = ?', p.invoice_id);
      const oldOver = Math.max(0, inv.paid_cents + inv.credit_applied_cents - inv.amount_cents);
      const newPaid = inv.paid_cents - p.amount_cents;
      const newOver = Math.max(0, newPaid + inv.credit_applied_cents - inv.amount_cents);
      this.db.run('UPDATE payments SET status = ?, reversed_at = ?, reverse_reason = ?, updated_at = ? WHERE id = ?', kind, T.nowIso(), reason, T.nowIso(), id);
      if (oldOver - newOver > 0) this.db.run('INSERT INTO credits (id,client_id,amount_cents,reason,payment_id,invoice_id,actor,created_at) VALUES (?,?,?,?,?,?,?,?)', C.newId('crd'), p.client_id, -(oldOver - newOver), 'Reverso de saldo por ' + kind + ' de ' + (p.number || p.id), id, inv.id, actor.label, T.nowIso());
      const stillPaid = newPaid + inv.credit_applied_cents >= inv.amount_cents;
      this.db.run('UPDATE invoices SET paid_cents = ?, status = ?, paid_at = CASE WHEN ? THEN paid_at ELSE NULL END WHERE id = ?',
        newPaid, stillPaid ? 'pagada' : (newPaid + inv.credit_applied_cents > 0 ? 'parcial' : 'pendiente'), stillPaid ? 1 : 0, inv.id);
      if (inv.status === 'pagada' && !stillPaid) {
        for (const g of this.db.all("SELECT * FROM license_grants WHERE invoice_id = ? AND kind = 'pago' AND id NOT IN (SELECT reverses_id FROM license_grants WHERE reverses_id IS NOT NULL)", inv.id)) {
          this.licenses.reverseGrant(g.id, `Pago ${p.number || ''} ${kind}: ${reason}`.trim(), actor, ip);
        }
      }
      // Si el pago tenía comprobante, se emite la nota de crédito (anulación o devolución total).
      const note = this.einvoice ? this.einvoice.onPaymentReversed(p, kind, reason, actor) : null;
      this.audit.log({ actor, action: 'pago.' + kind, entity: ['payment', id], ip, data: { number: p.number, amount_cents: p.amount_cents, reason, nota_credito: note ? `${note.series}-${note.number}` : undefined } });
      this.bus.emit('admin', { type: 'payment', id, status: kind });
      if (note) setImmediate(() => this.einvoice.kick());
      return this.db.get('SELECT * FROM payments WHERE id = ?', id);
    });
  }

  /**
   * Cargo confirmado por la pasarela (consultado directo a su API). Idempotente por id de cargo.
   * Si el cobro ya no estaba abierto, el dinero queda como saldo a favor (no se pierde).
   */
  applyGatewayCharge(c, { invoice_id }, ip) {
    const actor = { type: 'pasarela', id: null, label: 'Culqi' };
    return this.db.tx(() => {
      const prev = this.db.get("SELECT * FROM payments WHERE method = 'culqi' AND operation_norm = ?", normRef(c.id));
      if (prev) return { payment: prev, duplicate: true };
      const inv = this.db.get('SELECT * FROM invoices WHERE id = ?', invoice_id);
      if (!inv) throw new HttpError(404, 'COBRO', 'El cargo no corresponde a ningún cobro.');
      const id = C.newId('pay'), now = T.nowIso();
      this.db.run(`INSERT INTO payments (id,invoice_id,license_id,client_id,method,provider,source,amount_cents,currency,status,operation_ref,operation_norm,paid_on,payer_email_enc,card_label,created_by,created_at,updated_at)
        VALUES (?,?,?,?, 'culqi','culqi','pasarela', ?, ?, 'por_verificar', ?, ?, ?, ?, ?, NULL, ?, ?)`, id, inv.id, inv.license_id, inv.client_id, c.amountCents, c.currency || inv.currency, c.id, normRef(c.id), T.localDate(Date.now()),
      c.email ? this.vault.encrypt(c.email, 'payments.payer_email:' + id) : null, c.cardLabel || null, now, now);
      if (inv.status === 'anulada') {
        // cobro anulado: el pago se aprueba pero va íntegro a saldo a favor
        const number = 'R-' + String(this.db.nextSeq('receipt')).padStart(6, '0');
        this.db.run("UPDATE payments SET status = 'aprobado', number = ?, reviewed_by = 'Culqi', reviewed_at = ?, note = 'Cobro anulado: monto enviado a saldo a favor' WHERE id = ?", number, now, id);
        this.db.run('INSERT INTO credits (id,client_id,amount_cents,reason,payment_id,invoice_id,actor,created_at) VALUES (?,?,?,?,?,?,?,?)', C.newId('crd'), inv.client_id, c.amountCents, 'Pago sobre cobro anulado ' + inv.number, id, inv.id, 'Sistema', now);
        this.audit.log({ actor, action: 'pago.aprobado', entity: ['payment', id], ip, data: { number, note: 'cobro anulado → saldo' } });
        this.bus.emit('admin', { type: 'warning', message: `Llegó un pago con tarjeta sobre el cobro anulado ${inv.number}. Quedó como saldo a favor.` });
        return { payment: this.db.get('SELECT * FROM payments WHERE id = ?', id) };
      }
      return this.approvePayment(id, actor, ip, { skipFourEyes: true });
    });
  }

  /* ------------------------------------------------------------ Merchant of Record (Paddle, Lemon Squeezy, Stripe) */
  /**
   * Pago confirmado por un Merchant of Record. El MoR es el vendedor ante el cliente final: calcula, cobra y
   * declara el impuesto de su país (IVA/VAT/sales tax). Aquí se registra lo que informó (base, impuesto, total y
   * moneda) para extender la licencia. No se emite boleta/factura por cada venta: a quien se le factura es al MoR,
   * por cada liquidación (exportación de servicios). Idempotente por el id de la transacción del MoR.
   */
  applyMorPayment(ev, lic) {
    const actor = { type: 'pasarela', id: null, label: ev.providerLabel };
    return this.db.tx(() => {
      const ref = ev.provider.toUpperCase() + normRef(ev.paymentId);
      const prev = this.db.get("SELECT * FROM payments WHERE method = 'mor' AND operation_norm = ?", ref);
      if (prev) return { payment: prev, duplicate: true };
      if (!(ev.totalCents > 0)) throw new HttpError(400, 'MONTO', 'El aviso no trae un total válido.');
      if (ev.subtotalCents + ev.taxCents !== ev.totalCents) throw new HttpError(400, 'MONTO', 'Base + impuesto no coincide con el total informado.');
      const inv = this.createInvoice({
        client_id: lic.client_id, license_id: lic.id, kind: lic.activated_at ? 'renovacion' : 'alta', periods: lic.interval_unit === 'none' ? 0 : 1,
        description: `${ev.providerLabel} · ${lic.label} · ${ev.description || 'suscripción'}`.slice(0, 200), amount_cents: ev.totalCents, currency: ev.currency, external_ref: ev.paymentId,
        taxOverride: { total: ev.totalCents, subtotal: ev.subtotalCents, tax: ev.taxCents, rate: 0, treatment: 'mor', operation: 'mor', code: 'MOR-' + ev.provider.toUpperCase(),
          label: ev.taxCents ? `Impuesto calculado por ${ev.providerLabel}` : `Sin impuesto (${ev.providerLabel})`, country: ev.country || null, fiscal_doc: 'ninguno',
          note: `${ev.providerLabel} es el Merchant of Record: cobra y declara el impuesto del país del cliente.`, list_price_cents: ev.subtotalCents, tax_mode: 'mas_impuesto' },
      }, actor);
      const id = C.newId('pay'), now = T.nowIso();
      this.db.run(`INSERT INTO payments (id,invoice_id,license_id,client_id,method,provider,source,amount_cents,currency,status,operation_ref,operation_norm,paid_on,payer_email_enc,note,created_by,created_at,updated_at)
        VALUES (?,?,?,?,'mor',?,'pasarela',?,?,'por_verificar',?,?,?,?,?,NULL,?,?)`, id, inv.id, lic.id, lic.client_id, ev.provider, ev.totalCents, ev.currency, String(ev.paymentId).slice(0, 60), ref,
      T.localDate(ev.occurredAt ? Date.parse(ev.occurredAt) : Date.now()), ev.email ? this.vault.encrypt(ev.email, 'payments.payer_email:' + id) : null, `Cobrado por ${ev.providerLabel}`, now, now);
      return this.approvePayment(id, actor, null, { skipFourEyes: true });
    });
  }

  /** Reembolso o contracargo informado por el MoR: revierte el pago y la vigencia. */
  applyMorRefund(ev) {
    const ref = ev.provider.toUpperCase() + normRef(ev.paymentId);
    const p = this.db.get("SELECT * FROM payments WHERE method = 'mor' AND operation_norm = ?", ref);
    if (!p) return { missing: true };
    if (p.status !== 'aprobado') return { payment: p, duplicate: true };
    if (ev.refundCents && ev.refundCents < p.amount_cents) {
      this.bus.emit('admin', { type: 'warning', message: `${ev.providerLabel} informó un reembolso parcial (${money(ev.refundCents, p.currency)} de ${money(p.amount_cents, p.currency)}). Revísalo: la licencia no se modificó.` });
      this.audit.log({ actor: { type: 'pasarela', label: ev.providerLabel }, action: 'pago.reembolso_parcial', entity: ['payment', p.id], data: { refund_cents: ev.refundCents } });
      return { payment: p, partial: true };
    }
    return { payment: this.reversePayment(p.id, { reason: `${ev.kind === 'chargeback' ? 'Contracargo' : 'Reembolso'} informado por ${ev.providerLabel}`, kind: 'reembolsado' }, { type: 'pasarela', label: ev.providerLabel }) };
  }
}

module.exports = { Billing, MANUAL, normRef };
