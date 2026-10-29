'use strict';
/** Utilidades de prueba: Hub en memoria, cliente HTTP con cookies y CSRF, usuarios con 2FA. */
const crypto = require('node:crypto');
const { build } = require('../src/config');
const { createHub } = require('../src/hub');
const { FakeGateway } = require('../src/gateways/culqi');
const jws = require('../src/lib/jws');
const totp = require('../src/lib/totp');
const { Db } = require('../src/db');

const quiet = { info() {}, warn() {}, error() {}, log() {} };

function testConfig(env = {}, { dev = true } = {}) {
  const kp = jws.generateKeyPair();
  const r = () => crypto.randomBytes(32).toString('base64');
  return build({ dev, skipDotEnv: true, env: Object.assign({
    DATA_KEYS: 'k1:' + r(), DATA_KEY_ACTIVE: 'k1', BIDX_KEY: r(), AUDIT_KEY: r(), BACKUP_KEY: r(),
    LICENSE_SIGNING_KEY: Buffer.from(kp.privatePem).toString('base64'), DB_PATH: ':memory:', PUBLIC_URL: 'http://localhost:8080',
    SITE_ORIGINS: 'https://solvex.pe', CULQI_WEBHOOK_SECRET: 'w'.repeat(32),
  }, env) });
}

/** fetch simulado para webhooks salientes: guarda cada llamada y responde según `responder`. */
function fakeFetch() {
  const calls = [];
  const f = async (url, opts) => {
    calls.push({ url, opts, body: opts && opts.body ? JSON.parse(opts.body) : null, headers: opts && opts.headers });
    const status = f.responder ? f.responder(url, opts) : 200;
    return { ok: status >= 200 && status < 300, status, json: async () => ({}) };
  };
  f.calls = calls; f.responder = null;
  return f;
}

async function startHub({ env = {}, dev = true, file = null } = {}) {
  const config = testConfig(env, { dev });
  const fetchImpl = fakeFetch();
  const gateway = new FakeGateway();
  const hub = createHub(config, { gateway, fetchImpl, log: quiet, db: file ? new Db(file) : undefined });
  const server = hub.app.server();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const stop = () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); });
  return { hub, server, base, fetchImpl, gateway, config, stop };
}

class Client {
  constructor(base) { this.base = base; this.cookies = {}; this.csrf = null; }
  async req(method, path, body, headers = {}) {
    const h = Object.assign({}, headers);
    const ck = Object.entries(this.cookies).map(([k, v]) => `${k}=${v}`).join('; ');
    if (ck) h.Cookie = ck;
    if (body !== undefined) h['Content-Type'] = h['Content-Type'] || 'application/json';
    if (this.csrf && !h['X-CSRF-Token'] && method !== 'GET') h['X-CSRF-Token'] = this.csrf;
    const res = await fetch(this.base + path, { method, headers: h, body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)), redirect: 'manual' });
    for (const c of res.headers.getSetCookie ? res.headers.getSetCookie() : []) {
      const [kv] = c.split(';'); const i = kv.indexOf('='); const k = kv.slice(0, i), v = kv.slice(i + 1);
      if (/Max-Age=0/.test(c) || v === '') delete this.cookies[k]; else this.cookies[k] = v;
    }
    let json = null; const text = await res.text();
    try { json = JSON.parse(text); } catch (_) { json = null; }
    if (json && json.csrf) this.csrf = json.csrf;
    return { status: res.status, json, text, headers: res.headers };
  }
  get(p, h) { return this.req('GET', p, undefined, h); }
  post(p, b = {}, h) { return this.req('POST', p, b, h); }
  put(p, b = {}, h) { return this.req('PUT', p, b, h); }
  del(p, h) { return this.req('DELETE', p, undefined, h); }
}

const PASSWORD = 'caballo-correcto-bateria-grapa';

