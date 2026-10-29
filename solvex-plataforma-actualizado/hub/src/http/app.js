'use strict';
/**
 * Mini framework HTTP sobre node:http (sin Express). Lo justo y auditable:
 * rutas con parámetros, lectura de JSON con límite de tamaño, cookies, errores uniformes.
 */
const http = require('node:http');
const crypto = require('node:crypto');
const { ValidationError } = require('../lib/validate');

class HttpError extends Error {
  constructor(status, code, message, extra) { super(message || code); this.status = status; this.code = code; this.extra = extra; }
}

function compile(pattern) {
  const keys = [];
  const rx = new RegExp('^' + pattern.replace(/\/:([a-zA-Z_]+)/g, (_, k) => { keys.push(k); return '/([^/]+)'; }) + '/?$');
  return { rx, keys };
}

function parseCookies(h) {
  const out = {};
  for (const part of String(h || '').split(';')) {
    const i = part.indexOf('='); if (i < 0) continue;
    const k = part.slice(0, i).trim(), v = part.slice(i + 1).trim();
    if (k && !(k in out)) { try { out[k] = decodeURIComponent(v); } catch (_) { out[k] = v; } }
  }
  return out;
}

class Ctx {
  constructor(app, req, res) {
    this.app = app; this.req = req; this.res = res;
    this.method = req.method;
    const u = new URL(req.url, 'http://x');
    this.path = u.pathname; this.query = u.searchParams;
    this.params = {}; this.state = {};
    this.id = crypto.randomBytes(6).toString('hex');
    this.cookies = parseCookies(req.headers.cookie);
    this.ip = app.clientIp(req);
    this._raw = null;
  }
  header(n) { const v = this.req.headers[n.toLowerCase()]; return Array.isArray(v) ? v[0] : v || ''; }
  get done() { return this.res.writableEnded || this.res.headersSent; }

  /** Cuerpo crudo (Buffer) con límite de tamaño. */
  async raw(limit = 256 * 1024) {
    if (this._raw) return this._raw;
    const len = Number(this.header('content-length') || 0);
    if (len > limit) throw new HttpError(413, 'DEMASIADO_GRANDE', 'La solicitud es demasiado grande.');
    const chunks = []; let size = 0;
    for await (const c of this.req) {
      size += c.length;
      if (size > limit) throw new HttpError(413, 'DEMASIADO_GRANDE', 'La solicitud es demasiado grande.');
      chunks.push(c);
    }
    this._raw = Buffer.concat(chunks);
    return this._raw;
  }

  /** JSON del cuerpo. Exige Content-Type application/json (un formulario HTML de otro sitio no puede enviarlo sin CORS). */
  async json(limit) {
    if (this._json !== undefined) return this._json;
    const ct = this.header('content-type').toLowerCase();
    const buf = await this.raw(limit);
    if (!buf.length) { this._json = {}; return this._json; }
    if (!ct.startsWith('application/json')) throw new HttpError(415, 'TIPO_NO_SOPORTADO', 'Se esperaba JSON.');
    try { this._json = JSON.parse(buf.toString('utf8')); }
    catch (_) { throw new HttpError(400, 'JSON_INVALIDO', 'El cuerpo no es JSON válido.'); }
    if (this._json === null || typeof this._json !== 'object') throw new HttpError(400, 'JSON_INVALIDO', 'Se esperaba un objeto JSON.');
    return this._json;
  }

  set(h, v) { this.res.setHeader(h, v); return this; }
  setCookie(name, value, { maxAge, httpOnly = true, secure = true, sameSite = 'Strict', path = '/' } = {}) {
    const p = [`${name}=${encodeURIComponent(value)}`, `Path=${path}`, `SameSite=${sameSite}`];
    if (httpOnly) p.push('HttpOnly'); if (secure) p.push('Secure');
    if (maxAge != null) p.push(`Max-Age=${Math.floor(maxAge)}`);
    const prev = this.res.getHeader('Set-Cookie');
    this.res.setHeader('Set-Cookie', [].concat(prev || [], p.join('; ')));
  }
  send(status, body, type = 'application/json; charset=utf-8') {
    if (this.done) return;
    const data = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
    this.res.statusCode = status;
    if (!this.res.getHeader('Content-Type')) this.res.setHeader('Content-Type', type);
    this.res.setHeader('Content-Length', Buffer.byteLength(data));
    this.res.end(this.method === 'HEAD' ? undefined : data);
  }
  ok(body = { ok: true }) { this.send(200, body); }
  html(status, str) { this.send(status, str, 'text/html; charset=utf-8'); }
}

