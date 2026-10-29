'use strict';
/**
 * Proveedores de comprobantes electrónicos (OSE/PSE autorizados por SUNAT).
 *
 * Interfaz común (para cambiar de proveedor sin tocar el resto):
 *   send(doc)    -> resultado normalizado, o lanza un error con { retryable }
 *   consult(doc) -> resultado normalizado, o null si el proveedor no lo tiene
 * doc (independiente del proveedor): { kind, series, number, issue_date, operation, currency, subtotal_cents, tax_cents,
 *   total_cents, tax_rate_bp, igv_rate_bp, customer: { name, doc_type, doc_number, address, email }, description,
 *   related: { kind, series, number } | null, note_reason, send_to_client }
 * resultado: { state: 'aceptado' | 'enviado' | 'rechazado', code, description, hash, qr, link, pdf, xml, cdr }
 *
 * Nubefact: API JSON documentada en su "Manual de integración" (ruta + token por empresa). Antes de producción,
 * Nubefact pide emitir desde el sistema un set de prueba (factura, boleta, exportación, notas): hazlo con la
 * ruta y token de DEMO y revisa cada PDF. Si Nubefact cambia un campo, solo se ajusta toNubefact()/norm().
 */
const crypto = require('node:crypto');

const DOC_SUNAT = { RUC: '6', DNI: '1', CE: '4', PAS: '7', EXT: '0' }; // catálogo 06 (0 = no domiciliado sin RUC)
const KIND_NF = { factura: 1, boleta: 2, nota_credito: 3 };
const TRANSACTION_NF = { venta_interna: 1, exportacion: 2, no_domiciliado: 29 };
const CURRENCY_NF = { PEN: 1, USD: 2, EUR: 3 };
const NOTE_NF = { '01': 1, '06': 6 }; // catálogo 09: 01 anulación de la operación · 06 devolución total
const n2 = (cents) => Number((cents / 100).toFixed(2));
const ddmmyyyy = (iso) => { const [y, m, d] = iso.split('-'); return `${d}-${m}-${y}`; };

class ProviderError extends Error {
  constructor(message, { retryable = false, status = null, exists = false } = {}) { super(message); Object.assign(this, { retryable, status, exists }); }
}

