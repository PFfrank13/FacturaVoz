'use strict';
/**
 * Bandeja de webhooks de Merchant of Record. Orden de cada aviso:
 *   1. Firma: se verifica sobre el cuerpo crudo con el secreto del proveedor. Sin firma válida → 401 y auditoría.
 *   2. Idempotencia: cada aviso tiene una llave única (gateway_events). Un aviso repetido responde 200 sin hacer nada.
 *   3. Copia cifrada del aviso (para revisar o reprocesar), y procesamiento en una transacción.
 *   4. Respuesta: 200 si quedó resuelto (aplicado, repetido o ignorado); 503 si conviene que el MoR lo reintente
 *      (por ejemplo, un reembolso que llegó antes que su pago). En ese caso se borra la marca para aceptar el reintento.
 *
 * Seguridad adicional: un aviso solo mueve una licencia configurada para cobrarse con ESE proveedor; si ya está
 * vinculada a una suscripción, el aviso debe traer la misma. Así nadie puede "pagar" una licencia ajena desde otro checkout.
 */
const T = require('../lib/time');
const C = require('../lib/crypto');
const { ADAPTERS } = require('../gateways/mor');
const { money } = require('./notify');

class RetryLater extends Error {}

class Mor {
  constructor({ db, vault, audit, billing, licenses, bus, config, log = console }) { Object.assign(this, { db, vault, audit, billing, licenses, bus, cfg: config, log }); }

  enabled() { return Object.keys(this.cfg.mor || {}); }

  findLicense(provider, ev) {
    let lic = null;
    if (ev.licenseRef) lic = /^lic_[a-z0-9]{20}$/.test(ev.licenseRef) ? this.licenses.get(ev.licenseRef) : this.db.get('SELECT * FROM licenses WHERE code = ?', String(ev.licenseRef).toUpperCase());
    if (!lic && ev.subscriptionId) lic = this.db.get('SELECT * FROM licenses WHERE billing_provider = ? AND external_subscription_id = ?', provider, ev.subscriptionId);
    return lic || null;
  }

  /** ¿Puede este aviso mover esta licencia? Devuelve el motivo si no. */
  guard(provider, ev, lic) {
    if (!lic) return 'sin_licencia';
    if (lic.billing_provider !== provider) return 'licencia_no_configurada';
    if (ev.subscriptionId && lic.external_subscription_id && lic.external_subscription_id !== ev.subscriptionId) return 'otra_suscripcion';
    return null;
  }

  link(lic, ev) {
    if (!ev.subscriptionId && !ev.customerId) return;
    this.db.run('UPDATE licenses SET external_subscription_id = COALESCE(external_subscription_id, ?), external_customer_id = COALESCE(external_customer_id, ?), auto_invoice = 0, updated_at = ? WHERE id = ?',
      ev.subscriptionId || null, ev.customerId || null, T.nowIso(), lic.id);
  }

