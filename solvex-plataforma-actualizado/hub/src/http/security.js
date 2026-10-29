'use strict';
/**
 * Defensas HTTP: cabeceras de seguridad, límites de peticiones, CORS para el sitio público,
 * lista de IPs permitidas para el panel.
 */
const crypto = require('node:crypto');
const net = require('node:net');
const { HttpError } = require('./app');

const BASE = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), usb=(), payment=(self)',
  'X-Permitted-Cross-Domain-Policies': 'none',
};

const CSP = {
  api: "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
  panel: [
    "default-src 'none'", "script-src 'self'", "style-src 'self'",
    "font-src 'self'", "img-src 'self' data:", "connect-src 'self'",
    "manifest-src 'self'", "frame-ancestors 'none'", "base-uri 'none'", "form-action 'none'",
  ].join('; '),
  /** Página de pago: necesita el script y los marcos de Culqi. Ningún script en línea. */
  pay: [
    "default-src 'none'", "script-src 'self' https://checkout.culqi.com https://js.culqi.com",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com", "font-src https://fonts.gstatic.com",
    "img-src 'self' data: https://*.culqi.com", "connect-src 'self' https://*.culqi.com",
    'frame-src https://*.culqi.com', "frame-ancestors 'none'", "base-uri 'none'", "form-action 'self'",
  ].join('; '),
};

function headers(kind, { production } = {}) {
  return (ctx) => {
    for (const [k, v] of Object.entries(BASE)) ctx.set(k, v);
    ctx.set('Content-Security-Policy', CSP[kind]);
    ctx.set('Cross-Origin-Resource-Policy', kind === 'api' ? 'same-site' : 'same-origin');
    if (production) ctx.set('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
    ctx.set('Cache-Control', 'no-store'); // los archivos estáticos del panel lo reemplazan por su propia política
  };
}

/** Límite de peticiones en memoria por clave (IP, correo, etc.). Ventana fija. */
function rateLimit({ max, windowMs, key = (ctx) => ctx.ip, message = 'Demasiadas solicitudes. Intenta en unos minutos.', name = 'rl' }) {
  const hits = new Map();
  const t = setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (v.reset <= now) hits.delete(k); }, Math.min(windowMs, 60_000));
  t.unref();
  const mw = (ctx) => {
    const k = name + ':' + key(ctx), now = Date.now();
    let h = hits.get(k);
    if (!h || h.reset <= now) { h = { n: 0, reset: now + windowMs }; hits.set(k, h); }
    h.n++;
    if (h.n > max) {
      ctx.set('Retry-After', String(Math.ceil((h.reset - now) / 1000)));
      throw new HttpError(429, 'LIMITE', message);
    }
  };
  mw.reset = () => hits.clear();
  return mw;
}

/** CORS para los endpoints públicos que usa el sitio web (formulario, catálogo). */
function cors(origins) {
  return (ctx) => {
    const o = ctx.header('origin');
    if (o && origins.includes(o)) {
      ctx.set('Access-Control-Allow-Origin', o); ctx.set('Vary', 'Origin');
      ctx.set('Access-Control-Allow-Headers', 'Content-Type');
      ctx.set('Access-Control-Allow-Methods', 'GET, POST');
      ctx.set('Access-Control-Max-Age', '600');
    }
    if (ctx.method === 'OPTIONS') { ctx.send(204, ''); }
  };
}

/** Comprueba si una IP está en una lista de IPs o rangos CIDR ("190.12.0.0/16, 2001:db8::/32"). */
function ipAllowed(ip, list) {
  if (!list || !list.length) return true;
  const bl = new net.BlockList();
  for (const item of list) {
    const [addr, bits] = item.split('/');
    const type = net.isIPv6(addr) ? 'ipv6' : 'ipv4';
    if (!net.isIP(addr)) continue;
    if (bits) bl.addSubnet(addr, Number(bits), type); else bl.addAddress(addr, type);
  }
  if (!net.isIP(ip)) return false;
  return bl.check(ip, net.isIPv6(ip) ? 'ipv6' : 'ipv4');
}

/** Para guardar "de qué IP vino" sin guardar la IP (dato personal): hash diario con sal. */
function ipHash(ip, secret) {
  const day = new Date().toISOString().slice(0, 10);
  return crypto.createHmac('sha256', secret).update(day + '|' + ip).digest('hex').slice(0, 24);
}

/** Evita SSRF al registrar URLs de webhooks: nada de IPs privadas, locales o metadatos de nube. */
function isPublicHost(hostname) {
  const h = hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal')) return false;
  if (net.isIP(h)) {
    const bl = new net.BlockList();
    for (const [a, b] of [['10.0.0.0', 8], ['172.16.0.0', 12], ['192.168.0.0', 16], ['127.0.0.0', 8], ['169.254.0.0', 16], ['100.64.0.0', 10], ['0.0.0.0', 8]]) bl.addSubnet(a, b, 'ipv4');
    for (const [a, b] of [['::1', 128], ['fc00::', 7], ['fe80::', 10], ['::', 128]]) bl.addSubnet(a, b, 'ipv6');
    return !bl.check(h, net.isIPv6(h) ? 'ipv6' : 'ipv4');
  }
  return true;
}

module.exports = { headers, rateLimit, cors, ipAllowed, ipHash, isPublicHost, CSP };
