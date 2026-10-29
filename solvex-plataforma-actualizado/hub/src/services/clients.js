'use strict';
/**
 * Clientes de Solvex (barberías, restaurantes, empresas...). Los datos personales van cifrados;
 * el RUC/DNI, correo y celular tienen índice ciego para buscarlos y evitar duplicados.
 */
const C = require('../lib/crypto');
const T = require('../lib/time');
const v = require('../lib/validate');
const { HttpError } = require('../http/app');

const SCHEMA = {
  kind: v.oneOf(['empresa', 'persona'], { default: 'empresa' }),
  display_name: v.str({ min: 2, max: 120 }),
  legal_name: v.str({ max: 200, optional: true }),
  doc_type: v.oneOf(['RUC', 'DNI', 'CE', 'PAS', 'EXT']),
  doc_number: v.str({ min: 3, max: 15 }),
  country: v.str({ min: 2, max: 2, pattern: /^[A-Za-z]{2}$/, optional: true }),   // residencia fiscal (ISO 3166-1): decide el impuesto
  region: v.str({ max: 60, optional: true }),
  contact_name: v.str({ max: 120, optional: true }),
  email: v.email({ optional: true }),
  phone: v.phone({ optional: true }),
  address: v.str({ max: 250, optional: true }),
  city: v.str({ max: 80, optional: true }),
  notes: v.str({ max: 2000, optional: true, multiline: true }),
  owner_user_id: v.id('usr', { optional: true }),
};
const CHECKS = ['documento', 'ruc_sunat', 'local_redes', 'contrato', 'datos_facturacion'];

class Clients {
  constructor({ db, vault, audit, bus }) { Object.assign(this, { db, vault, audit, bus }); }

  get(id) { return this.db.get('SELECT * FROM clients WHERE id = ? AND deleted_at IS NULL', id); }
  must(id) { const c = this.get(id); if (!c) throw new HttpError(404, 'NO_ENCONTRADO', 'Cliente no encontrado.'); return c; }

  fields(id, d) {
    const enc = (k, val) => this.vault.encrypt(val, `clients.${k}:${id}`);
    return {
      kind: d.kind, display_name: d.display_name, doc_type: d.doc_type, country: d.country, region: d.region || null,
      legal_name_enc: enc('legal_name', d.legal_name), doc_number_enc: enc('doc_number', d.doc_number), doc_bidx: this.vault.bidx('doc', d.doc_type + ':' + d.doc_number),
      doc_hint: d.doc_number.slice(-3), contact_name_enc: enc('contact_name', d.contact_name),
      email_enc: enc('email', d.email), email_bidx: d.email ? this.vault.bidx('email', d.email) : null,
      phone_enc: enc('phone', d.phone), phone_bidx: d.phone ? this.vault.bidx('phone', d.phone) : null,
      address_enc: enc('address', d.address), city: d.city, notes_enc: enc('notes', d.notes), owner_user_id: d.owner_user_id || null,
    };
  }

  parse(body) {
    const d = v.parse(body, SCHEMA);
    d.doc_number = v.docNumber(d.doc_type, d.doc_number);
    d.country = (d.country || 'PE').toUpperCase();
    if (d.doc_type === 'RUC' && d.country !== 'PE') throw new v.ValidationError('country', 'Quien tiene RUC está domiciliado en el Perú: el país debe ser Perú.');
    if (d.doc_type === 'EXT' && d.country === 'PE') throw new v.ValidationError('doc_type', 'Para un cliente del Perú usa RUC, DNI, carné de extranjería o pasaporte.');
    if (d.kind === 'empresa' && d.country === 'PE' && d.doc_type !== 'RUC') throw new v.ValidationError('doc_type', 'Una empresa del Perú se registra con RUC.');
    if (d.kind === 'empresa' && d.country !== 'PE' && d.doc_type !== 'EXT') throw new v.ValidationError('doc_type', 'Una empresa del extranjero se registra con su documento tributario (Tax ID).');
    return d;
  }

  create(body, actor, ip) {
    const d = this.parse(body);
    return this.db.tx(() => {
      if (this.db.get('SELECT 1 FROM clients WHERE doc_bidx = ? AND deleted_at IS NULL', this.vault.bidx('doc', d.doc_type + ':' + d.doc_number))) throw new HttpError(409, 'DUPLICADO', 'Ya existe un cliente con ese documento.');
      const id = C.newId('cli'), now = T.nowIso(), code = 'CLI-' + String(this.db.nextSeq('client')).padStart(4, '0');
      const f = this.fields(id, d);
      this.db.run(`INSERT INTO clients (id,code,kind,display_name,legal_name_enc,doc_type,doc_number_enc,doc_bidx,doc_hint,country,region,contact_name_enc,email_enc,email_bidx,phone_enc,phone_bidx,address_enc,city,notes_enc,owner_user_id,created_at,updated_at)
        VALUES (@id,@code,@kind,@display_name,@legal_name_enc,@doc_type,@doc_number_enc,@doc_bidx,@doc_hint,@country,@region,@contact_name_enc,@email_enc,@email_bidx,@phone_enc,@phone_bidx,@address_enc,@city,@notes_enc,@owner_user_id,@now,@now)`, Object.assign({ id, code, now }, f));
      this.audit.log({ actor, action: 'cliente.creado', entity: ['client', id], ip, data: { code, display_name: d.display_name, doc_type: d.doc_type, country: d.country } });
      this.bus.emit('admin', { type: 'client', id });
      return this.get(id);
    });
  }

