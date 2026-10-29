'use strict';
/**
 * Cliente de licencias de Solvex para productos en Node.js (sin dependencias).
 *
 *  A) Producto en la nube (multi-negocio):  verifyToken() + verifyWebhook() + syncAll()
 *  B) Producto instalable en el equipo del cliente: Activation (activa con clave, guarda el token,
 *     lo renueva y decide sin conexión hasta que el token vence).
 *
 * Verdad incómoda: en un programa que corre en la computadora del cliente, alguien con control total
 * de esa computadora siempre puede intentar "parchar" el código. La firma impide FALSIFICAR una
 * licencia, no impide modificar el programa. Para lo crítico, deja la lógica de valor en el servidor.
 */
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');

const b64u = (s) => Buffer.from(String(s), 'base64url');

/** keys: arreglo de llaves públicas en base64 crudo (32 bytes) como las muestra el Hub. */
function verifyToken(token, keys, { audience = null, clockSkewSec = 120, now = Date.now() } = {}) {
  const [h, p, s] = String(token || '').split('.');
  if (!s) throw new Error('token mal formado');
  const header = JSON.parse(b64u(h)), payload = JSON.parse(b64u(p));
  if (header.alg !== 'EdDSA' || header.typ !== 'slx-license+jwt') throw new Error('algoritmo no permitido');
  const ok = keys.some((k) => {
    const der = Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(k, 'base64')]); // SPKI Ed25519
    try { return crypto.verify(null, Buffer.from(h + '.' + p), crypto.createPublicKey({ key: der, format: 'der', type: 'spki' }), b64u(s)); } catch (_) { return false; }
  });
  if (!ok) throw new Error('firma inválida');
  const t = Math.floor(now / 1000);
  if (payload.iss !== 'solvex-hub') throw new Error('emisor inválido');
  if (audience && payload.aud !== audience) throw new Error('el token no es para esta instancia');
  if (payload.nbf && t + clockSkewSec < payload.nbf) throw new Error('token aún no válido');
  if (!payload.exp || t - clockSkewSec > payload.exp) throw new Error('token vencido');
  return payload;
}

/** Verifica un webhook del Hub. rawBody: el cuerpo EXACTO recibido (Buffer o string). */
function verifyWebhook({ secret, timestamp, signature, rawBody, toleranceSec = 300 }) {
  const ts = Number(timestamp);
  if (!Number.isInteger(ts) || Math.abs(Date.now() / 1000 - ts) > toleranceSec) return false;
  const want = 'v1=' + crypto.createHmac('sha256', secret).update(ts + '.' + rawBody).digest('hex');
  const a = Buffer.from(want), b = Buffer.from(String(signature || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Modo efectivo ahora (corta sin conexión si el token anunció un corte que ya pasó). */
function effectiveMode(payload, now = Date.now()) {
  if (!payload) return 'blocked';
  const cut = payload.auto_cut ? (payload.cut_at || payload.grace_end) : null;
  if (['full', 'warning'].includes(payload.mode) && cut && now > Date.parse(cut)) return 'restricted';
  return payload.mode;
}

async function syncAll({ hubUrl, apiKey, keys, audience }) {
  const r = await fetch(hubUrl.replace(/\/+$/, '') + '/v1/instance/licenses', { headers: { Authorization: 'Bearer ' + apiKey }, signal: AbortSignal.timeout(15000) });
  if (!r.ok) throw new Error('Hub HTTP ' + r.status);
  const j = await r.json();
  return j.licenses.map((x) => ({ tenant: x.tenant_ref, payload: verifyToken(x.token, keys, { audience }), token: x.token }));
}

/** Producto instalable: activación con clave y renovación periódica. */
class Activation {
  constructor({ hubUrl, licenseKey, keys, cacheFile, label = os.hostname() }) {
    Object.assign(this, { hubUrl: hubUrl.replace(/\/+$/, ''), licenseKey, keys, cacheFile, label });
  }
  /** Huella del equipo (no secreta; ata la activación a esta máquina). */
  fingerprint() {
    const nets = Object.values(os.networkInterfaces()).flat().filter((n) => n && !n.internal && n.mac !== '00:00:00:00:00:00').map((n) => n.mac).sort();
    return crypto.createHash('sha256').update([os.hostname(), os.platform(), os.arch(), os.cpus()[0] && os.cpus()[0].model, nets[0] || ''].join('|')).digest('hex');
  }
  async call(path) {
    const r = await fetch(this.hubUrl + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ license_key: this.licenseKey, fingerprint: this.fingerprint(), label: this.label }), signal: AbortSignal.timeout(15000) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.message || 'Hub HTTP ' + r.status);
    const payload = verifyToken(j.token, this.keys, { audience: 'onprem' });
    if (payload.fp !== crypto.createHash('sha256').update('fp:' + this.fingerprint()).digest('hex')) throw new Error('el token es de otro equipo');
    fs.writeFileSync(this.cacheFile, j.token, { mode: 0o600 });
    return payload;
  }
  activate() { return this.call('/v1/activate'); }
  refresh() { return this.call('/v1/refresh'); }
  /** Estado actual: intenta renovar; si no hay conexión usa el token guardado mientras no venza. */
  async status() {
    try { return effectiveMode(await this.refresh()); } catch (e) {
      try { return effectiveMode(verifyToken(fs.readFileSync(this.cacheFile, 'utf8'), this.keys, { audience: 'onprem' })); } catch (_) { return 'blocked'; }
    }
  }
}

/**
 * Prueba gratis autoservicio (POST /v1/instance/trials). Devuelve { status: 'ok'|'existing'|'used'|'error', token?, message? }.
 * Una prueba por documento (RUC/DNI) y producto; repetirla con el mismo tenant_ref es idempotente.
 */
async function requestTrial({ hubUrl, apiKey, tenantRef, docType, docNumber, businessName, email, phone, planCode }) {
  const body = { tenant_ref: tenantRef, doc_type: docType, doc_number: docNumber, business_name: businessName };
  if (email) body.email = email;
  if (phone) body.phone = phone;
  if (planCode) body.plan_code = planCode;
  let r;
  try {
    r = await fetch(hubUrl.replace(/\/+$/, '') + '/v1/instance/trials', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) {
    return { status: 'error', message: 'Sin conexión con Solvex Hub' };
  }
  const data = await r.json().catch(() => ({}));
  if (r.status === 201) return { status: 'ok', token: data.token, license_code: data.license_code };
  if (r.status === 200) return { status: 'existing', token: data.token, license_code: data.license_code };
  if (r.status === 409 && data.error === 'PRUEBA_USADA') return { status: 'used', message: data.message };
  return { status: 'error', message: data.message || ('HTTP ' + r.status) };
}

module.exports = { verifyToken, verifyWebhook, effectiveMode, syncAll, Activation, requestTrial };
