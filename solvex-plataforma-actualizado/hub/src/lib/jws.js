'use strict';
/**
 * Tokens de licencia firmados con Ed25519 (formato JWS compacto: cabecera.contenido.firma).
 *
 * El Hub guarda la llave PRIVADA. Cada producto (barbería, restaurante...) guarda solo la llave
 * PÚBLICA y verifica la firma antes de creer lo que dice el token. Si alguien intercepta o edita
 * la respuesta (proxy, DNS falso, base de datos local manipulada), la firma deja de cuadrar.
 *
 * Rotación: cada llave tiene un "kid". El Hub puede publicar varias llaves públicas a la vez
 * (/.well-known/solvex-license-keys.json) para cambiar de llave sin cortar a nadie.
 */
const crypto = require('node:crypto');
const { b64u } = require('./crypto');

function loadPrivateKey(material) {
  if (!material) return null;
  const s = String(material).trim();
  const pem = s.includes('BEGIN') ? s.replace(/\\n/g, '\n') : Buffer.from(s, 'base64').toString('utf8');
  const key = crypto.createPrivateKey(pem);
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('La llave de firma debe ser Ed25519');
  return key;
}

function publicPemOf(privateKey) {
  return crypto.createPublicKey(privateKey).export({ type: 'spki', format: 'pem' }).toString();
}

/** kid estable derivado de la llave pública (no hace falta inventarlo). */
function kidOf(publicKeyPem) {
  const der = crypto.createPublicKey(publicKeyPem).export({ type: 'spki', format: 'der' });
  return 'slx-' + crypto.createHash('sha256').update(der).digest('base64url').slice(0, 16);
}

/** Llave pública cruda (32 bytes, base64) para verificarla con libsodium en PHP. */
function rawPublicKeyB64(publicKeyPem) {
  const jwk = crypto.createPublicKey(publicKeyPem).export({ format: 'jwk' });
  return Buffer.from(jwk.x, 'base64url').toString('base64');
}

function sign(privateKey, kid, payload, typ = 'slx-license+jwt') {
  const header = { alg: 'EdDSA', typ, kid };
  const input = b64u.enc(JSON.stringify(header)) + '.' + b64u.enc(JSON.stringify(payload));
  const sig = crypto.sign(null, Buffer.from(input), privateKey);
  return input + '.' + b64u.enc(sig);
}

/**
 * Verifica y devuelve el contenido, o lanza un error. keys: { kid: publicKeyPem }.
 * Comprueba firma, tipo, emisor (iss) y vigencia (nbf/exp) con una tolerancia de reloj.
 */
function verify(token, keys, { now = Date.now(), clockSkewSec = 120, iss = 'solvex-hub', typ = 'slx-license+jwt' } = {}) {
  const p = String(token || '').split('.');
  if (p.length !== 3) throw new Error('token mal formado');
  let header, payload;
  try { header = JSON.parse(b64u.dec(p[0]).toString()); payload = JSON.parse(b64u.dec(p[1]).toString()); }
  catch (_) { throw new Error('token ilegible'); }
  if (header.alg !== 'EdDSA' || header.typ !== typ) throw new Error('algoritmo o tipo no permitido');
  const pem = keys[header.kid];
  if (!pem) throw new Error('llave desconocida: ' + header.kid);
  const ok = crypto.verify(null, Buffer.from(p[0] + '.' + p[1]), crypto.createPublicKey(pem), b64u.dec(p[2]));
  if (!ok) throw new Error('firma inválida');
  const t = Math.floor(now / 1000);
  if (payload.iss !== iss) throw new Error('emisor inválido');
  if (typeof payload.nbf === 'number' && t + clockSkewSec < payload.nbf) throw new Error('token aún no válido');
  if (typeof payload.exp !== 'number' || t - clockSkewSec > payload.exp) throw new Error('token vencido');
  return payload;
}

/** Decodifica sin verificar (solo para mostrar en el panel). */
function decodeUnsafe(token) {
  const p = String(token || '').split('.');
  return { header: JSON.parse(b64u.dec(p[0]).toString()), payload: JSON.parse(b64u.dec(p[1]).toString()) };
}

function generateKeyPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  return {
    privatePem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    publicPem: publicKey.export({ type: 'spki', format: 'pem' }).toString(),
  };
}

module.exports = { loadPrivateKey, publicPemOf, kidOf, rawPublicKeyB64, sign, verify, decodeUnsafe, generateKeyPair };