  process(provider, ev) {
    const A = ADAPTERS[provider];
    const actor = { type: 'pasarela', label: A.label };
    Object.assign(ev, { provider, providerLabel: A.label });
    if (ev.kind === 'ignored') return 'ignorado';
    if (ev.kind === 'refund' || ev.kind === 'chargeback') {
      const r = this.billing.applyMorRefund(ev);
      if (r.missing) throw new RetryLater('el pago aún no llegó');
      return r.partial ? 'reembolso_parcial' : r.duplicate ? 'ya_registrado' : 'reembolsado';
    }
    const lic = this.findLicense(provider, ev);
    const why = this.guard(provider, ev, lic);
    if (why) {
      const msg = { sin_licencia: 'no indica una licencia (falta solvex_license en el checkout)', licencia_no_configurada: `la licencia ${lic && lic.code} no está configurada para cobrarse con ${A.label}`, otra_suscripcion: `la licencia ${lic && lic.code} ya está vinculada a otra suscripción` }[why];
      this.audit.log({ actor, action: 'mor.aviso_rechazado', entity: lic ? ['license', lic.id] : null, data: { tipo: ev.type, motivo: why } });
      if (ev.kind === 'payment') this.bus.emit('admin', { type: 'warning', message: `${A.label} informó un pago de ${money(ev.totalCents, ev.currency)} pero ${msg}. Revísalo en su panel.` });
      return why;
    }
    if (ev.kind === 'payment') {
      this.link(lic, ev);
      const r = this.billing.applyMorPayment(ev, this.licenses.get(lic.id));
      if (!r.duplicate && lic.currency === ev.currency && ev.subtotalCents < lic.price_cents) {
        this.bus.emit('admin', { type: 'warning', message: `${lic.code}: ${A.label} cobró ${money(ev.subtotalCents, ev.currency)} (sin impuesto), menos que el precio de la licencia (${money(lic.price_cents, lic.currency)}). Revisa el producto en ${A.label}.` });
      }
      return r.duplicate ? 'ya_registrado' : 'aplicado';
    }
    if (ev.kind === 'subscription_linked') { this.link(lic, ev); this.audit.log({ actor, action: 'mor.suscripcion_vinculada', entity: ['license', lic.id], data: { suscripcion: ev.subscriptionId } }); return 'vinculado'; }
    if (ev.kind === 'payment_failed') {
      this.audit.log({ actor, action: 'mor.pago_fallido', entity: ['license', lic.id], data: { tipo: ev.type } });
      this.bus.emit('admin', { type: 'warning', message: `${A.label}: falló el cobro de ${lic.code}. ${A.label} reintenta; si no se paga, la licencia entra en gracia y se corta sola al vencer.` });
      return 'aviso';
    }
    if (ev.kind === 'subscription_canceled') {
      this.audit.log({ actor, action: 'mor.suscripcion_cancelada', entity: ['license', lic.id], data: { tipo: ev.type } });
      this.bus.emit('admin', { type: 'warning', message: `${lic.code}: la suscripción se canceló en ${A.label}. La licencia sigue hasta su vencimiento y luego se corta sola.` });
      return 'cancelada';
    }
    return 'ignorado';
  }

  /** Punto de entrada del webhook. Devuelve { status, outcome }. */
  handle(provider, raw, headers, now = Date.now()) {
    const A = ADAPTERS[provider], conf = (this.cfg.mor || {})[provider];
    if (!A || !conf) return { status: 404, outcome: 'no_configurado' };
    if (!A.verify(raw, headers, conf.secret, now)) {
      this.audit.log({ actor: { type: 'publico', label: A.label + ' (firma inválida)' }, action: 'webhook.firma_invalida', data: { provider } });
      return { status: 401, outcome: 'firma_invalida' };
    }
    let json; try { json = JSON.parse(raw.toString('utf8')); } catch (_) { return { status: 400, outcome: 'json_invalido' }; }
    const ev = A.normalize(json);
    if (!ev.key) return { status: 400, outcome: 'sin_id' };
    const id = (provider + ':' + ev.key).slice(0, 200);
    const ins = this.db.run('INSERT OR IGNORE INTO gateway_events (id,provider,type,charge_id,received_at,payload_enc,attempts) VALUES (?,?,?,?,?,?,1)',
      id, provider, String(ev.type).slice(0, 60), String(ev.paymentId || ev.subscriptionId || '').slice(0, 80), T.nowIso(now), this.vault.encrypt(raw.toString('utf8'), 'gateway_events.payload:' + id));
    if (ins.changes === 0) return { status: 200, outcome: 'duplicado' };
    try {
      const outcome = this.db.tx(() => this.process(provider, ev));
      this.db.run('UPDATE gateway_events SET outcome = ?, processed_at = ? WHERE id = ?', outcome, T.nowIso(), id);
      return { status: 200, outcome };
    } catch (e) {
      this.db.run('DELETE FROM gateway_events WHERE id = ?', id); // así el reintento del MoR se procesa
      if (e instanceof RetryLater) return { status: 503, outcome: 'reintentar' };
      this.log.error('webhook ' + provider, e.stack || e.message);
      this.audit.log({ actor: { type: 'pasarela', label: A.label }, action: 'mor.error', data: { tipo: ev.type, error: String(e.message).slice(0, 200) } });
      return { status: 500, outcome: 'error' };
    }
  }
}

module.exports = { Mor, RetryLater };
void C;
