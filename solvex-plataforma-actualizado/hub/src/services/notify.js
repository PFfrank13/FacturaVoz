'use strict';
/**
 * Avisos a clientes por correo y WhatsApp, con cola persistente y reintentos.
 * Un fallo de envío nunca bloquea un pago ni un cambio de licencia: queda en cola y se reintenta.
 *
 * Correo: API HTTP de Resend o Brevo (EMAIL_PROVIDER). En desarrollo, "log" (se imprime en consola).
 * WhatsApp: Cloud API de Meta. Los mensajes que inicia la empresa DEBEN ser plantillas aprobadas
 * por Meta (ver docs/03-integracion-productos.md, sección plantillas).
 */
const C = require('../lib/crypto');
const { nowIso, localDate } = require('../lib/time');

const SYMBOL = { PEN: 'S/ ', USD: 'US$ ', EUR: '€ ', GBP: '£ ' };
const money = (c, currency = 'PEN') => (SYMBOL[currency] || String(currency || 'PEN') + ' ') + (Number(c || 0) / 100).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const MES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
function fecha(iso, tz) { if (!iso) return '—'; const d = localDate(iso, tz); const [y, m, dd] = d.split('-'); return `${+dd} de ${MES[+m - 1]} de ${y}`; }

/** Plantillas. vars: nombre, servicio, fecha, fecha_corte, monto, enlace, recibo, empresa. */
const T = {
  recordatorio: {
    wa: ['nombre', 'servicio', 'fecha', 'monto', 'enlace'],
    subject: (v) => `Tu servicio ${v.servicio} vence el ${v.fecha}`,
    text: (v) => `Hola ${v.nombre},\n\nTe recordamos que tu servicio ${v.servicio} está pagado hasta el ${v.fecha}.\nLa renovación es de ${v.monto}. Puedes pagar aquí:\n${v.enlace}\n\nAl confirmarse el pago, tu servicio sigue sin interrupciones.\n\n${v.empresa}`,
  },
  enlace_pago: {
    wa: ['nombre', 'servicio', 'monto', 'enlace'],
    subject: (v) => `Enlace de pago · ${v.servicio}`,
    text: (v) => `Hola ${v.nombre},\n\nAquí tienes tu enlace de pago para ${v.servicio} por ${v.monto}:\n${v.enlace}\n\nEste enlace es personal; no lo compartas.\n\n${v.empresa}`,
  },
  gracia: {
    wa: ['nombre', 'servicio', 'fecha_corte', 'monto', 'enlace'],
    subject: (v) => `Pago pendiente: ${v.servicio} se suspenderá el ${v.fecha_corte}`,
    text: (v) => `Hola ${v.nombre},\n\nTu servicio ${v.servicio} venció y está en periodo de gracia.\nSi no se registra el pago, se suspenderá automáticamente al terminar el ${v.fecha_corte}.\nMonto: ${v.monto}. Paga aquí:\n${v.enlace}\n\n${v.empresa}`,
  },
  suspension: {
    wa: ['nombre', 'servicio', 'monto', 'enlace'],
    subject: (v) => `Servicio suspendido: ${v.servicio}`,
    text: (v) => `Hola ${v.nombre},\n\nTu servicio ${v.servicio} fue suspendido por falta de pago. Tus datos se conservan.\nAl pagar (${v.monto}) se reactiva automáticamente en segundos:\n${v.enlace}\n\n${v.empresa}`,
  },
  reactivacion: {
    wa: ['nombre', 'servicio', 'fecha'],
    subject: (v) => `Servicio reactivado: ${v.servicio}`,
    text: (v) => `Hola ${v.nombre},\n\nRecibimos tu pago y tu servicio ${v.servicio} ya está activo, pagado hasta el ${v.fecha}.\nGracias.\n\n${v.empresa}`,
  },
  pago_recibido: {
    wa: ['nombre', 'monto', 'servicio', 'fecha', 'recibo'],
    subject: (v) => `Pago recibido · ${v.monto} · ${v.recibo}`,
    text: (v) => `Hola ${v.nombre},\n\nRecibimos tu pago de ${v.monto} por ${v.servicio}.\nVigente hasta: ${v.fecha}.\nN.º de recibo: ${v.recibo} (comprobante interno; la boleta o factura electrónica se emite aparte).\n\n${v.empresa}`,
  },
  pago_rechazado: {
    wa: ['nombre', 'monto', 'servicio', 'motivo'],
    subject: (v) => `No pudimos validar tu pago · ${v.servicio}`,
    text: (v) => `Hola ${v.nombre},\n\nNo pudimos validar el pago de ${v.monto} que reportaste para ${v.servicio}.\nMotivo: ${v.motivo}\nSi crees que es un error, responde a este mensaje con tu comprobante.\n\n${v.empresa}`,
  },
  pago_reportado: {
    wa: null, // solo correo: confirmación de que recibimos el reporte
    subject: (v) => `Recibimos tu reporte de pago · ${v.servicio}`,
    text: (v) => `Hola ${v.nombre},\n\nRecibimos tu reporte de pago por ${v.monto}. Lo verificaremos y te avisaremos cuando quede aprobado.\n\n${v.empresa}`,
  },
  reclamo_recibido: {
    wa: null,
    subject: (v) => `Constancia de ${v.tipo} N.º ${v.numero}`,
    text: (v) => `Hola ${v.nombre},\n\nRegistramos tu ${v.tipo} N.º ${v.numero} en nuestro Libro de Reclamaciones el ${v.fecha}.\nDetalle: ${v.detalle}\nPedido: ${v.pedido}\nTe responderemos a más tardar el ${v.plazo}.\n\n${v.empresa}`,
  },
  reclamo_respuesta: {
    wa: null,
    subject: (v) => `Respuesta a tu ${v.tipo} N.º ${v.numero}`,
    text: (v) => `Hola ${v.nombre},\n\nRespuesta a tu ${v.tipo} N.º ${v.numero}:\n\n${v.respuesta}\n\n${v.empresa}`,
  },
};

