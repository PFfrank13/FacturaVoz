'use strict';
/**
 * Códigos de un solo uso basados en tiempo (TOTP, RFC 6238), compatibles con
 * Google Authenticator, Microsoft Authenticator, 1Password, Authy, etc.
 * SHA-1, 6 dígitos, pasos de 30 s y tolerancia de ±1 paso por relojes desfasados.
 */
const crypto = require('node:crypto');

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buf) {
  let bits = 0, value = 0, out = '';
  for (const b of buf) {
    value = (value << 8) | b; bits += 8;
    while (bits >= 5) { out += B32[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(s) {
  const clean = String(s).toUpperCase().replace(/[\s=-]/g, '');
  let bits = 0, value = 0; const out = [];
  for (const ch of clean) {
    const i = B32.indexOf(ch); if (i < 0) throw new Error('base32 inválido');
    value = (value << 5) | i; bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(out);
}

function generateSecret() { return base32Encode(crypto.randomBytes(20)); }

function hotp(secretB32, counter) {
  const key = base32Decode(secretB32);
  const msg = Buffer.alloc(8); msg.writeBigUInt64BE(BigInt(counter));
  const h = crypto.createHmac('sha1', key).update(msg).digest();
  const off = h[h.length - 1] & 15;
  const code = ((h[off] & 0x7f) << 24) | (h[off + 1] << 16) | (h[off + 2] << 8) | h[off + 3];
  return String(code % 1e6).padStart(6, '0');
}

const counterAt = (ms) => Math.floor(ms / 1000 / 30);

/**
 * Verifica un código. Devuelve el contador usado (para impedir que el mismo código se use dos veces)
 * o -1 si no es válido. lastCounter: el último contador aceptado para ese usuario.
 */
function verify(secretB32, code, { now = Date.now(), lastCounter = -1, window = 1 } = {}) {
  const c = String(code || '').replace(/\s/g, '');
  if (!/^\d{6}$/.test(c)) return -1;
  const base = counterAt(now);
  for (let w = -window; w <= window; w++) {
    const ctr = base + w;
    if (ctr <= lastCounter) continue; // código ya usado o anterior: reutilización bloqueada
    const want = hotp(secretB32, ctr);
    if (crypto.timingSafeEqual(Buffer.from(want), Buffer.from(c))) return ctr;
  }
  return -1;
}

function otpauthUrl({ secret, account, issuer = 'Solvex Hub' }) {
  const label = encodeURIComponent(issuer) + ':' + encodeURIComponent(account);
  return `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=6&period=30`;
}

module.exports = { generateSecret, hotp, verify, otpauthUrl, base32Encode, base32Decode, counterAt };
