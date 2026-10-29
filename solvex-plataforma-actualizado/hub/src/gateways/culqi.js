'use strict';
/**
 * Pasarela Culqi (Perú). Interfaz común para poder cambiar de proveedor sin tocar el resto:
 *   createCharge({ amountCents, email, token, description, metadata }) -> cargo normalizado
 *   getCharge(id)                                                       -> cargo normalizado
 * Cargo normalizado: { id, paid, refunded, amountCents, email, cardLabel, metadata }
 *
 * Verifica con llaves de PRUEBA antes de producción. Si Culqi cambia nombres de campos,
 * solo se ajusta _norm().
 */
class CulqiGateway {
  constructor({ secretKey, apiBase = 'https://api.culqi.com/v2', fetchImpl = globalThis.fetch }) {
    if (!secretKey) throw new Error('Falta CULQI_SECRET_KEY');
    this.secretKey = secretKey; this.base = apiBase.replace(/\/+$/, ''); this.fetch = fetchImpl; this.name = 'culqi';
  }

  async _req(method, path, body) {
    const res = await this.fetch(this.base + path, {
      method, signal: AbortSignal.timeout(25_000),
      headers: { Authorization: 'Bearer ' + this.secretKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    let json = null; try { json = await res.json(); } catch (_) { /* sin cuerpo */ }
    return { status: res.status, json };
  }

  static _norm(c) {
    const src = c.source || {};
    const brand = (src.iin && src.iin.card_brand) || '';
    const last4 = String(src.card_number || '').replace(/\D/g, '').slice(-4);
    return {
      id: c.id,
      paid: !!(c.outcome && c.outcome.type === 'venta_exitosa'),
      refunded: Number(c.amount_refunded || 0) > 0,
      refundedCents: Number(c.amount_refunded || 0),
      amountCents: Number(c.amount || 0),
      currency: c.currency_code || 'PEN',
      email: c.email || '',
      cardLabel: brand ? brand + (last4 ? ' ····' + last4 : '') : (src.object === 'yape' ? 'Yape' : ''),
      metadata: c.metadata || {},
    };
  }

  async createCharge({ amountCents, currency = 'PEN', email, token, description, metadata }) {
    if (!['PEN', 'USD'].includes(currency)) throw Object.assign(new Error('Culqi cobra en soles o dólares'), { status: 400, userMessage: 'Moneda no disponible para pago con tarjeta.' });
    const { status, json } = await this._req('POST', '/charges', { amount: amountCents, currency_code: currency, email, source_id: token, description, metadata });
    if (status >= 400 || !json || !json.id) {
      const e = new Error((json && (json.user_message || json.merchant_message)) || 'La pasarela rechazó el cobro');
      e.status = status; e.userMessage = json && json.user_message; throw e;
    }
    return CulqiGateway._norm(json);
  }

  /** Consulta directa: es la fuente de verdad (el aviso del webhook no se toma como cierto). */
  async getCharge(id) {
    if (!/^[A-Za-z0-9_]{6,80}$/.test(String(id))) throw new Error('id de cargo inválido');
    const { status, json } = await this._req('GET', '/charges/' + encodeURIComponent(id));
    if (status !== 200 || !json || !json.id) { const e = new Error('No se pudo consultar el cargo'); e.status = status; throw e; }
    return CulqiGateway._norm(json);
  }
}

/**
 * Pasarela simulada para desarrollo y pruebas automáticas (nunca en producción).
 * token "tkn_ok..." aprueba, "tkn_fail..." rechaza.
 */
class FakeGateway {
  constructor() { this.charges = new Map(); this.name = 'simulada'; this.seq = 0; }
  async createCharge({ amountCents, currency = 'PEN', email, token, metadata }) {
    if (!String(token).startsWith('tkn_ok')) { const e = new Error('Tarjeta rechazada (simulada)'); e.status = 402; e.userMessage = 'Tarjeta rechazada.'; throw e; }
    const id = 'chr_test_' + (++this.seq).toString().padStart(6, '0') + Math.random().toString(36).slice(2, 8);
    const c = { id, paid: true, refunded: false, refundedCents: 0, amountCents, currency, email, cardLabel: 'Visa ····1111', metadata: metadata || {} };
    this.charges.set(id, c); return { ...c };
  }
  async getCharge(id) { const c = this.charges.get(id); if (!c) { const e = new Error('no existe'); e.status = 404; throw e; } return { ...c }; }
  refund(id) { const c = this.charges.get(id); if (c) { c.refunded = true; c.refundedCents = c.amountCents; } }
}

module.exports = { CulqiGateway, FakeGateway };