const escHtml = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function render(template, vars) {
  const t = T[template]; if (!t) throw new Error('Plantilla desconocida ' + template);
  const text = t.text(vars);
  const html = '<div style="font-family:system-ui,-apple-system,Segoe UI,sans-serif;max-width:520px;color:#0B1A2C;line-height:1.5">' +
    text.split('\n').map((l) => (/^https?:\/\//.test(l) ? `<p><a href="${escHtml(l)}" style="display:inline-block;background:#0D8460;color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none">Abrir enlace de pago</a><br><span style="font-size:12px;color:#5A6A77">${escHtml(l)}</span></p>` : `<p style="margin:6px 0">${escHtml(l) || '&nbsp;'}</p>`)).join('') + '</div>';
  return { subject: t.subject(vars), text, html };
}

class Notifier {
  constructor({ db, vault, config, log = console, fetchImpl = globalThis.fetch }) {
    this.db = db; this.vault = vault; this.cfg = config; this.log = log; this.fetch = fetchImpl; this.sending = false;
  }
  channels() { return { email: this.cfg.email.provider !== 'log' && !!this.cfg.email.apiKey, emailLog: this.cfg.email.provider === 'log', whatsapp: !!this.cfg.whatsapp }; }

  /** Datos de contacto descifrados de un cliente. */
  contactOf(client) {
    if (!client) return {};
    return {
      name: client.contact_name_enc ? this.vault.decrypt(client.contact_name_enc, 'clients.contact_name:' + client.id) : client.display_name,
      email: client.email_enc ? this.vault.decrypt(client.email_enc, 'clients.email:' + client.id) : '',
      phone: client.phone_enc ? this.vault.decrypt(client.phone_enc, 'clients.phone:' + client.id) : '',
    };
  }

  /**
   * Encola un aviso. to: { email, phone } (si no se da, se usan los del cliente).
   * dedupe: clave para no repetir el mismo aviso (ej. "recordatorio:lic_x:2026-11-18:3").
   */
  queue({ template, client, license = null, vars, to = null, dedupe = null, channels = ['email', 'whatsapp'] }) {
    const c = to || this.contactOf(client);
    const v = Object.assign({ empresa: this.cfg.company.name, nombre: (c.name || (client && client.display_name) || '').split(' ')[0] || 'cliente' }, vars);
    const ids = [];
    const add = (channel, addr, hint) => {
      const id = C.newId('ntf'), key = dedupe ? dedupe + ':' + channel : null;
      const r = this.db.run(`INSERT OR IGNORE INTO notifications (id,channel,to_enc,to_hint,template,payload_enc,client_id,license_id,status,next_attempt_at,dedupe_key,created_at)
        VALUES (?,?,?,?,?,?,?,?, 'pendiente', ?, ?, ?)`, id, channel, this.vault.encrypt(addr, 'notifications.to:' + id), hint, template,
        this.vault.encrypt(JSON.stringify(v), 'notifications.payload:' + id), client ? client.id : null, license ? license.id : null, nowIso(), key, nowIso());
      if (r.changes) ids.push(id);
    };
    if (channels.includes('email') && c.email) add('email', c.email, c.email.replace(/^(.).*(@.*)$/, '$1***$2'));
    if (channels.includes('whatsapp') && c.phone && T[template].wa && this.cfg.whatsapp) add('whatsapp', c.phone, '***' + String(c.phone).slice(-3));
    return ids;
  }

  async sendEmail(to, msg) {
    const e = this.cfg.email;
    if (e.provider === 'log') { this.log.info?.(`[correo de prueba] para ${to}: ${msg.subject}`); return; }
    let res;
    if (e.provider === 'resend') {
      res = await this.fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: 'Bearer ' + e.apiKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ from: e.from, to: [to], subject: msg.subject, text: msg.text, html: msg.html }), signal: AbortSignal.timeout(15000) });
    } else if (e.provider === 'brevo') {
      const m = /^(.*)<(.+)>$/.exec(e.from) || [null, '', e.from];
      res = await this.fetch('https://api.brevo.com/v3/smtp/email', { method: 'POST', headers: { 'api-key': e.apiKey, 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ sender: { name: m[1].trim() || this.cfg.company.name, email: m[2].trim() }, to: [{ email: to }], subject: msg.subject, textContent: msg.text, htmlContent: msg.html }), signal: AbortSignal.timeout(15000) });
    } else throw new Error('EMAIL_PROVIDER desconocido');
    if (!res.ok) throw new Error('correo HTTP ' + res.status);
  }

  async sendWhatsApp(phone, template, vars) {
    const w = this.cfg.whatsapp; if (!w) throw new Error('WhatsApp no configurado');
    const p = (t) => ({ type: 'text', text: String(t == null ? '-' : t).replace(/\s+/g, ' ').slice(0, 300) || '-' });
    const res = await this.fetch(`https://graph.facebook.com/${w.version}/${encodeURIComponent(w.phoneId)}/messages`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + w.token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to: phone, type: 'template', template: { name: 'slx_' + template, language: { code: w.lang }, components: [{ type: 'body', parameters: T[template].wa.map((k) => p(vars[k])) }] } }),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) { let d = ''; try { d = JSON.stringify((await res.json()).error || {}).slice(0, 160); } catch (_) {} throw new Error('WhatsApp HTTP ' + res.status + ' ' + d); }
  }

  /** Envía los avisos pendientes (lo llama el programador de tareas). */
  async run(limit = 25) {
    if (this.sending) return 0;
    this.sending = true; let n = 0;
    try {
      for (const r of this.db.all("SELECT * FROM notifications WHERE status = 'pendiente' AND next_attempt_at <= ? ORDER BY created_at LIMIT ?", nowIso(), limit)) {
        try {
          const to = this.vault.decrypt(r.to_enc, 'notifications.to:' + r.id);
          const vars = JSON.parse(this.vault.decrypt(r.payload_enc, 'notifications.payload:' + r.id));
          if (r.channel === 'email') await this.sendEmail(to, render(r.template, vars));
          else await this.sendWhatsApp(to, r.template, vars);
          this.db.run("UPDATE notifications SET status = 'enviado', attempts = attempts + 1, sent_at = ?, last_error = NULL WHERE id = ?", nowIso(), r.id); n++;
        } catch (e) {
          const att = r.attempts + 1;
          this.db.run('UPDATE notifications SET attempts = ?, last_error = ?, status = ?, next_attempt_at = ? WHERE id = ?',
            att, String(e.message).slice(0, 200), att >= 6 ? 'fallido' : 'pendiente', nowIso(Date.now() + 2 ** att * 60e3), r.id);
          this.log.error?.('aviso', r.channel, r.id, e.message);
        }
      }
    } finally { this.sending = false; }
    return n;
  }
}

module.exports = { Notifier, render, TEMPLATES: T, money, fecha };
