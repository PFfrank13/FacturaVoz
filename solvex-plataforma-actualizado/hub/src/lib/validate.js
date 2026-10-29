'use strict';
/**
 * Validación estricta de entradas. Regla: el servidor solo toma los campos que declara el esquema
 * (lo demás se ignora: evita la "asignación masiva", por ejemplo que alguien mande status:"activa"
 * o role:"propietario" en un formulario que no lo permite).
 */
class ValidationError extends Error {
  constructor(field, message) { super(message); this.field = field; this.status = 400; this.code = 'VALIDACION'; }
}

const CTRL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f‪-‮⁦-⁩]/g; // control y bidi (evita textos engañosos)

function clean(s, { multiline = false } = {}) {
  let v = String(s).normalize('NFC').replace(CTRL, '');
  if (!multiline) v = v.replace(/[\r\n\t]+/g, ' ');
  return v.trim();
}

const rule = (fn, opts = {}) => ({ fn, optional: !!opts.optional, def: opts.default });

function str({ min = 0, max = 200, optional = false, pattern = null, multiline = false, default: d } = {}) {
  return rule((v, f) => {
    if (typeof v !== 'string' && typeof v !== 'number') throw new ValidationError(f, 'Debe ser texto.');
    const s = clean(v, { multiline });
    if (s.length < min) throw new ValidationError(f, min <= 1 ? 'Es obligatorio.' : `Mínimo ${min} caracteres.`);
    if (s.length > max) throw new ValidationError(f, `Máximo ${max} caracteres.`);
    if (pattern && s && !pattern.test(s)) throw new ValidationError(f, 'Formato no válido.');
    return s;
  }, { optional, default: d });
}

function oneOf(values, { optional = false, default: d } = {}) {
  return rule((v, f) => { if (!values.includes(v)) throw new ValidationError(f, 'Valor no permitido.'); return v; }, { optional, default: d });
}

function int({ min = -1e12, max = 1e12, optional = false, default: d } = {}) {
  return rule((v, f) => {
    const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
    if (!Number.isInteger(n)) throw new ValidationError(f, 'Debe ser un número entero.');
    if (n < min || n > max) throw new ValidationError(f, `Debe estar entre ${min} y ${max}.`);
    return n;
  }, { optional, default: d });
}

function bool({ optional = false, default: d } = {}) {
  return rule((v, f) => {
    if (v === true || v === 'true' || v === 1 || v === '1' || v === 'on') return true;
    if (v === false || v === 'false' || v === 0 || v === '0' || v === '') return false;
    throw new ValidationError(f, 'Debe ser sí o no.');
  }, { optional, default: d });
}

/** Monto en soles ("150", "150.5", 150.50) → céntimos enteros. Nunca usa flotantes para guardar. */
function money({ min = 0, max = 10_000_000, optional = false, default: d } = {}) {
  return rule((v, f) => {
    const s = String(v).trim().replace(',', '.');
    if (!/^\d{1,9}(\.\d{1,2})?$/.test(s)) throw new ValidationError(f, 'Monto no válido (usa hasta 2 decimales).');
    const [a, b = ''] = s.split('.');
    const cents = Number(a) * 100 + Number((b + '00').slice(0, 2));
    if (cents < min * 100 || cents > max * 100) throw new ValidationError(f, 'Monto fuera de rango.');
    return cents;
  }, { optional, default: d });
}

