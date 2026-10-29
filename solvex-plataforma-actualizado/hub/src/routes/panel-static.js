'use strict';
/**
 * Archivos del panel. Se cargan en memoria al arrancar desde una lista cerrada (no hay forma de
 * pedir "../../.env": solo existen las rutas de este mapa).
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sec = require('../http/security');
const { HttpError } = require('../http/app');

const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };

module.exports = (app, s) => {
  const dir = path.join(__dirname, '..', '..', 'panel');
  const files = new Map();
  const walk = (d, rel = '') => {
    for (const f of fs.readdirSync(d, { withFileTypes: true })) {
      if (f.name.startsWith('.')) continue;
      const p = path.join(d, f.name), r = rel + '/' + f.name;
      if (f.isDirectory()) walk(p, r);
      else if (TYPES[path.extname(f.name)]) {
        const body = fs.readFileSync(p);
        files.set(r, { body, type: TYPES[path.extname(f.name)], etag: '"' + crypto.createHash('sha256').update(body).digest('base64url').slice(0, 20) + '"' });
      }
    }
  };
  walk(dir);
  const headers = sec.headers('panel', { production: s.config.production });

  const serve = (ctx, rel) => {
    if (!sec.ipAllowed(ctx.ip, s.config.adminAllowedIps)) throw new HttpError(404, 'NO_ENCONTRADO', 'No encontrado.');
    if (s.config.dev) { files.clear(); walk(dir); } // en desarrollo se leen de disco en cada pedido (cambios al instante)
    const f = files.get(rel); if (!f) throw new HttpError(404, 'NO_ENCONTRADO', 'No encontrado.');
    headers(ctx);
    ctx.set('Cache-Control', rel === '/index.html' ? 'no-cache' : 'public, max-age=300');
    ctx.set('ETag', f.etag);
    if (ctx.header('if-none-match') === f.etag) { ctx.res.statusCode = 304; ctx.res.end(); return; }
    ctx.send(200, f.body, f.type);
  };

  app.get('/panel', (ctx) => { if (ctx.path === '/panel') { ctx.set('Location', '/panel/'); ctx.send(302, ''); return; } serve(ctx, '/index.html'); });
  app.get('/panel/:file', (ctx) => serve(ctx, '/' + ctx.params.file));
};
