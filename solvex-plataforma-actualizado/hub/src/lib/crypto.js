'use strict';
/**
 * Criptografía del Hub. Todo con node:crypto (sin librerías externas).
 *
 *  - Identificadores y secretos: siempre con crypto.randomBytes (CSPRNG). Nunca Math.random().
 *  - Datos personales en la base: AES-256-GCM con datos adicionales autenticados (AAD) que atan
 *    cada valor cifrado a su tabla, columna y fila. Copiar un valor cifrado a otra fila o columna
 *    hace que falle el descifrado.
 *  - Búsqueda exacta sobre datos cifrados (DNI/RUC, correo, celular): "índice ciego" con HMAC-SHA256.
 *  - Contraseñas: scrypt (memoria intensiva) con sal aleatoria.
 */
const crypto = require('node:crypto');

const b64u = {
  enc: (buf) => Buffer.from(buf).toString('base64url'),
  dec: (s) => Buffer.from(String(s), 'base64url'),
};

const ALPHA = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sin 0/O ni 1/I/L: se dictan por teléfono sin errores

/** Cadena aleatoria legible (para claves que una persona puede tener que copiar). */
function randomCode(len) {
  const out = [];
  while (out.length < len) {
    const bytes = crypto.randomBytes(len * 2);
    for (const b of bytes) {
      if (b < 256 - (256 % ALPHA.length)) out.push(ALPHA[b % ALPHA.length]); // sin sesgo de módulo
      if (out.length === len) break;
    }
  }
  return out.join('');
}

/** Identificador interno: prefijo + 20 caracteres aleatorios (~100 bits). No es adivinable ni secuencial. */
function newId(prefix) {
  return prefix + '_' + randomCode(20).toLowerCase();
}

/** Secreto para URLs o cabeceras: 32 bytes aleatorios en base64url (256 bits). */
function newSecret(bytes = 32) {
  return b64u.enc(crypto.randomBytes(bytes));
}

const sha256 = (data) => crypto.createHash('sha256').update(data).digest('hex');
const hmacHex = (key, data) => crypto.createHmac('sha256', key).update(data).digest('hex');

/** Comparación en tiempo constante para cadenas de cualquier largo. */
function safeEqual(a, b) {
  const x = crypto.createHash('sha256').update(String(a)).digest();
  const y = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(x, y) && String(a).length === String(b).length;
}

/* ------------------------------------------------------------------ */
/*  Cifrado de campos (AES-256-GCM)                                    */
/* ------------------------------------------------------------------ */
class Vault {
  /**
   * @param {object} o
   * @param {Record<string, Buffer>} o.keys  llaves de datos por id (32 bytes cada una)
   * @param {string} o.active                id de la llave con la que se cifra lo nuevo
   * @param {Buffer} o.bidxKey               llave del índice ciego (32 bytes)
   */
  constructor({ keys, active, bidxKey }) {
    if (!keys || !keys[active]) throw new Error('Vault: falta la llave activa ' + active);
    for (const [id, k] of Object.entries(keys)) {
      if (!/^[a-z0-9]{1,12}$/.test(id)) throw new Error('Vault: id de llave inválido ' + id);
      if (!Buffer.isBuffer(k) || k.length !== 32) throw new Error('Vault: la llave ' + id + ' debe tener 32 bytes');
    }
    if (!Buffer.isBuffer(bidxKey) || bidxKey.length !== 32) throw new Error('Vault: BIDX_KEY debe tener 32 bytes');
    this.keys = keys; this.active = active; this.bidxKey = bidxKey;
  }

  /** Cifra texto. aad = "tabla.columna:id". Devuelve "v1.<kid>.<iv>.<ct>.<tag>" o null si el valor está vacío. */
  encrypt(plain, aad) {
    if (plain == null || plain === '') return null;
    const iv = crypto.randomBytes(12);
    const c = crypto.createCipheriv('aes-256-gcm', this.keys[this.active], iv);
    c.setAAD(Buffer.from(String(aad)));
    const ct = Buffer.concat([c.update(String(plain), 'utf8'), c.final()]);
    return ['v1', this.active, b64u.enc(iv), b64u.enc(ct), b64u.enc(c.getAuthTag())].join('.');
  }

