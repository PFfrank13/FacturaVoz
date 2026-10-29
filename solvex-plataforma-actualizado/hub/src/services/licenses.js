'use strict';
/**
 * Motor de licencias.
 *
 * ESTADOS
 *   pendiente  → creada, aún no activada (implementación o esperando el primer pago).
 *   prueba     → periodo de prueba gratuito.
 *   activa     → pagada y vigente.
 *   gracia     → venció; sigue funcionando con aviso hasta el último día de gracia.
 *   suspendida → corte. "auto" (falta de pago: se levanta sola al pagar) o "manual" (decisión de Solvex: solo la levanta una persona).
 *   cancelada  → baja definitiva (no se reactiva con un pago; queda registrado para revisión).
 *
 * REGLA DE ORO: el estado real se CALCULA a partir de las fechas (effective()). La columna `status`
 * es una copia para listar y avisar. Si las tareas programadas se retrasan o el servidor estuvo
 * apagado, la respuesta a los productos sigue siendo correcta porque se calcula en el momento.
 *
 * MODO que recibe el producto en el token:
 *   full        → todo funciona.
 *   warning     → todo funciona + aviso de pago pendiente (gracia).
 *   restricted  → suspendida/cancelada: el personal no opera; el dueño solo entra a pagar o exportar sus datos.
 *   blocked     → pendiente: el sistema aún no está habilitado.
 */
const C = require('../lib/crypto');
const T = require('../lib/time');
const jws = require('../lib/jws');
const { HttpError } = require('../http/app');

const MODE = { pendiente: 'blocked', prueba: 'full', activa: 'full', gracia: 'warning', suspendida: 'restricted', cancelada: 'restricted' };
const ALLOWED = new Set(['prueba', 'activa', 'gracia']);

/** Fin de la gracia: tras una prueba no hay gracia; tras un periodo pagado, grace_days días de calendario. */
function graceEndOf(l) {
  if (!l.period_end) return null;
  if (l.is_trial) return l.period_end;
  return T.endOfLocalDay(T.addDays(T.localDate(l.period_end, l.timezone), l.grace_days), l.timezone);
}

/** Estado real en el instante `now` (ms). Función pura: misma entrada, misma salida. */
function effective(l, now = Date.now()) {
  if (l.status === 'cancelada') return { status: 'cancelada', kind: null };
  if (!l.activated_at) return { status: 'pendiente', kind: null };
  if (l.suspension_kind === 'manual') return { status: 'suspendida', kind: 'manual' };
  if (!l.period_end) return { status: 'activa', kind: null, perpetual: true };
  if (now <= Date.parse(l.period_end)) return { status: l.is_trial ? 'prueba' : 'activa', kind: null };
  const ge = l.grace_end || graceEndOf(l);
  if (!l.auto_cut || now <= Date.parse(ge)) return { status: 'gracia', kind: null, cutAt: l.auto_cut ? ge : null };
  return { status: 'suspendida', kind: 'auto' };
}

class Licenses {
  constructor({ db, vault, audit, outbox, notifier, settings, config, bus }) {
    Object.assign(this, { db, vault, audit, outbox, notifier, settings, cfg: config, bus });
    outbox.tokenFor = (lic, inst) => this.token(lic, { aud: inst.id });
    this.billing = null; // se inyecta (para el enlace de pago en avisos y tokens)
  }

  get(id) { return this.db.get('SELECT * FROM licenses WHERE id = ?', id); }
  must(id) { const l = this.get(id); if (!l) throw new HttpError(404, 'NO_ENCONTRADO', 'Licencia no encontrada.'); return l; }