  update(id, body, version, actor, ip) {
    const d = this.parse(body);
    return this.db.tx(() => {
      const c = this.must(id);
      if (c.anonymized_at) throw new HttpError(409, 'ANONIMIZADO', 'El cliente fue anonimizado.');
      if (version != null && c.version !== version) throw new HttpError(409, 'VERSION', 'Otra persona modificó este cliente. Recarga para ver los cambios.');
      const f = this.fields(id, d);
      const dup = this.db.get('SELECT id FROM clients WHERE doc_bidx = ? AND deleted_at IS NULL AND id <> ?', f.doc_bidx, id);
      if (dup) throw new HttpError(409, 'DUPLICADO', 'Ya existe otro cliente con ese documento.');
      // qué campos cambiaron (solo nombres, nunca valores personales en la auditoría)
      const changed = Object.keys(SCHEMA).filter((k) => {
        const map = { legal_name: 'legal_name_enc', doc_number: 'doc_bidx', contact_name: 'contact_name_enc', email: 'email_bidx', phone: 'phone_bidx', address: 'address_enc', notes: 'notes_enc' };
        if (['legal_name', 'contact_name', 'address', 'notes'].includes(k)) return (c[map[k]] ? this.vault.decrypt(c[map[k]], `clients.${k}:${id}`) : '') !== (d[k] || '');
        if (map[k]) return (c[map[k]] || null) !== (f[map[k]] || null);
        return (c[k] ?? null) !== (d[k] ?? null);
      });
      this.db.run(`UPDATE clients SET kind=@kind, display_name=@display_name, legal_name_enc=@legal_name_enc, doc_type=@doc_type, doc_number_enc=@doc_number_enc, doc_bidx=@doc_bidx, doc_hint=@doc_hint, country=@country, region=@region,
        contact_name_enc=@contact_name_enc, email_enc=@email_enc, email_bidx=@email_bidx, phone_enc=@phone_enc, phone_bidx=@phone_bidx, address_enc=@address_enc, city=@city, notes_enc=@notes_enc,
        owner_user_id=@owner_user_id, version = version + 1, updated_at=@now WHERE id=@id`, Object.assign({ id, now: T.nowIso() }, f));
      // Cambiar el documento invalida la verificación: hay que volver a revisarlo.
      if (changed.includes('doc_number') || changed.includes('doc_type')) this.db.run("UPDATE clients SET verification = 'pendiente' WHERE id = ?", id);
      this.audit.log({ actor, action: 'cliente.editado', entity: ['client', id], ip, data: { campos: changed } });
      this.bus.emit('admin', { type: 'client', id });
      return this.get(id);
    });
  }

  verify(id, { verification, checklist, note }, actor, ip) {
    if (!['pendiente', 'verificado', 'observado', 'rechazado'].includes(verification)) throw new HttpError(400, 'ESTADO', 'Estado no válido.');
    const ck = {}; for (const k of CHECKS) ck[k] = !!(checklist && checklist[k]);
    if (verification === 'verificado' && !CHECKS.slice(0, 2).every((k) => ck[k])) throw new HttpError(400, 'CHECKLIST', 'Para verificar, revisa al menos el documento y el RUC en SUNAT.');
    return this.db.tx(() => {
      const c = this.must(id);
      this.db.run('UPDATE clients SET verification = ?, checklist = ?, version = version + 1, updated_at = ? WHERE id = ?', verification, JSON.stringify(ck), T.nowIso(), id);
      this.audit.log({ actor, action: 'cliente.verificacion', entity: ['client', id], ip, data: { de: c.verification, a: verification, checklist: ck, note: note || undefined } });
      return this.get(id);
    });
  }

  addContact(id, { channel, note }, actor, ip) {
    const c = this.must(id);
    const cid = C.newId('cct');
    this.db.run('INSERT INTO client_contacts (id,client_id,channel,note_enc,user_id,created_at) VALUES (?,?,?,?,?,?)', cid, c.id, channel, this.vault.encrypt(note, 'client_contacts.note:' + cid), actor.id || null, T.nowIso());
    this.audit.log({ actor, action: 'cliente.contacto', entity: ['client', id], ip, data: { channel } });
  }