class NubefactProvider {
  constructor({ url, token, fetchImpl = globalThis.fetch }) {
    if (!/^https:\/\//.test(String(url || ''))) throw new Error('NUBEFACT_URL debe ser la ruta https que te da Nubefact');
    if (!token) throw new Error('Falta NUBEFACT_TOKEN');
    Object.assign(this, { url, token, fetch: fetchImpl, name: 'nubefact' });
  }

  async _post(body) {
    let res;
    try {
      res = await this.fetch(this.url, { method: 'POST', signal: AbortSignal.timeout(30_000),
        headers: { Authorization: `Token token="${this.token}"`, 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify(body) });
    } catch (e) { throw new ProviderError('Sin conexión con Nubefact: ' + e.message, { retryable: true }); }
    let json = null; try { json = await res.json(); } catch (_) { /* sin JSON */ }
    if (res.status >= 500 || res.status === 429) throw new ProviderError(`Nubefact respondió ${res.status}`, { retryable: true, status: res.status });
    if (!json) throw new ProviderError(`Respuesta no válida de Nubefact (${res.status})`, { retryable: true, status: res.status });
    if (json.errors) {
      const msg = String(Array.isArray(json.errors) ? json.errors.join(' · ') : json.errors).slice(0, 500);
      throw new ProviderError(msg, { status: res.status, exists: /ya existe|ya fue|duplicad/i.test(msg) });
    }
    return json;
  }

  toNubefact(d) {
    const exp = d.operation === 'exportacion';
    const tipoIgv = exp ? 16 : 1; // 1 gravado - operación onerosa · 16 exportación
    const body = {
      operacion: 'generar_comprobante', tipo_de_comprobante: KIND_NF[d.kind], serie: d.series, numero: d.number,
      sunat_transaction: TRANSACTION_NF[d.operation],
      cliente_tipo_de_documento: DOC_SUNAT[d.customer.doc_type] || '0', cliente_numero_de_documento: String(d.customer.doc_number || '-').slice(0, 15),
      cliente_denominacion: String(d.customer.name).replace(/"/g, '').slice(0, 100), cliente_direccion: String(d.customer.address || '').replace(/"/g, '').slice(0, 100),
      cliente_email: d.customer.email || '', fecha_de_emision: ddmmyyyy(d.issue_date), moneda: CURRENCY_NF[d.currency], tipo_de_cambio: '',
      // Exportación: Nubefact la recibe con porcentaje 0 y el valor en total_inafecta (ver su ejemplo 6 en la cuenta DEMO).
      porcentaje_de_igv: exp ? 0 : n2(d.igv_rate_bp),
      total_gravada: exp ? '' : n2(d.subtotal_cents), total_inafecta: exp ? n2(d.subtotal_cents) : '', total_exonerada: '', total_igv: n2(d.tax_cents), total: n2(d.total_cents),
      detraccion: false, observaciones: '',
      documento_que_se_modifica_tipo: d.related ? KIND_NF[d.related.kind] : '', documento_que_se_modifica_serie: d.related ? d.related.series : '',
      documento_que_se_modifica_numero: d.related ? d.related.number : '', tipo_de_nota_de_credito: d.related ? NOTE_NF[d.note_reason] : '', tipo_de_nota_de_debito: '',
      enviar_automaticamente_a_la_sunat: true, enviar_automaticamente_al_cliente: !!(d.send_to_client && d.customer.email),
      codigo_unico: `${d.series}-${d.number}`, condiciones_de_pago: '', medio_de_pago: '', formato_de_pdf: '',
      items: [{
        unidad_de_medida: 'ZZ', codigo: 'SRV', descripcion: String(d.description).replace(/"/g, '').slice(0, 250), cantidad: 1,
        valor_unitario: n2(d.subtotal_cents), precio_unitario: n2(d.total_cents), descuento: '', subtotal: n2(d.subtotal_cents),
        tipo_de_igv: tipoIgv, igv: n2(d.tax_cents), total: n2(d.total_cents), anticipo_regularizacion: false, anticipo_documento_serie: '', anticipo_documento_numero: '',
      }],
    };
    return body;
  }

  static norm(j) {
    const code = j.sunat_responsecode != null ? String(j.sunat_responsecode) : '';
    // Códigos de SUNAT: 0 aceptado · 0100-1999 excepción (reintentar) · 2000-3999 rechazo · 4000+ aceptado con observaciones.
    const n = /^\d+$/.test(code) ? Number(code) : null;
    const state = j.aceptada_por_sunat === true ? 'aceptado' : (n != null && n >= 2000 && n < 4000 ? 'rechazado' : 'enviado');
    return { state, code, description: String(j.sunat_description || j.sunat_note || j.sunat_soap_error || '').slice(0, 500),
      hash: j.codigo_hash || null, qr: j.cadena_para_codigo_qr || null, link: j.enlace || null, pdf: j.enlace_del_pdf || null, xml: j.enlace_del_xml || null, cdr: j.enlace_del_cdr || null };
  }

  async send(d) { return NubefactProvider.norm(await this._post(this.toNubefact(d))); }

  async consult(d) {
    try { return NubefactProvider.norm(await this._post({ operacion: 'consultar_comprobante', tipo_de_comprobante: KIND_NF[d.kind], serie: d.series, numero: d.number })); }
    catch (e) { if (!e.retryable && /no existe|not found|no encontrado/i.test(e.message)) return null; throw e; }
  }
}

/** Proveedor simulado (desarrollo y pruebas). mode: ok | rechazo | caido | invalido. Nunca en producción. */
class SimulatedProvider {
  constructor() { this.name = 'simulado'; this.mode = 'ok'; this.store = new Map(); this.calls = []; }
  key(d) { return `${d.series}-${d.number}`; }
  async send(d) {
    this.calls.push(d);
    if (this.mode === 'caido') throw new ProviderError('Proveedor simulado sin conexión', { retryable: true });
    if (this.mode === 'invalido') throw new ProviderError('Dato inválido (simulado)');
    if (this.store.has(this.key(d))) throw new ProviderError('Este documento ya existe (simulado)', { exists: true });
    const r = this.mode === 'rechazo'
      ? { state: 'rechazado', code: '2800', description: 'Rechazo simulado', hash: null, qr: null, link: null, pdf: null, xml: null, cdr: null }
      : { state: 'aceptado', code: '0', description: `Comprobante ${this.key(d)} aceptado (simulado)`, hash: crypto.randomBytes(20).toString('base64'), qr: `RUC|${this.key(d)}|${n2(d.tax_cents)}|${n2(d.total_cents)}`, link: null, pdf: null, xml: null, cdr: null };
    this.store.set(this.key(d), r);
    return r;
  }
  async consult(d) { return this.store.get(this.key(d)) || null; }
}

function makeProvider(cfg, fetchImpl) {
  if (!cfg || cfg.provider === 'none') return null;
  if (cfg.provider === 'nubefact') return new NubefactProvider({ url: cfg.url, token: cfg.token, fetchImpl });
  if (cfg.provider === 'simulado') return new SimulatedProvider();
  throw new Error('EINVOICE_PROVIDER no reconocido: ' + cfg.provider);
}

module.exports = { NubefactProvider, SimulatedProvider, ProviderError, makeProvider, DOC_SUNAT };
