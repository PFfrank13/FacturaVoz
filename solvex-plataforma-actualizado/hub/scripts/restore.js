'use strict';
/**
 * Restaura un respaldo cifrado en un archivo NUEVO (nunca encima de la base en uso).
 *   npm run restaurar -- backups/hub-20261019-030000.db.enc data/restaurado.db
 * Luego detén el Hub, cambia DB_PATH (o reemplaza el archivo) y vuelve a iniciarlo.
 */
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const { loadDotEnv } = require('../src/config');
const C = require('../src/lib/crypto');

process.chdir(path.join(__dirname, '..'));
loadDotEnv(path.resolve('.env'));
const [src, dst] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
if (!src || !dst) { console.log('Uso: npm run restaurar -- <respaldo.db.enc> <destino.db>'); process.exit(1); }
if (fs.existsSync(dst)) { console.error('El destino ya existe. Elige un archivo nuevo.'); process.exit(1); }
const key = Buffer.from(process.env.BACKUP_KEY || '', 'base64');
if (key.length !== 32) { console.error('Falta BACKUP_KEY válida en .env'); process.exit(1); }
let plain;
try { plain = C.decryptBuffer(key, fs.readFileSync(src)); } catch (e) { console.error('No se pudo descifrar: llave incorrecta o archivo alterado.'); process.exit(1); }
fs.writeFileSync(dst, plain, { mode: 0o600 });
const db = new DatabaseSync(dst);
const ok = db.prepare('PRAGMA integrity_check').get();
console.log('Restaurado en', dst, '· integridad:', Object.values(ok)[0]);
db.close();