  contacts(id) {
    return this.db.all('SELECT cc.*, u.name AS user_name FROM client_contacts cc LEFT JOIN users u ON u.id = cc.user_id WHERE client_id = ? ORDER BY cc.created_at DESC LIMIT 100', id)
      .map((r) => ({ id: r.id, channel: r.channel, note: this.vault.decrypt(r.note_enc, 'client_contacts.note:' + r.id), user: r.user_name, created_at: r.created_at }));
  }

  /** Búsqueda: por nombre o código; si parece documento, correo o celular, búsqueda exacta por índice ciego. */
  search({ q = '', verification = '', limit = 50, offset = 0 }) {
    const where = ['deleted_at IS NULL']; const p = [];
    const s = String(q || '').trim();
    if (s) {
      const digits = s.replace(/\D/g, '');
      if (/^\d{8}$|^\d{11}$/.test(s)) { where.push('(doc_bidx = ? OR doc_bidx = ?)'); p.push(this.vault.bidx('doc', 'DNI:' + s), this.vault.bidx('doc', 'RUC:' + s)); }
      else if (s.includes('@')) { where.push('email_bidx = ?'); p.push(this.vault.bidx('email', s.toLowerCase())); }
      else if (/^9\d{8}$/.test(digits) && digits.length === s.replace(/\s/g, '').length) { where.push('phone_bidx = ?'); p.push(this.vault.bidx('phone', '51' + digits)); }
      else { where.push("(display_name LIKE ? ESCAPE '\\' OR code LIKE ? ESCAPE '\\' OR city LIKE ? ESCAPE '\\')"); const like = '%' + s.replace(/[\\%_]/g, (m) => '\\' + m) + '%'; p.push(like, like, like); }
    }
    if (verification) { where.push('verification = ?'); p.push(verification); }
    const w = where.join(' AND ');
    const total = this.db.get(`SELECT COUNT(*) n FROM clients WHERE ${w}`, ...p).n;
    const rows = this.db.all(`SELECT * FROM clients WHERE ${w} ORDER BY created_at DESC LIMIT ? OFFSET ?`, ...p, Math.min(200, limit), offset);
    return { total, rows };
  }

  /** Derecho de acceso (ARCO): todo lo que Solvex tiene de este cliente, en JSON. */
  exportData(id, views) {
    const c = this.must(id);
    return {
      exported_at: T.nowIso(), client: views.client(c, { full: true }), contacts: this.contacts(id),
      licenses: this.db.all('SELECT * FROM licenses WHERE client_id = ?', id).map((l) => views.license(l)),
      invoices: this.db.all('SELECT * FROM invoices WHERE client_id = ?', id).map((i) => views.invoice(i)),
      payments: this.db.all('SELECT * FROM payments WHERE client_id = ?', id).map((p) => views.payment(p)),
    };
  }

  /**
   * Derecho de cancelación / supresión: borra los datos personales y conserva los registros
   * contables (montos, fechas) que la ley obliga a guardar. No se permite con licencias vivas.
   */
  anonymize(id, actor, ip) {
    return this.db.tx(() => {
      const c = this.must(id);
      if (this.db.get("SELECT 1 FROM licenses WHERE client_id = ? AND status NOT IN ('cancelada')", id)) throw new HttpError(409, 'LICENCIAS_VIVAS', 'Primero cancela todas sus licencias.');
      this.db.run(`UPDATE clients SET display_name = ?, legal_name_enc = NULL, doc_number_enc = ?, doc_bidx = ?, doc_hint = NULL, contact_name_enc = NULL, email_enc = NULL, email_bidx = NULL,
        phone_enc = NULL, phone_bidx = NULL, address_enc = NULL, notes_enc = NULL, anonymized_at = ?, deleted_at = ?, updated_at = ?, version = version + 1 WHERE id = ?`,
      'Cliente anonimizado ' + c.code, this.vault.encrypt('-', 'clients.doc_number:' + id), 'anon:' + id, T.nowIso(), T.nowIso(), T.nowIso(), id);
      this.db.run('DELETE FROM client_contacts WHERE client_id = ?', id);
      this.db.run('UPDATE payments SET payer_email_enc = NULL WHERE client_id = ?', id);
      for (const n of this.db.all('SELECT id FROM notifications WHERE client_id = ?', id)) {
        this.db.run('UPDATE notifications SET to_enc = ?, to_hint = NULL, payload_enc = ? WHERE id = ?', this.vault.encrypt('-', 'notifications.to:' + n.id), this.vault.encrypt('{}', 'notifications.payload:' + n.id), n.id);
      }
      this.audit.log({ actor, action: 'cliente.anonimizado', entity: ['client', id], ip, data: { code: c.code } });
      return true;
    });
  }
}

module.exports = { Clients, CHECKS };
