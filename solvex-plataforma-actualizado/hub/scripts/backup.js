'use strict';
/**
 * Respaldo cifrado de la base (AES-256-GCM con BACKUP_KEY). No detiene el servidor.
 *   npm run respaldo                 → backups/hub-AAAAMMDD-HHMMSS.db.enc (guarda los 30 más recientes)
 * Programa este comando cada día (cron) y copia la carpeta backups/ FUERA del servidor
 * (otro proveedor, por ejemplo Cloudflare R2 o Backblaze B2). Para restaurar hacen falta
 * BACKUP_KEY (para abrir el archivo) y DATA_KEYS (para leer los datos personales).
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { boot } = require('./_boot');
const C = require('../src/lib/crypto');

const hub = boot();
if (!hub.config.backupKey) { console.error('Falta BACKUP_KEY en .env'); process.exit(1); }
const dir = path.resolve(process.env.BACKUP_DIR || './backups');
fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
const tmp = path.join(dir, `.tmp-${process.pid}.db`);
const audit = hub.audit.verify();
if (!audit.ok) console.warn('AVISO: la bitácora de auditoría NO está íntegra (registro ' + audit.brokenAt + '). Se respalda igual; revisa de inmediato.');
hub.db.snapshotTo(tmp);
const plain = fs.readFileSync(tmp); fs.unlinkSync(tmp);
const enc = C.encryptBuffer(hub.config.backupKey, plain);
const out = path.join(dir, `hub-${stamp}.db.enc`);
fs.writeFileSync(out, enc, { mode: 0o600 });
const sha = crypto.createHash('sha256').update(enc).digest('hex');
hub.db.run("INSERT INTO settings (key,value,updated_at) VALUES ('last_backup', ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at", JSON.stringify({ file: path.basename(out), at: new Date().toISOString(), sha256: sha, audit_head: audit.head || null }), new Date().toISOString());
hub.audit.log({ actor: { type: 'sistema', label: 'respaldo' }, action: 'respaldo.creado', data: { file: path.basename(out), sha256: sha.slice(0, 16), bytes: enc.length } });
const keep = Number(process.env.BACKUP_KEEP || 30);
const files = fs.readdirSync(dir).filter((f) => /^hub-\d{8}-\d{6}\.db\.enc$/.test(f)).sort();
for (const f of files.slice(0, Math.max(0, files.length - keep))) fs.unlinkSync(path.join(dir, f));
console.log(`Respaldo cifrado: ${out}\nSHA-256: ${sha}\nAuditoría: ${audit.ok ? 'íntegra' : 'ROTA'} (${audit.count} registros${audit.head ? ', cabeza ' + audit.head.slice(0, 16) : ''})`);
hub.shutdown();