  /* ------------------------------------------------------------ creación */
  /**
   * start: 'prueba' | 'pendiente' | 'cobro' (emite el primer cobro; se activa sola al pagarse) | 'cortesia' (activa N ciclos sin cobro, con motivo)
   */
  create(input, actor, ip) {
    const plan = this.db.get('SELECT * FROM plans WHERE id = ?', input.plan_id);
    if (!plan || !plan.active) throw new HttpError(400, 'PLAN', 'Plan no válido o inactivo.');
    const product = this.db.get('SELECT * FROM products WHERE id = ?', plan.product_id);
    if (product.status === 'retirado') throw new HttpError(400, 'PRODUCTO', 'Ese producto está retirado.');
    const client = this.db.get('SELECT * FROM clients WHERE id = ? AND deleted_at IS NULL', input.client_id);
    if (!client) throw new HttpError(400, 'CLIENTE', 'Cliente no válido.');
    if (input.instance_id) {
      const inst = this.db.get('SELECT * FROM instances WHERE id = ?', input.instance_id);
      if (!inst || inst.product_id !== product.id) throw new HttpError(400, 'INSTANCIA', 'La instancia no corresponde a ese producto.');
      if (!input.tenant_ref) throw new HttpError(400, 'TENANT', 'Indica el identificador del negocio dentro del sistema (por ejemplo, el slug de la barbería).');
    }
    const tz = input.timezone || this.cfg.defaultTimezone;
    if (!T.isValidTz(tz)) throw new HttpError(400, 'ZONA', 'Zona horaria no válida.');
    const id = C.newId('lic'), now = T.nowIso();
    let plainKey = null;

    const result = this.db.tx(() => {
      const code = 'LIC-' + String(this.db.nextSeq('license')).padStart(5, '0');
      const row = {
        id, code, client_id: client.id, product_id: product.id, plan_id: plan.id, instance_id: input.instance_id || null,
        tenant_ref: input.tenant_ref || null, label: input.label || client.display_name, status: 'pendiente',
        grace_days: input.grace_days ?? plan.grace_days, auto_cut: input.auto_cut === false ? 0 : 1, auto_invoice: input.auto_invoice === false ? 0 : 1,
        timezone: tz, price_cents: input.price_cents ?? plan.price_cents, currency: plan.currency, interval_unit: plan.interval_unit, interval_count: plan.interval_count,
        tax_mode: input.tax_mode || plan.tax_mode || 'incluido', billing_provider: input.billing_provider || 'hub',
        features: JSON.stringify(Object.assign({}, JSON.parse(plan.features || '{}'), input.features || {})),
        max_activations: input.max_activations || 1, created_at: now, updated_at: now,
      };
      if (product.kind === 'instalable') { plainKey = 'SLX-' + C.randomCode(5) + '-' + C.randomCode(5) + '-' + C.randomCode(5) + '-' + C.randomCode(5); row.key_hash = C.sha256(plainKey); row.key_prefix = plainKey.slice(0, 10); }
      this.db.run(`INSERT INTO licenses (id,code,client_id,product_id,plan_id,instance_id,tenant_ref,label,status,grace_days,auto_cut,auto_invoice,timezone,price_cents,currency,interval_unit,interval_count,tax_mode,billing_provider,features,max_activations,key_hash,key_prefix,created_at,updated_at)
        VALUES (@id,@code,@client_id,@product_id,@plan_id,@instance_id,@tenant_ref,@label,@status,@grace_days,@auto_cut,@auto_invoice,@timezone,@price_cents,@currency,@interval_unit,@interval_count,@tax_mode,@billing_provider,@features,@max_activations,@key_hash,@key_prefix,@created_at,@updated_at)`,
      Object.assign({ key_hash: null, key_prefix: null }, row));
      this.db.run('INSERT INTO license_events (license_id,from_status,to_status,reason,actor,created_at) VALUES (?,?,?,?,?,?)', id, null, 'pendiente', 'Licencia creada', actor.label, now);
      this.audit.log({ actor, action: 'licencia.creada', entity: ['license', id], ip, data: { code, product: product.code, plan: plan.code, start: input.start } });
      const out = { license: this.get(id), invoice: null };
      if (input.start && input.start !== 'pendiente') Object.assign(out, this.activate(id, { mode: input.start, periods: input.periods || 1, note: input.note, startDate: input.start_date }, actor, ip));
      else this.outbox.licenseChanged(this.get(id), 'creada');
      return out;
    });
    result.license = this.get(id);
    result.licenseKey = plainKey; // se muestra UNA sola vez
    return result;
  }

