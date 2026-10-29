'use strict';
/**
 * Tareas automáticas (cada minuto):
 *  1. Cortes y reactivaciones por fecha (sweep).
 *  2. Cobros de renovación N días antes del vencimiento.
 *  3. Recordatorios de vencimiento (7, 3 y 1 día antes, configurable).
 *  4. Entrega de webhooks pendientes a los productos.
 *  5. Envío de avisos por correo/WhatsApp.
 *  6. Limpieza de sesiones vencidas.
 *  7. Envío de comprobantes electrónicos (boletas, facturas, notas de crédito) y consulta de su estado en SUNAT.
 *  8. Cada hora: conciliación con la pasarela (detecta reembolsos y contracargos).
 *
 * Un candado en la base evita que dos procesos ejecuten lo mismo a la vez.
 * Aunque el programador se detenga, las licencias se siguen respondiendo bien porque el estado se
 * calcula en cada consulta; el programador solo adelanta avisos y registros.
 */
const crypto = require('node:crypto');
const T = require('../lib/time');
const { money, fecha } = require('./notify');

class Scheduler {
  constructor({ db, licenses, billing, outbox, notifier, settings, gateway, audit, einvoice = null, log = console }) {
    Object.assign(this, { db, licenses, billing, outbox, notifier, settings, gateway, audit, einvoice, log });
    this.owner = process.pid + '-' + crypto.randomBytes(4).toString('hex');
    this.lastReconcile = 0; this.timer = null; this.running = false;
  }

  lock(ms) {
    const now = T.nowIso(), exp = T.nowIso(Date.now() + ms);
    this.db.run('INSERT INTO locks (name, owner, expires_at) VALUES (?,?,?) ON CONFLICT(name) DO UPDATE SET owner = excluded.owner, expires_at = excluded.expires_at WHERE locks.expires_at < ? OR locks.owner = ?', 'scheduler', this.owner, exp, now, this.owner);
    return this.db.get("SELECT owner FROM locks WHERE name = 'scheduler'").owner === this.owner;
  }

  renewals(now = Date.now()) {
    const days = Number(this.settings.get('renewal_notice_days')) || 10;
    const limit = T.nowIso(now + days * 864e5);
    const rows = this.db.all(`SELECT l.* FROM licenses l WHERE l.activated_at IS NOT NULL AND l.status IN ('prueba','activa','gracia','suspendida')
      AND l.auto_invoice = 1 AND l.billing_provider = 'hub' AND l.interval_unit <> 'none' AND l.price_cents > 0 AND l.period_end IS NOT NULL AND l.period_end <= ?
      AND NOT EXISTS (SELECT 1 FROM invoices i WHERE i.license_id = l.id AND i.status IN ('pendiente','parcial'))
      AND NOT EXISTS (SELECT 1 FROM invoices i WHERE i.license_id = l.id AND i.kind = 'renovacion' AND i.for_period_end = l.period_end)`, limit);
    let n = 0;
    for (const l of rows) { try { if (this.billing.createRenewal(l)) n++; } catch (e) { this.log.error('renovación', l.code, e.message); } }
    return n;
  }

  reminders(now = Date.now()) {
    const list = (this.settings.get('reminders_days') || []).map(Number).filter((d) => d > 0 && d <= 60);
    if (!list.length) return 0;
    const max = Math.max(...list);
    const rows = this.db.all(`SELECT * FROM licenses WHERE status IN ('prueba','activa') AND period_end IS NOT NULL AND period_end > ? AND period_end <= ? AND auto_invoice = 1 AND billing_provider = 'hub'`, T.nowIso(now), T.nowIso(now + (max + 1) * 864e5));
    let n = 0;
    for (const l of rows) {
      const left = T.diffDays(T.localDate(now, l.timezone), T.localDate(l.period_end, l.timezone));
      if (!list.includes(left)) continue;
      const inv = this.billing.openInvoiceForLicense(l, { create: false });
      if (!inv) continue;
      const client = this.db.get('SELECT * FROM clients WHERE id = ?', l.client_id);
      if (!client || client.anonymized_at) continue;
      const product = this.db.get('SELECT name FROM products WHERE id = ?', l.product_id);
      n += this.notifier.queue({
        template: 'recordatorio', client, license: l, dedupe: `recordatorio:${l.id}:${l.period_end}:${left}`,
        vars: { servicio: `${product.name} (${l.label})`, fecha: fecha(l.period_end, l.timezone), monto: money(this.billing.remaining(inv), inv.currency), enlace: this.billing.payUrl(inv) },
      }).length;
    }
    return n;
  }

  /** Conciliación: revisa los cargos de Culqi aprobados en los últimos 30 días; si hubo reembolso, lo revierte. */
  async reconcile() {
    if (!this.gateway) return 0;
    const since = T.nowIso(Date.now() - 30 * 864e5);
    let fixed = 0;
    for (const p of this.db.all("SELECT * FROM payments WHERE method = 'culqi' AND status = 'aprobado' AND created_at > ?", since)) {
      try {
        const c = await this.gateway.getCharge(p.operation_ref);
        if (c.refunded) { this.billing.reversePayment(p.id, { reason: 'Reembolso detectado en la pasarela', kind: 'reembolsado' }, { type: 'pasarela', label: 'Conciliación' }); fixed++; }
      } catch (e) { this.log.error('conciliación', p.id, e.message); }
    }
    return fixed;
  }

  async tick(now = Date.now()) {
    if (this.running) return null;
    this.running = true;
    const out = {};
    try {
      if (!this.lock(5 * 60e3)) return null;
      out.sweep = this.licenses.sweep(now);
      out.renewals = this.renewals(now);
      out.reminders = this.reminders(now);
      out.webhooks = await this.outbox.run();
      out.notifications = await this.notifier.run();
      if (this.einvoice) out.einvoices = await this.einvoice.run(now);
      this.db.run('DELETE FROM sessions WHERE expires_at < ? OR revoked_at < ?', T.nowIso(now - 864e5), T.nowIso(now - 864e5));
      if (now - this.lastReconcile > 3600e3) { this.lastReconcile = now; out.reconciled = await this.reconcile(); }
      return out;
    } catch (e) { this.log.error('programador', e.stack || e.message); return out; } finally { this.running = false; }
  }

  start(intervalMs = 60e3) {
    const run = () => this.tick().catch((e) => this.log.error('programador', e.message));
    setTimeout(run, 2000).unref();
    this.timer = setInterval(run, intervalMs); this.timer.unref();
  }
  stop() { if (this.timer) clearInterval(this.timer); this.db.run("DELETE FROM locks WHERE name = 'scheduler' AND owner = ?", this.owner); }
}

module.exports = { Scheduler };
