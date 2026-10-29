'use strict';
/**
 * Motor de impuestos. Se ejecuta ANTES de cobrar: cada cobro guarda base, impuesto, total, tasa,
 * tratamiento y el motivo, y ese desglose queda congelado en cuanto entra dinero.
 *
 * Reglas (Perú, persona natural o empresa domiciliada que vende software y suscripciones):
 *  1. Cliente con residencia fiscal en el Perú  → IGV (18 % hoy, tomado de la tabla tax_rules con su vigencia).
 *     Con RUC: factura. Con DNI/CE/pasaporte: boleta.
 *  2. Cliente del extranjero (no domiciliado):
 *     a. Si Solvex está inscrito para cobrar el impuesto de ese país (hay una regla para ese país) → ese impuesto.
 *     b. Si Solvex está inscrito en el Registro de Exportadores de Servicios → exportación de servicios, 0 % de IGV
 *        (Ley del IGV, art. 33). Factura de exportación.
 *     c. Si no está inscrito → NO califica como exportación: se cobra IGV (operación "no domiciliado").
 *        Así nunca se deja de cobrar un impuesto que SUNAT podría exigir después.
 *  3. Régimen Nuevo RUS: no se cobra IGV y solo se emiten boletas.
 *  4. Merchant of Record (Paddle, Lemon Squeezy...): el impuesto lo calcula y declara el MoR; aquí solo se registra.
 *
 * Montos en céntimos enteros, tasas en puntos básicos (1800 = 18 %), redondeo "mitad hacia arriba" al céntimo.
 * Modo de precio:
 *  - incluido: el precio ya trae el IGV del Perú (lo que paga un cliente peruano). Para un cliente exportado se
 *    cobra solo la base (precio ÷ 1.18): el mismo valor de venta, sin el impuesto peruano.
 *  - mas_impuesto: el precio es la base; se suma el impuesto que corresponda.
 */
const T = require('../lib/time');
const { HttpError } = require('../http/app');

const BP = 10000;
/** n / d redondeado al entero más cercano (mitad hacia arriba). Solo enteros no negativos. */
const roundDiv = (n, d) => Math.floor((2 * n + d) / (2 * d));
const pct = (bp) => (bp / 100).toLocaleString('es-PE', { maximumFractionDigits: 2 }) + ' %';

/** Divide un precio en base + impuesto. refRate: tasa que el precio "incluido" ya trae (IGV del Perú). */
function split(price, mode, rate, refRate) {
  if (!Number.isInteger(price) || price < 0) throw new Error('precio inválido');
  if (mode === 'incluido') {
    const base = refRate > 0 ? roundDiv(price * BP, BP + refRate) : price;
    if (rate === refRate) return { subtotal: base, tax: price - base, total: price };
    const tax = roundDiv(base * rate, BP);
    return { subtotal: base, tax, total: base + tax };
  }
  const tax = roundDiv(price * rate, BP);
  return { subtotal: price, tax, total: price + tax };
}

/**
 * Parte de un pago (por ejemplo, un abono parcial) que es base e impuesto, en la misma proporción que el cobro.
 * Para un pago completo devuelve exactamente la base y el impuesto del cobro.
 */
function portion(amount, inv) {
  if (!(inv.amount_cents > 0) || inv.tax_cents === 0) return { subtotal: amount, tax: 0, total: amount };
  if (amount === inv.amount_cents) return { subtotal: inv.subtotal_cents, tax: inv.tax_cents, total: amount };
  const subtotal = roundDiv(amount * inv.subtotal_cents, inv.amount_cents);
  return { subtotal, tax: amount - subtotal, total: amount };
}

/**
 * Decide el tratamiento sin tocar la base (función pura: fácil de probar).
 * ctx: { regime, exportRegistered, peRule, foreignRule }
 */
