'use strict';
/**
 * Tiempo real.
 *  1) Hacia el panel: bus en memoria + Server-Sent Events (el panel se actualiza solo).
 *  2) Hacia cada producto (barbería, restaurante...): "outbox" + webhooks firmados con reintentos.
 *
 * Patrón outbox: el evento se guarda en la MISMA transacción que el cambio de la licencia, así nunca
 * hay un cambio sin aviso ni un aviso sin cambio. Después un despachador lo entrega.
 *
 * Cada webhook lleva el token de licencia firmado con Ed25519 y además se firma el cuerpo con
 * HMAC-SHA256 (secreto por instancia) + marca de tiempo (anti-repetición). Doble cerradura: aunque
 * se filtrara el secreto HMAC, nadie puede fabricar un token de licencia válido.
 */
const { EventEmitter } = require('node:events');
const crypto = require('node:crypto');
const C = require('../lib/crypto');
const { nowIso } = require('../lib/time');

// Reintentos: 30 s, 1, 2, 5, 10, 20, 30 min, 1, 2, 4, 8, 12 h (≈ 28 h en total)
const BACKOFF_SEC = [30, 60, 120, 300, 600, 1200, 1800, 3600, 7200, 14400, 28800, 43200];

class Bus extends EventEmitter {}

class Outbox {
  constructor({ db, vault, bus, log = console, fetchImpl = globalThis.fetch, allowPrivateWebhooks = false }) {
    this.db = db; this.vault = vault; this.bus = bus; this.log = log; this.fetch = fetchImpl;
    this.tokenFor = null; // lo inyecta el servicio de licencias
    this.running = false; this.allowPrivate = allowPrivateWebhooks;
  }

  /** Registra un cambio de licencia y programa su entrega a la instancia (dentro de la transacción del cambio). */
  licenseChanged(lic, reason, override = null) {
    const id = C.newId('evt'), now = nowIso();
    this.db.run('INSERT INTO outbox (id,topic,license_id,instance_id,payload,created_at) VALUES (?,?,?,?,?,?)',
      id, 'license.updated', lic.id, lic.instance_id, JSON.stringify({ reason, override }), now);
    if (lic.instance_id) {
      const inst = this.db.get('SELECT id, status, webhook_url FROM instances WHERE id = ?', lic.instance_id);
      if (inst && inst.status === 'activa' && inst.webhook_url) {
        // Las entregas anteriores aún pendientes de esta licencia quedan reemplazadas: el token nuevo ya trae el estado final.
        this.db.run(`UPDATE deliveries SET status = 'descartado', last_error = 'reemplazado por un evento más reciente'
          WHERE status = 'pendiente' AND instance_id = ? AND event_id IN (SELECT id FROM outbox WHERE license_id = ?)`, inst.id, lic.id);
        this.db.run("INSERT INTO deliveries (event_id,instance_id,status,next_attempt_at,created_at) VALUES (?,?,'pendiente',?,?)", id, inst.id, now, now);
      }
    }
    this.bus.emit('admin', { type: 'license', id: lic.id, reason });
    this.kick();
    return id;
  }

  /** Evento de prueba ("ping") para verificar la integración de una instancia. */
  ping(instance) {
    const id = C.newId('evt'), now = nowIso();
    this.db.tx(() => {
      this.db.run('INSERT INTO outbox (id,topic,license_id,instance_id,payload,created_at) VALUES (?,?,?,?,?,?)', id, 'ping', null, instance.id, '{}', now);
      this.db.run("INSERT INTO deliveries (event_id,instance_id,status,next_attempt_at,created_at) VALUES (?,?,'pendiente',?,?)", id, instance.id, now, now);
    });
    this.kick();
    return id;
  }

  kick() { if (this._kick || this.closed) return; this._kick = setImmediate(() => { this._kick = null; this.run().catch((e) => this.log.error('outbox', e.message)); }); }