class App {
  constructor({ trustProxy = 0, log = console } = {}) {
    this.routes = []; this.before = []; this.trustProxy = trustProxy; this.log = log;
  }
  use(fn) { this.before.push(fn); }
  add(method, pattern, ...handlers) { this.routes.push({ method, ...compile(pattern), pattern, handlers }); }
  get(p, ...h) { this.add('GET', p, ...h); }
  post(p, ...h) { this.add('POST', p, ...h); }
  put(p, ...h) { this.add('PUT', p, ...h); }
  patch(p, ...h) { this.add('PATCH', p, ...h); }
  del(p, ...h) { this.add('DELETE', p, ...h); }

  /** IP real del cliente. Solo se confía en X-Forwarded-For si hay proxies declarados (TRUST_PROXY). */
  clientIp(req) {
    const direct = (req.socket && req.socket.remoteAddress || '').replace(/^::ffff:/, '');
    if (!this.trustProxy) return direct;
    const xff = String(req.headers['x-forwarded-for'] || '').split(',').map((s) => s.trim()).filter(Boolean);
    const i = xff.length - this.trustProxy;
    return (i >= 0 ? xff[i] : xff[0] || direct).replace(/^::ffff:/, '');
  }

  async handle(req, res) {
    const ctx = new Ctx(this, req, res);
    try {
      for (const fn of this.before) { await fn(ctx); if (ctx.done) return; }
      const method = ctx.method === 'HEAD' ? 'GET' : ctx.method;
      let pathMatched = false;
      for (const r of this.routes) {
        const m = r.rx.exec(ctx.path); if (!m) continue;
        pathMatched = true;
        if (r.method !== method) continue;
        r.keys.forEach((k, i) => { try { ctx.params[k] = decodeURIComponent(m[i + 1]); } catch (_) { ctx.params[k] = ''; } });
        ctx.route = r.pattern;
        for (const h of r.handlers) { await h(ctx); if (ctx.done) return; }
        if (!ctx.done) ctx.send(204, '');
        return;
      }
      throw pathMatched ? new HttpError(405, 'METODO_NO_PERMITIDO') : new HttpError(404, 'NO_ENCONTRADO', 'No encontrado.');
    } catch (e) {
      this.fail(ctx, e);
    }
  }

  fail(ctx, e) {
    if (ctx.done) return;
    if (e instanceof ValidationError) return ctx.send(400, { error: 'VALIDACION', field: e.field, message: e.message });
    if (e instanceof HttpError) return ctx.send(e.status, Object.assign({ error: e.code, message: e.message }, e.extra || {}));
    if (e && /UNIQUE constraint failed/.test(e.message)) return ctx.send(409, { error: 'DUPLICADO', message: 'Ya existe un registro con esos datos.' });
    if (e && /solo inserción|no se puede modificar|no se borran/.test(e.message)) return ctx.send(409, { error: 'BLOQUEADO', message: 'Ese registro está cerrado y no se puede cambiar.' });
    this.log.error(`[${ctx.id}] ${ctx.method} ${ctx.path}:`, e && e.stack || e);
    ctx.send(500, { error: 'ERROR_INTERNO', message: 'Ocurrió un error. Código: ' + ctx.id });
  }

  server() {
    const s = http.createServer({ requestTimeout: 30_000, headersTimeout: 15_000, maxHeaderSize: 16 * 1024 }, (req, res) => this.handle(req, res));
    s.keepAliveTimeout = 5000;
    return s;
  }
}

module.exports = { App, HttpError, parseCookies };