/** Crea un usuario listo (contraseña definitiva + 2FA) directamente en la base. */
async function makeUser(hub, { email = 'dueno@solvex.pe', name = 'Dueño', role = 'propietario' } = {}) {
  const u = await hub.auth.createUser({ email, name, role, password: PASSWORD }, { type: 'sistema', label: 'pruebas' });
  const secret = totp.generateSecret();
  hub.db.run('UPDATE users SET must_change_password = 0, totp_enabled = 1, totp_secret_enc = ? WHERE id = ?', hub.vault.encrypt(secret, 'users.totp:' + u.id), u.id);
  return { id: u.id, email, secret };
}

/** Código TOTP válido (reinicia el contador anti-repetición, solo en pruebas). */
function code(hub, user) {
  hub.db.run('UPDATE users SET totp_last_counter = -1 WHERE id = ?', user.id);
  return totp.hotp(user.secret, totp.counterAt(Date.now()));
}

async function login(t, user) {
  const c = new Client(t.base);
  const r1 = await c.post('/api/admin/auth/login', { email: user.email, password: PASSWORD });
  if (r1.status !== 200) throw new Error('login falló: ' + r1.text);
  const r2 = await c.post('/api/admin/auth/totp', { code: code(t.hub, user) });
  if (r2.status !== 200) throw new Error('2fa falló: ' + r2.text);
  return c;
}

async function sudo(t, c, user) { const r = await c.post('/api/admin/auth/sudo', { code: code(t.hub, user) }); if (r.status !== 200) throw new Error('sudo falló ' + r.text); }

/** Producto + plan + instancia + cliente básicos. */
async function catalog(t, c, user, { kind = 'saas', price = '150', interval_unit = 'month', grace = 5, trial = 30, webhook = 'http://localhost:9999/solvex/webhook' } = {}) {
  const p = await c.post('/api/admin/products', { code: 'BARBERIA' + Math.floor(Math.random() * 1e6), name: 'Sistema de Barbería', kind, public: true, feature_keys: ['max_branches'] });
  if (p.status !== 201) throw new Error(p.text);
  const pl = await c.post(`/api/admin/products/${p.json.product.id}/plans`, { code: 'MENSUAL', name: 'Mensual', interval_unit, interval_count: 1, price, trial_days: trial, grace_days: grace, public: true, features: { max_branches: 1 } });
  if (pl.status !== 201) throw new Error(pl.text);
  await sudo(t, c, user);
  const ins = await c.post('/api/admin/instances', { product_id: p.json.product.id, name: 'Barbería SaaS', environment: 'produccion', webhook_url: webhook });
  if (ins.status !== 201) throw new Error(ins.text);
  const cl = await c.post('/api/admin/clients', { kind: 'empresa', display_name: 'Barbería Don Corte', doc_type: 'RUC', doc_number: '20100047218', contact_name: 'Luis Ramos', email: 'luis@doncorte.pe', phone: '987654321', city: 'Ica' });
  if (cl.status !== 201) throw new Error(cl.text);
  return { product: p.json.product, plan: pl.json.plan, instance: ins.json.instance, apiKey: ins.json.apiKey, webhookSecret: ins.json.webhookSecret, client: cl.json.client };
}

/** Simula el paso del tiempo moviendo las fechas de la licencia hacia atrás. */
function shiftDays(hub, licId, days) {
  const ms = days * 864e5;
  const l = hub.db.get('SELECT period_end, grace_end FROM licenses WHERE id = ?', licId);
  const mv = (iso) => (iso ? new Date(Date.parse(iso) - ms).toISOString() : iso);
  hub.db.run('UPDATE licenses SET period_end = ?, grace_end = ? WHERE id = ?', mv(l.period_end), mv(l.grace_end), licId);
}

const keysOf = (hub) => ({ [hub.config.signing.kid]: hub.config.signing.publicPem });

module.exports = { testConfig, startHub, Client, makeUser, code, login, sudo, catalog, shiftDays, keysOf, PASSWORD, fakeFetch, quiet };