const EMAIL = /^[^\s@<>"'(),;:\\[\]]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$/;
function email({ optional = false } = {}) {
  return rule((v, f) => {
    const s = clean(v).toLowerCase();
    if (s.length > 254 || !EMAIL.test(s) || s.includes('..')) throw new ValidationError(f, 'Correo no válido.');
    return s;
  }, { optional });
}

/** Celular: acepta 9 dígitos peruanos (9xxxxxxxx) o internacional con código (10-15 dígitos). Guarda solo dígitos con código de país. */
function phone({ optional = false } = {}) {
  return rule((v, f) => {
    const d = String(v).replace(/[\s()+-]/g, '');
    if (/^9\d{8}$/.test(d)) return '51' + d;
    if (/^\d{10,15}$/.test(d)) return d;
    throw new ValidationError(f, 'Celular no válido (9 dígitos, empieza con 9).');
  }, { optional });
}

/** Documento peruano según tipo. RUC con dígito verificador (módulo 11 de SUNAT). */
function rucOk(r) {
  if (!/^(10|15|16|17|20)\d{9}$/.test(r)) return false;
  const w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const s = w.reduce((a, x, i) => a + x * Number(r[i]), 0);
  let dv = 11 - (s % 11); if (dv === 10) dv = 0; if (dv === 11) dv = 1;
  return dv === Number(r[10]);
}
function docNumber(type, value, field = 'doc_number') {
  const s = String(value || '').replace(/\s/g, '').toUpperCase();
  if (type === 'DNI' && !/^\d{8}$/.test(s)) throw new ValidationError(field, 'El DNI tiene 8 dígitos.');
  if (type === 'RUC' && !rucOk(s)) throw new ValidationError(field, 'RUC no válido (11 dígitos con dígito verificador correcto).');
  if (type === 'CE' && !/^[A-Z0-9]{8,12}$/.test(s)) throw new ValidationError(field, 'Carné de extranjería no válido.');
  if (type === 'PAS' && !/^[A-Z0-9]{6,15}$/.test(s)) throw new ValidationError(field, 'Pasaporte no válido.');
  if (type === 'EXT' && !/^[A-Z0-9-]{3,15}$/.test(s)) throw new ValidationError(field, 'Documento tributario extranjero no válido (3 a 15 letras, números o guiones).');
  return s;
}

function date({ optional = false } = {}) {
  return rule((v, f) => {
    if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v) || Number.isNaN(Date.parse(v + 'T00:00:00Z'))) throw new ValidationError(f, 'Fecha no válida (AAAA-MM-DD).');
    const back = new Date(v + 'T00:00:00Z').toISOString().slice(0, 10);
    if (back !== v) throw new ValidationError(f, 'Fecha inexistente.');
    return v;
  }, { optional });
}

function id(prefix, { optional = false } = {}) {
  const rx = new RegExp('^' + prefix + '_[a-z0-9]{20}$');
  return rule((v, f) => { if (typeof v !== 'string' || !rx.test(v)) throw new ValidationError(f, 'Identificador no válido.'); return v; }, { optional });
}

/** URL https (o http solo a localhost si allowHttpLocal). Bloquea usuario:clave en la URL. */
function url({ optional = false, allowHttpLocal = false } = {}) {
  return rule((v, f) => {
    let u; try { u = new URL(String(v).trim()); } catch (_) { throw new ValidationError(f, 'URL no válida.'); }
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(u.hostname);
    if (u.protocol !== 'https:' && !(allowHttpLocal && local && u.protocol === 'http:')) throw new ValidationError(f, 'La URL debe usar https://');
    if (u.username || u.password) throw new ValidationError(f, 'La URL no puede llevar usuario ni contraseña.');
    if (String(v).length > 500) throw new ValidationError(f, 'URL demasiado larga.');
    return u.toString();
  }, { optional });
}

function arrayOf(inner, { max = 50, optional = false } = {}) {
  return rule((v, f) => {
    if (!Array.isArray(v)) throw new ValidationError(f, 'Debe ser una lista.');
    if (v.length > max) throw new ValidationError(f, `Máximo ${max} elementos.`);
    return v.map((x, i) => inner.fn(x, f + '[' + i + ']'));
  }, { optional });
}

/** Objeto de límites/funciones de un plan: { clave: número | sí/no }. */
function features({ optional = true } = {}) {
  return rule((v, f) => {
    if (v == null || v === '') return {};
    if (typeof v !== 'object' || Array.isArray(v)) throw new ValidationError(f, 'Formato de funciones no válido.');
    const out = {}; const keys = Object.keys(v);
    if (keys.length > 40) throw new ValidationError(f, 'Demasiadas funciones.');
    for (const k of keys) {
      if (!/^[a-z][a-z0-9_]{1,39}$/.test(k)) throw new ValidationError(f, 'Clave de función no válida: ' + k);
      const x = v[k];
      if (typeof x === 'boolean') out[k] = x;
      else if (Number.isInteger(x) && x >= -1 && x <= 1e6) out[k] = x; // -1 = ilimitado
      else throw new ValidationError(f, 'Valor no válido para ' + k);
    }
    return out;
  }, { optional });
}

function parse(input, schema) {
  const src = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
  const out = {};
  for (const [k, r] of Object.entries(schema)) {
    const v = src[k];
    if (v === undefined || v === null || (v === '' && r.optional)) {
      if (r.def !== undefined) { out[k] = r.def; continue; }
      if (r.optional) { out[k] = null; continue; }
      throw new ValidationError(k, 'Es obligatorio.');
    }
    out[k] = r.fn(v, k);
  }
  return out;
}

module.exports = { ValidationError, parse, str, oneOf, int, bool, money, email, phone, docNumber, rucOk, date, id, url, arrayOf, features, clean };