function decide(client, ctx) {
  const country = (client.country || 'PE').toUpperCase();
  const domestic = country === 'PE';
  const docFor = () => (client.doc_type === 'RUC' ? 'factura' : 'boleta');
  if (!ctx.peRule) throw new HttpError(500, 'SIN_IGV', 'No hay una regla de IGV vigente para el Perú (Configuración → Impuestos).');
  const igv = ctx.peRule.rate_bp;
  if (ctx.regime === 'nrus') {
    return { treatment: 'no_sujeto', operation: 'nrus', rate: 0, code: 'PE-NRUS', label: 'Sin IGV (Nuevo RUS)', country, fiscal_doc: 'boleta',
      note: 'Solvex está en el Nuevo RUS: no cobra IGV y solo emite boletas.' };
  }
  if (domestic) {
    return { treatment: 'gravado', operation: 'venta_interna', rate: igv, code: ctx.peRule.code, label: `${ctx.peRule.label} ${pct(igv)}`, country, fiscal_doc: docFor(),
      note: 'Cliente domiciliado en el Perú: operación gravada con IGV.' };
  }
  if (ctx.foreignRule) {
    const r = ctx.foreignRule;
    return { treatment: 'impuesto_extranjero', operation: 'extranjero', rate: r.rate_bp, code: r.code, label: `${r.label} ${pct(r.rate_bp)}`, country, fiscal_doc: 'factura',
      note: `Solvex cobra ${r.label} de ${country} (regla ${r.code}). En el Perú es exportación (0 % de IGV) sobre la base.` };
  }
  if (ctx.exportRegistered) {
    return { treatment: 'exportacion', operation: 'exportacion', rate: 0, code: 'EXPORTACION', label: 'Exportación de servicios (0 % IGV)', country, fiscal_doc: 'factura',
      note: 'Cliente no domiciliado y Solvex inscrito en el Registro de Exportadores de Servicios (Ley del IGV, art. 33).' };
  }
  return { treatment: 'gravado', operation: 'no_domiciliado', rate: igv, code: ctx.peRule.code, label: `${ctx.peRule.label} ${pct(igv)}`, country, fiscal_doc: 'factura',
    note: 'Cliente del extranjero, pero Solvex aún no está inscrito en el Registro de Exportadores de Servicios: no califica como exportación y se cobra IGV.' };
}

class Tax {
  constructor({ db, settings }) { Object.assign(this, { db, settings }); }

  /** Regla vigente para un país (y región) en una fecha. Una regla de región gana sobre la del país. */
  rule(country, { region = null, date = T.localDate(Date.now()), kind = 'todos' } = {}) {
    const rows = this.db.all(`SELECT * FROM tax_rules WHERE country = ? AND active = 1 AND valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)
      AND (region IS NULL OR region = ?) AND customer_kind IN ('todos', ?) ORDER BY (region IS NOT NULL) DESC, (customer_kind <> 'todos') DESC, valid_from DESC`, country, date, date, region || '', kind);
    return rows[0] || null;
  }

  /**
   * Calcula el impuesto de un precio para un cliente. Es lo que se llama antes de emitir (o refrescar) un cobro.
   * client: fila de clients (country, region, doc_type, kind). price_cents: precio ingresado. tax_mode: incluido | mas_impuesto.
   */
  quote({ client, price_cents, tax_mode = 'incluido', date = T.localDate(Date.now()) }) {
    const s = this.settings.get('tax') || {};
    const country = (client.country || 'PE').toUpperCase();
    const kind = client.kind === 'persona' ? 'persona' : 'empresa';
    const peRule = this.rule('PE', { date, kind });
    const foreignRule = country !== 'PE' ? this.rule(country, { region: client.region, date, kind }) : null;
    const d = decide(client, { regime: s.regime, exportRegistered: !!s.export_registered, peRule, foreignRule });
    // El precio "incluido" siempre trae el IGV del Perú (salvo en el Nuevo RUS, donde no hay IGV que separar).
    const refRate = s.regime === 'nrus' ? 0 : peRule.rate_bp;
    const amounts = split(price_cents, tax_mode, d.rate, refRate);
    return Object.assign(d, amounts, { tax_mode, list_price_cents: price_cents, date });
  }

  /** Texto corto para el panel: "IGV 18 % · factura". */
  describe(client) {
    try { const q = this.quote({ client, price_cents: 10000, tax_mode: 'mas_impuesto' }); return { label: q.label, fiscal_doc: q.fiscal_doc, treatment: q.treatment, note: q.note }; }
    catch (e) { return { label: e.message, fiscal_doc: 'ninguno', treatment: 'error', note: '' }; }
  }
}

module.exports = { Tax, split, portion, decide, roundDiv, pct, BP };
