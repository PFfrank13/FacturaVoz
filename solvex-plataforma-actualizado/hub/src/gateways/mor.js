'use strict';
/**
 * Merchant of Record (MoR): Paddle y Lemon Squeezy. El MoR vende en su nombre al cliente final, calcula y
 * declara el IVA/VAT/sales tax de cada país y le paga a Solvex el neto. El Hub solo necesita saber
 * "se pagó / se reembolsó / se canceló" para mover la licencia.
 *
 * Cada adaptador hace dos cosas:
 *   verify(rawBody, headers, secret, now) -> true/false   (firma HMAC sobre el cuerpo CRUDO, comparación en tiempo constante)
 *   normalize(json) -> evento interno:
 *     { key, type, kind, occurredAt, paymentId, subscriptionId, customerId, licenseRef, currency,
 *       subtotalCents, taxCents, totalCents, refundCents, email, country, description }
 *     kind: payment | refund | chargeback | payment_failed | subscription_linked | subscription_canceled | ignored
 *
 * Para que un pago se asocie a una licencia, el checkout del MoR debe llevar el dato personalizado
 * solvex_license = "LIC-00012" (Paddle: customData; Lemon Squeezy: checkout[custom][solvex_license]).
 */
const crypto = require('node:crypto');

const safeEq = (a, b) => { const x = Buffer.from(String(a)), y = Buffer.from(String(b)); return x.length === y.length && crypto.timingSafeEqual(x, y); };
const hmacHex = (secret, data) => crypto.createHmac('sha256', secret).update(data).digest('hex');
const int = (v) => { const n = Number(v); return Number.isFinite(n) ? Math.round(n) : 0; };
const str = (v) => (v == null || v === '' ? null : String(v).slice(0, 120));
const cur = (v) => (/^[A-Za-z]{3}$/.test(String(v || '')) ? String(v).toUpperCase() : 'USD');
const header = (h, k) => { const v = h[k] ?? h[k.toLowerCase()]; return Array.isArray(v) ? v[0] : v; };

/* ------------------------------------------------------------ Paddle Billing */
const paddle = {
  name: 'paddle', label: 'Paddle',
  /** Paddle-Signature: ts=1671552777;h1=<hex>  — firma = HMAC-SHA256(secreto, ts + ":" + cuerpo). Rechaza avisos con más de 5 minutos. */
  verify(raw, headers, secret, now = Date.now()) {
    const h = String(header(headers, 'paddle-signature') || '');
    const parts = h.split(';').map((p) => p.trim().split('='));
    const ts = (parts.find((p) => p[0] === 'ts') || [])[1];
    const sigs = parts.filter((p) => p[0] === 'h1').map((p) => p[1]);
    if (!/^\d{9,12}$/.test(String(ts)) || !sigs.length) return false;
    if (Math.abs(now / 1000 - Number(ts)) > 300) return false;
    const exp = hmacHex(secret, ts + ':' + raw.toString('utf8'));
    return sigs.some((s) => safeEq(s, exp));
  },
  normalize(j) {
    const d = j.data || {}, cd = d.custom_data || {}, type = String(j.event_type || '');
    const base = { key: str(j.event_id), type, occurredAt: str(j.occurred_at), licenseRef: str(cd.solvex_license), customerId: str(d.customer_id) };
    if (type === 'transaction.completed' || type === 'transaction.paid') {
      if (type === 'transaction.paid') return Object.assign(base, { kind: 'ignored' }); // se espera a "completed"
      const t = (d.details && d.details.totals) || {};
      const total = int(t.total), tax = int(t.tax);
      return Object.assign(base, { kind: 'payment', paymentId: str(d.id), subscriptionId: str(d.subscription_id), currency: cur(d.currency_code),
        totalCents: total, taxCents: tax, subtotalCents: total - tax, description: d.origin === 'subscription_recurring' ? 'renovación' : 'suscripción' });
    }
    if (type === 'transaction.payment_failed') return Object.assign(base, { kind: 'payment_failed', paymentId: str(d.id), subscriptionId: str(d.subscription_id) });
    if (type === 'adjustment.created' || type === 'adjustment.updated') {
      if (d.status !== 'approved' || !['refund', 'chargeback'].includes(d.action)) return Object.assign(base, { kind: 'ignored' });
      return Object.assign(base, { kind: d.action === 'chargeback' ? 'chargeback' : 'refund', paymentId: str(d.transaction_id), subscriptionId: str(d.subscription_id),
        refundCents: int(d.totals && d.totals.total), currency: cur(d.currency_code), key: base.key });
    }
    if (['subscription.created', 'subscription.activated', 'subscription.updated', 'subscription.resumed'].includes(type)) return Object.assign(base, { kind: 'subscription_linked', subscriptionId: str(d.id) });
    if (type === 'subscription.canceled') return Object.assign(base, { kind: 'subscription_canceled', subscriptionId: str(d.id) });
    if (type === 'subscription.past_due') return Object.assign(base, { kind: 'payment_failed', subscriptionId: str(d.id) });
    return Object.assign(base, { kind: 'ignored' });
  },
};

