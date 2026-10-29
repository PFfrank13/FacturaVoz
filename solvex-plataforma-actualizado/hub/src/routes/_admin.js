'use strict';
/** Piezas comunes de la API del panel. */
const sec = require('../http/security');
const { HttpError } = require('../http/app');
const { requireUser } = require('../services/auth');
const { actorOf } = require('../services/audit');

const cache = new WeakMap();

function base(s) {
  if (cache.has(s)) return cache.get(s);
  const headers = sec.headers('api', { production: s.config.production });
  const limiter = sec.rateLimit({ max: 300, windowMs: 60_000, name: 'admin', message: 'Demasiadas solicitudes al panel.' });
  const expectedOrigin = new URL(s.config.publicUrl).origin;
  const guard = (ctx) => {
    headers(ctx);
    if (!sec.ipAllowed(ctx.ip, s.config.adminAllowedIps)) throw new HttpError(404, 'NO_ENCONTRADO', 'No encontrado.');
    limiter(ctx);
    // Defensa extra contra CSRF: si el navegador manda Origin en una escritura, debe ser el del Hub.
    if (!['GET', 'HEAD'].includes(ctx.method)) {
      const o = ctx.header('origin');
      if (o && o !== expectedOrigin && !(s.config.dev && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o))) throw new HttpError(403, 'ORIGEN', 'Origen no permitido.');
      const sf = ctx.header('sec-fetch-site');
      if (sf && !['same-origin', 'none'].includes(sf)) throw new HttpError(403, 'ORIGEN', 'Origen no permitido.');
    }
  };
  const out = { guard, limiter };
  cache.set(s, out);
  return out;
}

/** Atajo: [guard, requireUser({...})] */
function U(s, opts = {}) { return [base(s).guard, requireUser(s.auth, opts)]; }

const ip = (ctx) => ctx.ip;
const actor = actorOf;
const page = (ctx) => ({ limit: Math.min(200, Math.max(1, Number(ctx.query.get('limit')) || 50)), offset: Math.max(0, Number(ctx.query.get('offset')) || 0) });

module.exports = { base, U, ip, actor, page };
