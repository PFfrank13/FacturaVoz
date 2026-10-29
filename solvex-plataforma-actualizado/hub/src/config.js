'use strict';
/**
 * Configuración desde variables de entorno (.env). En producción el Hub se niega a arrancar si
 * falta un secreto o es débil: es mejor no arrancar que arrancar inseguro.
 *
 * En desarrollo (npm run dev) genera secretos de prueba en data/dev-secrets.json para que
 * funcione sin configurar nada. Esos secretos NUNCA se usan en producción.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const jws = require('./lib/jws');
const { isValidTz } = require('./lib/time');

function loadDotEnv(file) {
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (!m || line.trim().startsWith('#')) continue;
    let v = m[2];
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    if (process.env[m[1]] === undefined) process.env[m[1]] = v;
  }
}

const key32 = (name, v) => {
  const b = Buffer.from(String(v || ''), 'base64');
  if (b.length !== 32) throw new Error(`${name} debe ser de 32 bytes en base64 (usa: npm run setup)`);
  return b;
};

function devSecrets(dir) {
  const f = path.join(dir, 'dev-secrets.json');
  if (fs.existsSync(f)) return JSON.parse(fs.readFileSync(f, 'utf8'));
  const r = () => crypto.randomBytes(32).toString('base64');
  const kp = jws.generateKeyPair();
  const s = {
    DATA_KEYS: 'k1:' + r(), DATA_KEY_ACTIVE: 'k1', BIDX_KEY: r(), AUDIT_KEY: r(), BACKUP_KEY: r(),
    LICENSE_SIGNING_KEY: Buffer.from(kp.privatePem).toString('base64'), CULQI_WEBHOOK_SECRET: crypto.randomBytes(24).toString('hex'),
  };
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  fs.writeFileSync(f, JSON.stringify(s, null, 2), { mode: 0o600 });
  return s;
}

function build(overrides = {}) {
  if (!overrides.skipDotEnv) loadDotEnv(path.resolve(process.cwd(), '.env'));
  // Por defecto PRODUCCIÓN (lo seguro). El modo desarrollo hay que pedirlo: --dev o NODE_ENV=development.
  const dev = overrides.dev ?? (process.argv.includes('--dev') || process.env.NODE_ENV === 'development');
  const env = Object.assign({}, process.env, overrides.env || {});
  const production = !dev;
  const dataDir = path.dirname(path.resolve(env.DB_PATH || './data/hub.db'));
  if (dev && !overrides.env?.DATA_KEYS && !env.DATA_KEYS) Object.assign(env, devSecrets(dataDir), { ...env });

  const errors = [];
  const need = (k) => { if (!env[k]) errors.push(`Falta ${k}`); return env[k]; };

  const keys = {};
  for (const part of String(need('DATA_KEYS') || '').split(',').filter(Boolean)) {
    const [id, b64] = part.split(':');
    try { keys[id] = key32('DATA_KEYS ' + id, b64); } catch (e) { errors.push(e.message); }
  }
  const active = env.DATA_KEY_ACTIVE || Object.keys(keys).pop();
  if (active && !keys[active]) errors.push('DATA_KEY_ACTIVE no está en DATA_KEYS');

  let bidxKey, auditKey, backupKey, signingKey = null;
  try { bidxKey = key32('BIDX_KEY', need('BIDX_KEY')); } catch (e) { errors.push(e.message); }
  try { auditKey = key32('AUDIT_KEY', need('AUDIT_KEY')); } catch (e) { errors.push(e.message); }
  try { backupKey = env.BACKUP_KEY ? key32('BACKUP_KEY', env.BACKUP_KEY) : null; } catch (e) { errors.push(e.message); }
  try { signingKey = jws.loadPrivateKey(need('LICENSE_SIGNING_KEY')); } catch (e) { errors.push('LICENSE_SIGNING_KEY: ' + e.message); }
  if (bidxKey && auditKey && bidxKey.equals(auditKey)) errors.push('BIDX_KEY y AUDIT_KEY deben ser distintas');

  const publicUrl = (env.PUBLIC_URL || (production ? '' : `http://localhost:${env.PORT || 8080}`)).replace(/\/+$/, '');
  if (production && !/^https:\/\//.test(publicUrl)) errors.push('PUBLIC_URL debe empezar con https:// en producción');

  const tz = env.DEFAULT_TIMEZONE || 'America/Lima';
  if (!isValidTz(tz)) errors.push('DEFAULT_TIMEZONE no es una zona horaria válida');

  const culqi = env.CULQI_SECRET_KEY ? {
    publicKey: env.CULQI_PUBLIC_KEY || '', secretKey: env.CULQI_SECRET_KEY, apiBase: env.CULQI_API_BASE || 'https://api.culqi.com/v2',
    webhookSecret: env.CULQI_WEBHOOK_SECRET || '',
  } : null;
  if (culqi && (!culqi.publicKey || String(culqi.webhookSecret).length < 24)) errors.push('Con Culqi activo se necesitan CULQI_PUBLIC_KEY y CULQI_WEBHOOK_SECRET (24+ caracteres)');
  if (production && culqi && /^sk_test_/.test(culqi.secretKey)) console.warn('AVISO: producción con llaves de PRUEBA de Culqi.');

  // Comprobantes electrónicos (boleta/factura): proveedor OSE/PSE. En desarrollo, simulado.
  const einvoice = { provider: env.EINVOICE_PROVIDER || (dev ? 'simulado' : 'none'), url: env.NUBEFACT_URL || '', token: env.NUBEFACT_TOKEN || '' };
  if (!['none', 'simulado', 'nubefact'].includes(einvoice.provider)) errors.push('EINVOICE_PROVIDER debe ser none, simulado o nubefact');
  if (production && einvoice.provider === 'simulado') errors.push('EINVOICE_PROVIDER=simulado no se permite en producción');
  if (einvoice.provider === 'nubefact' && (!/^https:\/\//.test(einvoice.url) || einvoice.token.length < 20)) errors.push('Con Nubefact se necesitan NUBEFACT_URL (https) y NUBEFACT_TOKEN');

  // Merchant of Record: secretos para verificar la firma de sus webhooks (se activa cada uno si tiene secreto).
  const mor = {};
  for (const [k, name] of [['paddle', 'PADDLE_WEBHOOK_SECRET'], ['lemonsqueezy', 'LEMONSQUEEZY_WEBHOOK_SECRET']]) {
    if (!env[name]) continue;
    if (String(env[name]).length < 16) errors.push(`${name} es demasiado corto`); else mor[k] = { secret: env[name] };
  }

  // Llaves públicas adicionales para rotación (la nueva se anuncia antes de empezar a firmar con ella).
  const extraPublic = String(env.LICENSE_EXTRA_PUBLIC_KEYS || '').split(',').map((s) => s.trim()).filter(Boolean)
    .map((b64) => Buffer.from(b64, 'base64').toString('utf8'));

  if (errors.length) {
    const e = new Error('Configuración inválida:\n - ' + errors.join('\n - '));
    e.configErrors = errors; throw e;
  }

  const signingPublicPem = jws.publicPemOf(signingKey);
  return {
    dev, production,
    host: env.HOST || (production ? '127.0.0.1' : '0.0.0.0'),
    port: Number(env.PORT) || 8080,
    publicUrl,
    trustProxy: Number(env.TRUST_PROXY || 0),
    dbPath: env.DB_PATH || './data/hub.db',
    company: { name: env.COMPANY_NAME || 'Solvex', supportEmail: env.SUPPORT_EMAIL || '', supportPhone: env.SUPPORT_WHATSAPP || '' },
    defaultTimezone: tz,
    vaultKeys: keys, vaultActive: active, bidxKey, auditKey, backupKey,
    signing: { key: signingKey, publicPem: signingPublicPem, kid: jws.kidOf(signingPublicPem), extraPublic },
    tokenTtlHours: Math.min(168, Math.max(1, Number(env.TOKEN_TTL_HOURS) || 72)),
    siteOrigins: String(env.SITE_ORIGINS || (production ? '' : 'http://localhost:5500,http://127.0.0.1:5500')).split(',').map((s) => s.trim()).filter(Boolean),
    adminAllowedIps: String(env.ADMIN_ALLOWED_IPS || '').split(',').map((s) => s.trim()).filter(Boolean),
    culqi,
    einvoice, mor,
    email: { provider: env.EMAIL_PROVIDER || 'log', apiKey: env.EMAIL_API_KEY || '', from: env.EMAIL_FROM || 'Solvex <no-responder@localhost>' },
    whatsapp: env.WA_TOKEN && env.WA_PHONE_ID ? { token: env.WA_TOKEN, phoneId: env.WA_PHONE_ID, version: env.WA_API_VERSION || 'v21.0', lang: env.WA_LANG || 'es' } : null,
    turnstileSecret: env.TURNSTILE_SECRET || '',
    session: { idleMin: Number(env.SESSION_IDLE_MIN) || 30, absoluteHours: Number(env.SESSION_MAX_HOURS) || 10 },
    schedulerEnabled: env.SCHEDULER !== 'off',
  };
}

module.exports = { build, loadDotEnv };