/* ------------------------------------------------------------ Lemon Squeezy */
const lemonsqueezy = {
  name: 'lemonsqueezy', label: 'Lemon Squeezy',
  /** X-Signature: hex(HMAC-SHA256(secreto, cuerpo)). Lemon Squeezy no firma una fecha: la idempotencia evita repeticiones. */
  verify(raw, headers, secret) {
    const sig = String(header(headers, 'x-signature') || '');
    return /^[a-f0-9]{64}$/i.test(sig) && safeEq(sig.toLowerCase(), hmacHex(secret, raw));
  },
  normalize(j) {
    const m = j.meta || {}, d = j.data || {}, a = d.attributes || {}, cd = m.custom_data || {}, type = String(m.event_name || '');
    const base = { key: `${type}:${d.type || ''}:${d.id || ''}:${a.updated_at || a.created_at || ''}`, type, occurredAt: str(a.created_at), licenseRef: str(cd.solvex_license),
      customerId: str(a.customer_id), email: str(a.user_email) };
    const money = (pid) => { const total = int(a.total), tax = int(a.tax); return { paymentId: pid, currency: cur(a.currency), totalCents: total, taxCents: tax, subtotalCents: total - tax }; };
    if (type === 'subscription_payment_success') {
      if (a.status && a.status !== 'paid') return Object.assign(base, { kind: 'ignored' });
      return Object.assign(base, money('si_' + d.id), { kind: 'payment', subscriptionId: str(a.subscription_id), description: a.billing_reason === 'renewal' ? 'renovación' : 'suscripción' });
    }
    // Una compra única (no suscripción). En suscripciones, Lemon Squeezy manda order_created Y subscription_payment_success
    // por el primer pago: para no contarlo dos veces, order_created solo cuenta si el checkout lo marcó como pago único.
    if (type === 'order_created') {
      if (cd.solvex_kind !== 'unico' || a.status !== 'paid') return Object.assign(base, { kind: 'ignored' });
      return Object.assign(base, money('ord_' + d.id), { kind: 'payment', description: 'pago único' });
    }
    if (type === 'subscription_payment_refunded') return Object.assign(base, { kind: 'refund', paymentId: 'si_' + d.id, refundCents: int(a.refunded_amount) || null, currency: cur(a.currency) });
    if (type === 'order_refunded') return Object.assign(base, { kind: cd.solvex_kind === 'unico' ? 'refund' : 'ignored', paymentId: 'ord_' + d.id, refundCents: int(a.refunded_amount) || null, currency: cur(a.currency) });
    if (type === 'subscription_payment_failed') return Object.assign(base, { kind: 'payment_failed', subscriptionId: str(a.subscription_id) });
    if (['subscription_created', 'subscription_updated', 'subscription_resumed', 'subscription_unpaused'].includes(type)) return Object.assign(base, { kind: 'subscription_linked', subscriptionId: str(d.id) });
    if (['subscription_cancelled', 'subscription_expired'].includes(type)) return Object.assign(base, { kind: 'subscription_canceled', subscriptionId: str(d.id) });
    return Object.assign(base, { kind: 'ignored' });
  },
};

const ADAPTERS = { paddle, lemonsqueezy };
module.exports = { ADAPTERS, paddle, lemonsqueezy, hmacHex };
