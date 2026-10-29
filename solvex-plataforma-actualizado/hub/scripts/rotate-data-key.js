'use strict';
/**
 * Rotación de la llave de datos. Pasos:
 *   1. Agrega una llave nueva a DATA_KEYS (ej. DATA_KEYS=k1:...,k2:...) y pon DATA_KEY_ACTIVE=k2.
 *   2. Reinicia el Hub (lo nuevo ya se cifra con k2; lo viejo se sigue leyendo con k1).
 *   3. npm run rotar-llave-datos   → vuelve a cifrar todo con k2.
 *   4. Cuando termine sin errores, quita k1 de DATA_KEYS y reinicia.
 */
const { boot } = require('./_boot');
const hub = boot();
const { db, vault } = hub;
const MAP = [
  ['users', [['totp_secret_enc', 'users.totp']]],
  ['clients', ['legal_name', 'doc_number', 'contact_name', 'email', 'phone', 'address', 'notes'].map((c) => [c + '_enc', 'clients.' + c])],
  ['client_contacts', [['note_enc', 'client_contacts.note']]],
  ['instances', [['webhook_secret_enc', 'instances.webhook_secret']]],
  ['invoices', [['pay_token_enc', 'invoices.pay_token']]],
  ['payments', [['payer_email_enc', 'payments.payer_email']]],
  ['notifications', [['to_enc', 'notifications.to'], ['payload_enc', 'notifications.payload']]],
  ['leads', [['name_enc', 'leads.name'], ['contact_enc', 'leads.contact'], ['message_enc', 'leads.message']]],
  ['ticket_notes', [['body_enc', 'ticket_notes.body']]],
  ['complaints', [['consumer_enc', 'complaints.consumer'], ['description_enc', 'complaints.description'], ['request_enc', 'complaints.request'], ['response_enc', 'complaints.response']]],
];
let n = 0, errors = 0;
for (const [table, cols] of MAP) {
  for (const row of db.all(`SELECT * FROM ${table}`)) {
    const set = {};
    for (const [col, aad] of cols) {
      const val = row[col];
      if (!val || vault.keyIdOf(val) === vault.active) continue;
      try { set[col] = vault.encrypt(vault.decrypt(val, aad + ':' + row.id), aad + ':' + row.id); } catch (e) { errors++; console.error(`No se pudo re-cifrar ${table}.${col} ${row.id}: ${e.message}`); }
    }
    const keys = Object.keys(set);
    if (keys.length) { db.run(`UPDATE ${table} SET ${keys.map((k) => k + ' = ?').join(', ')} WHERE id = ?`, ...keys.map((k) => set[k]), row.id); n += keys.length; }
  }
}
hub.audit.log({ actor: { type: 'sistema', label: 'rotación de llave' }, action: 'datos.llave_rotada', data: { valores: n, errores: errors, activa: vault.active } });
console.log(`Re-cifrados ${n} valores con la llave ${vault.active}. Errores: ${errors}.`);
hub.shutdown();