  decrypt(blob, aad) {
    if (blob == null || blob === '') return '';
    const p = String(blob).split('.');
    if (p.length !== 5 || p[0] !== 'v1' || !this.keys[p[1]]) throw new Error('Vault: valor cifrado ilegible');
    const d = crypto.createDecipheriv('aes-256-gcm', this.keys[p[1]], b64u.dec(p[2]));
    d.setAAD(Buffer.from(String(aad)));
    d.setAuthTag(b64u.dec(p[4]));
    return Buffer.concat([d.update(b64u.dec(p[3])), d.final()]).toString('utf8');
  }

  /** Id de la llave con la que se cifró un valor (para la rotación de llaves). */
  keyIdOf(blob) { const p = String(blob || '').split('.'); return p.length === 5 ? p[1] : null; }

  /** Índice ciego: HMAC del valor normalizado. Sirve para "¿existe este RUC?" sin guardar el RUC en claro. */
  bidx(kind, value) {
    const v = String(value == null ? '' : value).trim().toLowerCase();
    if (!v) return null;
    return hmacHex(this.bidxKey, kind + ':' + v).slice(0, 40);
  }
}

/* ------------------------------------------------------------------ */
/*  Contraseñas (scrypt)                                               */
/* ------------------------------------------------------------------ */
const SCRYPT = { N: 1 << 15, r: 8, p: 1, len: 32 };
const scryptAsync = (pw, salt, o) => new Promise((res, rej) =>
  crypto.scrypt(pw, salt, o.len, { N: o.N, r: o.r, p: o.p, maxmem: 128 * o.N * o.r * 2 }, (e, k) => (e ? rej(e) : res(k))));

async function hashPassword(pw) {
  const salt = crypto.randomBytes(16);
  const k = await scryptAsync(String(pw).normalize('NFKC'), salt, SCRYPT);
  return ['scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p, b64u.enc(salt), b64u.enc(k)].join('$');
}

async function verifyPassword(pw, stored) {
  const p = String(stored || '').split('$');
  if (p.length !== 6 || p[0] !== 'scrypt') { await scryptAsync('x', Buffer.alloc(16), SCRYPT); return false; }
  const o = { N: +p[1], r: +p[2], p: +p[3], len: 32 };
  const k = await scryptAsync(String(pw).normalize('NFKC'), b64u.dec(p[4]), o);
  const want = b64u.dec(p[5]);
  return want.length === k.length && crypto.timingSafeEqual(k, want);
}

/** Hash ficticio para igualar el tiempo de respuesta cuando el usuario no existe (evita enumerar correos). */
let dummyHash = null;
async function dummyVerify(pw) {
  if (!dummyHash) dummyHash = await hashPassword(crypto.randomBytes(16).toString('hex'));
  await verifyPassword(pw, dummyHash);
  return false;
}

/* ------------------------------------------------------------------ */
/*  Cifrado de archivos de respaldo (AES-256-GCM, formato propio)      */
/* ------------------------------------------------------------------ */
function encryptBuffer(key, buf) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', key, iv);
  c.setAAD(Buffer.from('solvex-backup-v1'));
  const ct = Buffer.concat([c.update(buf), c.final()]);
  return Buffer.concat([Buffer.from('SLXB1'), iv, c.getAuthTag(), ct]);
}
function decryptBuffer(key, blob) {
  if (blob.subarray(0, 5).toString() !== 'SLXB1') throw new Error('No es un respaldo de Solvex');
  const iv = blob.subarray(5, 17), tag = blob.subarray(17, 33), ct = blob.subarray(33);
  const d = crypto.createDecipheriv('aes-256-gcm', key, iv);
  d.setAAD(Buffer.from('solvex-backup-v1')); d.setAuthTag(tag);
  return Buffer.concat([d.update(ct), d.final()]);
}

module.exports = {
  b64u, randomCode, newId, newSecret, sha256, hmacHex, safeEqual, Vault,
  hashPassword, verifyPassword, dummyVerify, encryptBuffer, decryptBuffer,
};
