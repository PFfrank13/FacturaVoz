'use strict';
/**
 * Bitácora de auditoría encadenada.
 *
 * Cada registro guarda el hash del anterior y su propio hash = HMAC(AUDIT_KEY, anterior + contenido).
 *  - La base impide UPDATE y DELETE (triggers).
 *  - Si alguien con acceso al archivo intenta editar o borrar un registro "por fuera", la cadena se
 *    rompe y la verificación (panel > Auditoría > Verificar, o npm run verificar-auditoria) lo detecta.
 *  - Sin AUDIT_KEY no se puede recalcular la cadena, así que tampoco se puede "rehacer" entera.
 *
 * Regla: aquí nunca se guardan contraseñas, claves, tokens ni datos personales en claro;
 * solo qué cambió (nombres de campos) y valores no sensibles.
 */
const crypto = require('node:crypto');
const { nowIso } = require('../lib/time');

const GENESIS = '0'.repeat(64);

class Audit {
  constructor(db, key, bus) { this.db = db; this.key = key; this.bus = bus; }

  hashOf(prev, r) {
    const body = JSON.stringify([r.at, r.actor_type, r.actor_id, r.actor_label, r.action, r.entity_type, r.entity_id, r.ip, r.data]);
    return crypto.createHmac('sha256', this.key).update(prev + '|' + body).digest('hex');
  }

  /**
   * @param {object} a { actor:{type,id,label}, action, entity:[type,id], ip, data }
   */
  log(a) {
    const actor = a.actor || { type: 'sistema', id: null, label: 'Sistema' };
    const r = {
      at: nowIso(), actor_type: actor.type, actor_id: actor.id || null, actor_label: String(actor.label || '').slice(0, 120),
      action: String(a.action).slice(0, 80),
      entity_type: a.entity ? a.entity[0] : null, entity_id: a.entity ? a.entity[1] : null,
      ip: a.ip || null, data: a.data == null ? null : JSON.stringify(a.data).slice(0, 4000),
    };
    return this.db.tx(() => {
      const last = this.db.get('SELECT hash FROM audit_log ORDER BY seq DESC LIMIT 1');
      const prev = last ? last.hash : GENESIS;
      const hash = this.hashOf(prev, r);
      this.db.run(`INSERT INTO audit_log (at,actor_type,actor_id,actor_label,action,entity_type,entity_id,ip,data,prev_hash,hash)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)`, r.at, r.actor_type, r.actor_id, r.actor_label, r.action, r.entity_type, r.entity_id, r.ip, r.data, prev, hash);
      if (this.bus) this.bus.emit('admin', { type: 'audit', action: r.action, entity: a.entity || null });
      return hash;
    });
  }

  /** Recorre toda la cadena. Devuelve { ok, count, brokenAt, head }. */
  verify() {
    let prev = GENESIS, count = 0;
    const it = this.db.raw.prepare('SELECT * FROM audit_log ORDER BY seq ASC').iterate();
    let expectedSeq = null;
    for (const r of it) {
      if (expectedSeq !== null && r.seq !== expectedSeq) return { ok: false, count, brokenAt: expectedSeq, reason: 'falta un registro (hueco en la secuencia)' };
      if (r.prev_hash !== prev) return { ok: false, count, brokenAt: r.seq, reason: 'el enlace con el registro anterior no coincide' };
      const h = this.hashOf(prev, r);
      if (h !== r.hash) return { ok: false, count, brokenAt: r.seq, reason: 'el contenido del registro fue alterado' };
      prev = r.hash; count++; expectedSeq = r.seq + 1;
    }
    const maxSeq = this.db.get("SELECT seq FROM sqlite_sequence WHERE name = 'audit_log'");
    if (maxSeq && expectedSeq !== null && maxSeq.seq !== expectedSeq - 1) return { ok: false, count, brokenAt: expectedSeq, reason: 'se borraron los últimos registros' };
    return { ok: true, count, head: prev };
  }
}

/** Actor para los registros a partir de la petición. */
const actorOf = (ctx) => (ctx && ctx.state.user ? { type: 'usuario', id: ctx.state.user.id, label: ctx.state.user.name } : { type: 'sistema', id: null, label: 'Sistema' });

module.exports = { Audit, actorOf, GENESIS };