  /** Activa una licencia pendiente: prueba, cortesía o emitiendo el primer cobro. */
  activate(id, { mode, periods = 1, note, startDate }, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (l.activated_at || l.status !== 'pendiente') throw new HttpError(409, 'ESTADO', 'Solo se activa una licencia pendiente.');
      if (this.db.get("SELECT 1 FROM invoices WHERE license_id = ? AND kind = 'alta' AND status IN ('pendiente','parcial')", id)) throw new HttpError(409, 'COBRO_ABIERTO', 'Ya hay un cobro de alta abierto: al pagarse, la licencia se activa sola.');
      const plan = this.db.get('SELECT * FROM plans WHERE id = ?', l.plan_id);
      const start = startDate && T.isDate(startDate) ? startDate : T.localDate(Date.now(), l.timezone);
      if (mode === 'prueba') {
        const days = plan.trial_days || 0;
        if (days < 1) throw new HttpError(400, 'SIN_PRUEBA', 'El plan no tiene días de prueba.');
        const end = T.endOfLocalDay(T.addDays(start, days - 1), l.timezone);
        this.db.run('UPDATE licenses SET is_trial = 1, period_end = ?, grace_end = ?, anchor_day = ?, activated_at = ?, updated_at = ? WHERE id = ?', end, end, +start.slice(8, 10), T.nowIso(), T.nowIso(), id);
        this.db.run('INSERT INTO license_grants (id,license_id,kind,from_end,to_end,periods,note,actor,created_at) VALUES (?,?,?,?,?,?,?,?,?)', C.newId('grt'), id, 'prueba', null, end, 0, `Prueba de ${days} días`, actor.label, T.nowIso());
        this.sync(id, actor, 'Inicio de prueba', ip);
        return { license: this.get(id), invoice: null };
      }
      if (mode === 'cortesia') {
        if (!note || String(note).trim().length < 5) throw new HttpError(400, 'MOTIVO', 'Indica el motivo de la activación sin cobro.');
        this.grant(id, { kind: 'cortesia', periods, note, startDate: start }, actor, ip);
        return { license: this.get(id), invoice: null };
      }
      if (mode === 'cobro') {
        if (!this.billing) throw new Error('billing no inyectado');
        if (l.billing_provider !== 'hub') throw new HttpError(409, 'COBRA_MOR', 'Esta licencia se cobra por un Merchant of Record: se activa sola cuando llega su primer pago.');
        const amount = l.price_cents * periods + (plan.setup_cents || 0);
        if (amount <= 0) throw new HttpError(400, 'MONTO', 'El plan no tiene precio: usa activación de cortesía.');
        const inv = this.billing.createInvoice({
          client_id: l.client_id, license_id: id, kind: 'alta', periods,
          description: `Alta · ${l.label} · ${periods} ciclo(s)` + (plan.setup_cents ? ' + implementación' : ''), amount_cents: amount, tax_mode: l.tax_mode,
          due_date: start,
        }, actor, ip);
        this.outbox.licenseChanged(this.get(id), 'esperando primer pago');
        return { license: this.get(id), invoice: inv };
      }
      throw new HttpError(400, 'MODO', 'Modo de activación no válido.');
    });
  }

  /* ------------------------------------------------------------ vigencia */
  /**
   * Extiende la vigencia. kind: 'pago' | 'cortesia' | 'ajuste'.
   * - Si la licencia está vigente (prueba/activa/gracia): el nuevo ciclo continúa desde el fin del anterior
   *   (en gracia ya usó esos días; tras una prueba, el ciclo pagado empieza al terminar la prueba).
   * - Si estaba suspendida (o sin fecha): el ciclo empieza el día del pago (restore_anchor = fecha_pago).
   */
  grant(id, { kind, periods = 1, days = null, note = null, invoice_id = null, payment_id = null, startDate = null }, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (l.status === 'cancelada') throw new HttpError(409, 'CANCELADA', 'La licencia está cancelada: no se extiende.');
      if (l.interval_unit === 'none') {
        // Licencia perpetua (compra): queda activa sin fecha de fin.
        this.db.run("UPDATE licenses SET period_end = NULL, grace_end = NULL, is_trial = 0, suspension_kind = CASE WHEN suspension_kind = 'auto' THEN NULL ELSE suspension_kind END, activated_at = COALESCE(activated_at, ?), updated_at = ?, version = version + 1 WHERE id = ?", T.nowIso(), T.nowIso(), id);
        this.db.run('INSERT INTO license_grants (id,license_id,kind,from_end,to_end,periods,invoice_id,payment_id,note,actor,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          C.newId('grt'), id, kind, l.period_end, null, periods, invoice_id, payment_id, note || 'Licencia perpetua', actor.label, T.nowIso());
        return this.sync(id, actor, kind === 'pago' ? 'Pago registrado' : 'Vigencia extendida', ip, true);
      }
      const eff = effective(l);
      const anchorMode = this.settings.get('restore_anchor');
      let start, anchor;
      if (l.period_end && (ALLOWED.has(eff.status) || (eff.status === 'suspendida' && anchorMode === 'continuar'))) {
        start = T.addDays(T.localDate(l.period_end, l.timezone), 1); anchor = l.anchor_day || +start.slice(8, 10);
        // Si el inicio no cae en el día ancla (por una extensión en días), el ancla pasa a ser ese día:
        // así cada ciclo pagado dura completo y nunca se "acorta" para alinearse con la fecha anterior.
        const [sy, sm, sd] = start.split('-').map(Number);
        if (l.interval_unit !== 'day' && sd !== Math.min(anchor, T.daysInMonth(sy, sm))) anchor = sd;
      } else {
        start = startDate || T.localDate(Date.now(), l.timezone); anchor = +start.slice(8, 10);
      }
      const last = days ? T.addDays(start, days - 1) : T.lastCoveredDay(start, l.interval_unit, l.interval_count, periods, anchor);
      const end = T.endOfLocalDay(last, l.timezone);
      const next = Object.assign({}, l, { period_end: end, is_trial: 0 });
      const ge = graceEndOf(next);
      this.db.run(`UPDATE licenses SET period_end = ?, grace_end = ?, is_trial = 0, anchor_day = ?,
          suspension_kind = CASE WHEN suspension_kind = 'auto' THEN NULL ELSE suspension_kind END,
          suspension_reason = CASE WHEN suspension_kind = 'auto' THEN NULL ELSE suspension_reason END,
          activated_at = COALESCE(activated_at, ?), updated_at = ?, version = version + 1 WHERE id = ?`, end, ge, anchor, T.nowIso(), T.nowIso(), id);
      const gid = C.newId('grt');
      this.db.run('INSERT INTO license_grants (id,license_id,kind,from_end,to_end,periods,invoice_id,payment_id,note,actor,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        gid, id, kind, l.period_end, end, days ? 0 : periods, invoice_id, payment_id, note || (days ? `${days} día(s)` : `${periods} ciclo(s)`), actor.label, T.nowIso());
      this.audit.log({ actor, action: 'licencia.vigencia_extendida', entity: ['license', id], ip, data: { kind, periods, days, from: l.period_end, to: end } });
      if (l.suspension_kind === 'manual') this.bus.emit('admin', { type: 'warning', message: `${l.code}: se registró pago pero sigue suspendida manualmente.` });
      return this.sync(id, actor, kind === 'pago' ? 'Pago registrado' : 'Vigencia extendida', ip, true);
    });
  }

  /** Revierte una extensión (reembolso o anulación de pago). */
  reverseGrant(grantId, reason, actor, ip) {
    return this.db.tx(() => {
      const g = this.db.get('SELECT * FROM license_grants WHERE id = ?', grantId);
      if (!g || g.kind === 'reverso') throw new HttpError(404, 'NO_ENCONTRADO', 'Extensión no encontrada.');
      if (this.db.get('SELECT 1 FROM license_grants WHERE reverses_id = ?', grantId)) return this.get(g.license_id);
      const l = this.must(g.license_id);
      let end;
      const expired = T.nowIso(Date.now() - 1000); // "ya vencida" (sin cobertura desde este instante)
      if (l.interval_unit === 'none') end = expired;
      else if (l.period_end === g.to_end) end = g.from_end || expired;
      else end = T.nowIso(Date.parse(l.period_end) - (Date.parse(g.to_end) - Date.parse(g.from_end || g.to_end)));
      const next = Object.assign({}, l, { period_end: end });
      const ge = g.from_end ? graceEndOf(next) : end; // si nunca tuvo vigencia previa, no hay gracia
      this.db.run('UPDATE licenses SET period_end = ?, grace_end = ?, updated_at = ?, version = version + 1 WHERE id = ?', end, ge, T.nowIso(), l.id);
      this.db.run('INSERT INTO license_grants (id,license_id,kind,from_end,to_end,periods,reverses_id,invoice_id,payment_id,note,actor,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        C.newId('grt'), l.id, 'reverso', l.period_end, end, -g.periods, g.id, g.invoice_id, g.payment_id, reason, actor.label, T.nowIso());
      this.audit.log({ actor, action: 'licencia.vigencia_revertida', entity: ['license', l.id], ip, data: { grant: g.id, from: l.period_end, to: end, reason } });
      return this.sync(l.id, actor, 'Reverso: ' + reason, ip, true);
    });
  }

  /* ------------------------------------------------------------ acciones manuales */
  suspend(id, reason, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (l.status === 'cancelada') throw new HttpError(409, 'CANCELADA', 'La licencia está cancelada.');
      this.db.run("UPDATE licenses SET suspension_kind = 'manual', suspension_reason = ?, updated_at = ?, version = version + 1 WHERE id = ?", reason, T.nowIso(), id);
      this.audit.log({ actor, action: 'licencia.suspendida_manual', entity: ['license', id], ip, data: { reason } });
      return this.sync(id, actor, 'Suspensión manual: ' + reason, ip, true);
    });
  }

  resume(id, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (l.suspension_kind !== 'manual') throw new HttpError(409, 'ESTADO', 'La licencia no tiene una suspensión manual.');
      this.db.run('UPDATE licenses SET suspension_kind = NULL, suspension_reason = NULL, updated_at = ?, version = version + 1 WHERE id = ?', T.nowIso(), id);
      this.audit.log({ actor, action: 'licencia.suspension_levantada', entity: ['license', id], ip });
      return this.sync(id, actor, 'Suspensión manual levantada', ip, true);
    });
  }

  cancel(id, reason, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (l.status === 'cancelada') return l;
      this.db.run("UPDATE licenses SET status = 'cancelada', cancelled_at = ?, cancel_reason = ?, status_changed_at = ?, updated_at = ?, version = version + 1 WHERE id = ?", T.nowIso(), reason, T.nowIso(), T.nowIso(), id);
      this.db.run('INSERT INTO license_events (license_id,from_status,to_status,reason,actor,created_at) VALUES (?,?,?,?,?,?)', id, l.status, 'cancelada', reason, actor.label, T.nowIso());
      // Cobros abiertos sin pagos se anulan para que no sigan llegando recordatorios.
      for (const inv of this.db.all("SELECT id FROM invoices WHERE license_id = ? AND status = 'pendiente' AND paid_cents = 0", id)) this.billing.voidInvoice(inv.id, 'Licencia cancelada', actor, ip);
      this.audit.log({ actor, action: 'licencia.cancelada', entity: ['license', id], ip, data: { reason } });
      this.outbox.licenseChanged(this.get(id), 'cancelada');
      return this.get(id);
    });
  }

  reopen(id, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (l.status !== 'cancelada') throw new HttpError(409, 'ESTADO', 'Solo se reabre una licencia cancelada.');
      const eff = effective(Object.assign({}, l, { status: 'x' }));
      this.db.run('UPDATE licenses SET status = ?, suspension_kind = ?, cancelled_at = NULL, cancel_reason = NULL, status_changed_at = ?, updated_at = ?, version = version + 1 WHERE id = ?', eff.status, eff.kind || null, T.nowIso(), T.nowIso(), id);
      this.db.run('INSERT INTO license_events (license_id,from_status,to_status,reason,actor,created_at) VALUES (?,?,?,?,?,?)', id, 'cancelada', eff.status, 'Licencia reabierta', actor.label, T.nowIso());
      this.audit.log({ actor, action: 'licencia.reabierta', entity: ['license', id], ip });
      return this.sync(id, actor, 'Licencia reabierta', ip, true);
    });
  }

  /** Edita datos operativos. version: control de concurrencia (dos personas editando a la vez). */
  update(id, patch, version, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      if (version != null && l.version !== version) throw new HttpError(409, 'VERSION', 'Otra persona modificó esta licencia. Recarga para ver los cambios.');
      const fields = ['label', 'tenant_ref', 'instance_id', 'auto_cut', 'auto_invoice', 'grace_days', 'timezone', 'price_cents', 'max_activations', 'tax_mode', 'billing_provider'];
      const next = Object.assign({}, l); const changed = [];
      for (const f of fields) if (patch[f] !== undefined && patch[f] !== null && patch[f] !== l[f]) { next[f] = patch[f]; changed.push(f); }
      if (patch.clear_instance && l.instance_id) { next.instance_id = null; next.tenant_ref = null; changed.push('instance_id'); }
      if (patch.features) { next.features = JSON.stringify(patch.features); if (next.features !== l.features) changed.push('features'); }
      if (patch.plan_id && patch.plan_id !== l.plan_id) {
        const plan = this.db.get('SELECT * FROM plans WHERE id = ? AND product_id = ? AND active = 1', patch.plan_id, l.product_id);
        if (!plan) throw new HttpError(400, 'PLAN', 'Plan no válido para este producto.');
        Object.assign(next, { plan_id: plan.id, interval_unit: plan.interval_unit, interval_count: plan.interval_count, currency: plan.currency });
        if (patch.tax_mode == null) next.tax_mode = plan.tax_mode;
        if (patch.price_cents == null) next.price_cents = plan.price_cents;
        if (!patch.features) next.features = plan.features;
        changed.push('plan');
      }
      if (next.instance_id) {
        const inst = this.db.get('SELECT * FROM instances WHERE id = ?', next.instance_id);
        if (!inst || inst.product_id !== l.product_id) throw new HttpError(400, 'INSTANCIA', 'La instancia no corresponde al producto.');
        if (!next.tenant_ref) throw new HttpError(400, 'TENANT', 'Falta el identificador del negocio en la instancia.');
      }
      if (!T.isValidTz(next.timezone)) throw new HttpError(400, 'ZONA', 'Zona horaria no válida.');
      if (!changed.length) return l;
      next.grace_end = graceEndOf(next);
      this.db.run(`UPDATE licenses SET label=@label, tenant_ref=@tenant_ref, instance_id=@instance_id, auto_cut=@auto_cut, auto_invoice=@auto_invoice, grace_days=@grace_days,
        timezone=@timezone, price_cents=@price_cents, max_activations=@max_activations, features=@features, plan_id=@plan_id, interval_unit=@interval_unit,
        interval_count=@interval_count, currency=@currency, tax_mode=@tax_mode, billing_provider=@billing_provider,
        external_subscription_id = CASE WHEN @billing_provider = billing_provider THEN external_subscription_id END,
        external_customer_id = CASE WHEN @billing_provider = billing_provider THEN external_customer_id END,
        grace_end=@grace_end, updated_at=@now, version=version+1 WHERE id=@id`,
      { label: next.label, tenant_ref: next.tenant_ref || null, instance_id: next.instance_id || null, auto_cut: next.auto_cut ? 1 : 0, auto_invoice: next.auto_invoice ? 1 : 0, grace_days: next.grace_days, timezone: next.timezone, price_cents: next.price_cents, max_activations: next.max_activations, features: next.features, plan_id: next.plan_id, interval_unit: next.interval_unit, interval_count: next.interval_count, currency: next.currency, tax_mode: next.tax_mode, billing_provider: next.billing_provider, grace_end: next.grace_end, now: T.nowIso(), id });
      this.audit.log({ actor, action: 'licencia.editada', entity: ['license', id], ip, data: { campos: changed } });
      // Si cambió de instancia, la anterior debe enterarse de que ya no tiene este negocio.
      if (l.instance_id && (l.instance_id !== next.instance_id || l.tenant_ref !== next.tenant_ref)) {
        this.outbox.licenseChanged(l, 'retirada de esta instancia', { instance_id: l.instance_id, tenant_ref: l.tenant_ref, status: 'cancelada' });
      }
      return this.sync(id, actor, 'Licencia editada', ip, true);
    });
  }

  rotateKey(id, actor, ip) {
    return this.db.tx(() => {
      const l = this.must(id);
      const p = this.db.get('SELECT kind FROM products WHERE id = ?', l.product_id);
      if (p.kind !== 'instalable') throw new HttpError(400, 'NO_APLICA', 'Solo los productos instalables usan clave.');
      const key = 'SLX-' + C.randomCode(5) + '-' + C.randomCode(5) + '-' + C.randomCode(5) + '-' + C.randomCode(5);
      this.db.run('UPDATE licenses SET key_hash = ?, key_prefix = ?, updated_at = ? WHERE id = ?', C.sha256(key), key.slice(0, 10), T.nowIso(), id);
      this.db.run('UPDATE activations SET revoked_at = ? WHERE license_id = ? AND revoked_at IS NULL', T.nowIso(), id);
      this.audit.log({ actor, action: 'licencia.clave_regenerada', entity: ['license', id], ip });
      return key;
    });
  }

  /* ------------------------------------------------------------ sincronización */
  /**
   * Compara el estado guardado con el real; si cambió, lo registra, avisa al cliente y al producto.
   * force: emite el evento al producto aunque el estado no cambie (por ejemplo, nueva fecha de vigencia).
   */
  sync(id, actor = { type: 'sistema', label: 'Tareas automáticas' }, reason = null, ip = null, force = false) {
    return this.db.tx(() => {
      const l = this.must(id);
      const eff = effective(l);
      const changed = eff.status !== l.status || (eff.kind || null) !== (l.suspension_kind || null);
      if (changed) {
        this.db.run(`UPDATE licenses SET status = ?, suspension_kind = ?, suspension_reason = CASE WHEN ? = 'auto' THEN 'Falta de pago' ELSE suspension_reason END,
          status_changed_at = ?, updated_at = ? WHERE id = ?`, eff.status, eff.kind || null, eff.kind || '', T.nowIso(), T.nowIso(), id);
        this.db.run('INSERT INTO license_events (license_id,from_status,to_status,reason,actor,created_at) VALUES (?,?,?,?,?,?)',
          id, l.status, eff.status, reason || this.reasonFor(l.status, eff.status), actor.label || 'Sistema', T.nowIso());
        if (actor.type === 'sistema') this.audit.log({ actor, action: 'licencia.estado', entity: ['license', id], ip, data: { de: l.status, a: eff.status } });
        this.notifyTransition(this.get(id), l.status, eff.status);
      }
      if (changed || force) this.outbox.licenseChanged(this.get(id), reason || eff.status);
      return this.get(id);
    });
  }

  reasonFor(from, to) {
    if (to === 'gracia') return 'Venció el periodo pagado: inicia la gracia';
    if (to === 'suspendida') return 'Terminó la gracia sin pago: corte automático';
    if (from === 'suspendida' && (to === 'activa' || to === 'prueba')) return 'Reactivación automática';
    if (from === 'prueba' && to === 'activa') return 'Pasó de prueba a pagada';
    return null;
  }

  notifyTransition(l, from, to) {
    const client = this.db.get('SELECT * FROM clients WHERE id = ?', l.client_id);
    if (!client || client.anonymized_at) return;
    const product = this.db.get('SELECT name FROM products WHERE id = ?', l.product_id);
    const servicio = `${product.name} (${l.label})`;
    const inv = this.billing ? this.billing.openInvoiceForLicense(l, { create: !!l.auto_invoice && (to === 'gracia' || to === 'suspendida') }) : null;
    const enlace = inv ? this.billing.payUrl(inv) : '';
    const monto = inv ? require('./notify').money(inv.amount_cents - inv.paid_cents - inv.credit_applied_cents) : require('./notify').money(l.price_cents);
    const f = (iso) => require('./notify').fecha(iso, l.timezone);
    const key = `${l.id}:${l.period_end}`;
    if (to === 'gracia') this.notifier.queue({ template: 'gracia', client, license: l, vars: { servicio, fecha_corte: f(l.grace_end), monto, enlace }, dedupe: 'gracia:' + key });
    else if (to === 'suspendida' && l.suspension_kind === 'auto') this.notifier.queue({ template: 'suspension', client, license: l, vars: { servicio, monto, enlace }, dedupe: 'suspension:' + key });
    else if (from === 'suspendida' && ALLOWED.has(to)) this.notifier.queue({ template: 'reactivacion', client, license: l, vars: { servicio, fecha: f(l.period_end) }, dedupe: 'reactivacion:' + key });
  }

  /** Revisa todas las licencias que deberían cambiar de estado por fecha. Lo llama el programador cada minuto. */
  sweep(now = Date.now()) {
    const iso = T.nowIso(now);
    const due = this.db.all(`SELECT id FROM licenses WHERE
      (status IN ('prueba','activa') AND period_end IS NOT NULL AND period_end < ?)
      OR (status = 'gracia' AND auto_cut = 1 AND grace_end < ?)
      OR (status = 'suspendida' AND suspension_kind = 'auto' AND period_end >= ?)`, iso, iso, iso);
    let n = 0;
    for (const r of due) { const before = this.get(r.id).status; if (this.sync(r.id).status !== before) n++; }
    return n;
  }

  /* ------------------------------------------------------------ token firmado */
  /** Token que recibe el producto. Vida corta; nunca dura más allá del corte programado. */
  token(l, { aud, fingerprint = null } = {}) {
    const eff = effective(l);
    const product = this.db.get('SELECT code, name FROM products WHERE id = ?', l.product_id);
    const plan = this.db.get('SELECT code, name FROM plans WHERE id = ?', l.plan_id);
    const now = Math.floor(Date.now() / 1000);
    let exp = now + this.cfg.tokenTtlHours * 3600;
    // Si la licencia se cortará antes de que venza el token, el token vence en el corte (tolerancia sin conexión acotada).
    let cutIso = null;
    if (eff.status === 'gracia') cutIso = eff.cutAt || null;
    else if (ALLOWED.has(eff.status) && l.period_end && l.auto_cut) cutIso = l.grace_end || graceEndOf(l);
    if (cutIso) { const cut = Math.ceil(Date.parse(cutIso) / 1000); if (cut > now) exp = Math.min(exp, cut); }
    if (exp - now < 300) exp = now + 300;
    const inv = ['gracia', 'suspendida'].includes(eff.status) && this.billing ? this.billing.openInvoiceForLicense(l, { create: false }) : null;
    const msg = {
      prueba: 'Periodo de prueba', activa: null,
      gracia: `Pago pendiente. El servicio se suspenderá el ${require('./notify').fecha(eff.cutAt, l.timezone)} si no se registra el pago.`,
      suspendida: eff.kind === 'manual' ? 'Servicio suspendido. Comunícate con Solvex.' : 'Servicio suspendido por falta de pago. Al pagar se reactiva automáticamente.',
      cancelada: 'Servicio dado de baja. Comunícate con Solvex para exportar tus datos.',
      pendiente: 'El servicio aún no está activado.',
    }[eff.status];
    const payload = {
      iss: 'solvex-hub', sub: l.id, aud: aud || 'onprem', jti: C.newId('tok'), iat: now, nbf: now - 60, exp,
      lic: l.code, tenant: l.tenant_ref, product: product.code, plan: plan.code,
      status: eff.status, mode: MODE[eff.status], suspension: eff.kind || null,
      auto_cut: !!l.auto_cut, period_end: l.period_end, grace_end: l.period_end ? (l.grace_end || graceEndOf(l)) : null, cut_at: eff.cutAt || null,
      features: JSON.parse(l.features || '{}'), message: msg || null,
      pay_url: inv ? this.billing.payUrl(inv) : null,
      fp: fingerprint || undefined,
    };
    return jws.sign(this.cfg.signing.key, this.cfg.signing.kid, payload);
  }

  publicKeys() {
    const keys = [{ kid: this.cfg.signing.kid, alg: 'EdDSA', crv: 'Ed25519', pem: this.cfg.signing.publicPem, raw_b64: jws.rawPublicKeyB64(this.cfg.signing.publicPem), active: true }];
    for (const pem of this.cfg.signing.extraPublic) keys.push({ kid: jws.kidOf(pem), alg: 'EdDSA', crv: 'Ed25519', pem, raw_b64: jws.rawPublicKeyB64(pem), active: false });
    return keys;
  }
}

module.exports = { Licenses, effective, graceEndOf, MODE, ALLOWED };