  static sign(secret, ts, body) { return 'v1=' + crypto.createHmac('sha256', secret).update(ts + '.' + body).digest('hex'); }

  async deliverOne(d) {
    const inst = this.db.get('SELECT * FROM instances WHERE id = ?', d.instance_id);
    const ev = this.db.get('SELECT * FROM outbox WHERE id = ?', d.event_id);
    if (!inst || inst.status !== 'activa' || !inst.webhook_url || !ev) {
      this.db.run("UPDATE deliveries SET status = 'descartado', last_error = 'instancia inactiva o sin URL' WHERE id = ?", d.id); return;
    }
    let data = {};
    if (ev.topic === 'license.updated') {
      let lic = this.db.get('SELECT * FROM licenses WHERE id = ?', ev.license_id);
      const ov = JSON.parse(ev.payload || '{}').override;
      // override: la licencia se movió a otra instancia; a la anterior se le avisa (con token firmado) que ese negocio ya no está habilitado.
      if (lic && ov) lic = Object.assign({}, lic, ov);
      if (!lic || lic.instance_id !== inst.id) { this.db.run("UPDATE deliveries SET status = 'descartado', last_error = 'la licencia ya no pertenece a esta instancia' WHERE id = ?", d.id); return; }
      data = { license_code: lic.code, tenant_ref: lic.tenant_ref, token: this.tokenFor(lic, inst) };
    }
    const body = JSON.stringify({ id: ev.id, type: ev.topic, created_at: ev.created_at, sent_at: nowIso(), data });
    const ts = String(Math.floor(Date.now() / 1000));
    const secret = this.vault.decrypt(inst.webhook_secret_enc, 'instances.webhook_secret:' + inst.id);
    let status = 0, err = null;
    try {
      const u = new URL(inst.webhook_url);
      if (!this.allowPrivate && !require('../http/security').isPublicHost(u.hostname)) throw new Error('URL de webhook no permitida (red privada)');
      const res = await this.fetch(inst.webhook_url, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10_000),
        headers: { 'Content-Type': 'application/json', 'User-Agent': 'SolvexHub/3', 'Solvex-Event-Id': ev.id, 'Solvex-Timestamp': ts, 'Solvex-Signature': Outbox.sign(secret, ts, body) },
        body,
      });
      status = res.status;
      if (res.status < 200 || res.status >= 300) err = 'HTTP ' + res.status;
    } catch (e) { err = String(e.message || e).slice(0, 200); }
    if (!err) {
      this.db.run("UPDATE deliveries SET status = 'entregado', attempts = attempts + 1, last_status = ?, last_error = NULL, delivered_at = ? WHERE id = ?", status, nowIso(), d.id);
      return true;
    }
    const att = d.attempts + 1, dead = att > BACKOFF_SEC.length;
    this.db.run('UPDATE deliveries SET status = ?, attempts = ?, last_status = ?, last_error = ?, next_attempt_at = ? WHERE id = ?',
      dead ? 'fallido' : 'pendiente', att, status || null, err, nowIso(Date.now() + (BACKOFF_SEC[att - 1] || 0) * 1000), d.id);
    if (att === 3 || dead) this.bus.emit('admin', { type: 'delivery_failed', instance: inst.id, attempts: att });
    return false;
  }

  async run(limit = 30) {
    if (this.running || this.closed) return 0;
    this.running = true; let n = 0;
    try {
      const due = this.db.all("SELECT * FROM deliveries WHERE status = 'pendiente' AND next_attempt_at <= ? ORDER BY id LIMIT ?", nowIso(), limit);
      for (const d of due) { if (await this.deliverOne(d)) n++; }
    } finally { this.running = false; }
    return n;
  }

  retry(deliveryId) {
    return this.db.run("UPDATE deliveries SET status = 'pendiente', next_attempt_at = ?, attempts = 0 WHERE id = ? AND status IN ('fallido','pendiente')", nowIso(), deliveryId).changes;
  }
}

module.exports = { Bus, Outbox, BACKOFF_SEC };
