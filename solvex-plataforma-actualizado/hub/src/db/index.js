'use strict';
/**
 * Base de datos SQLite (módulo node:sqlite incluido en Node 22+; no hay que instalar nada).
 *
 * Por qué SQLite: un solo archivo, sin servidor aparte, transacciones ACID y respaldos simples.
 * Para cientos de clientes y miles de pagos sobra. Si algún día hiciera falta, el acceso a datos
 * está concentrado en este módulo y en los servicios, lo que facilita pasar a PostgreSQL.
 */
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const migrations = require('./migrations');

class Db {
  constructor(file) {
    if (file !== ':memory:') fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true, mode: 0o700 });
    this.file = file;
    this.raw = new DatabaseSync(file);
    this.raw.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;      -- datos financieros: preferimos durabilidad a velocidad
      PRAGMA foreign_keys = ON;
      PRAGMA busy_timeout = 5000;
      PRAGMA secure_delete = ON;      -- lo borrado se sobrescribe con ceros en el archivo
      PRAGMA trusted_schema = OFF;
    `);
    if (file !== ':memory:') { try { fs.chmodSync(file, 0o600); } catch (_) { /* Windows */ } }
    this.cache = new Map();
    this.depth = 0;
    this.migrate();
  }

  stmt(sql) {
    let s = this.cache.get(sql);
    if (!s) { s = this.raw.prepare(sql); this.cache.set(sql, s); }
    return s;
  }
  get(sql, ...p) { return this.stmt(sql).get(...p); }
  all(sql, ...p) { return this.stmt(sql).all(...p); }
  run(sql, ...p) { return this.stmt(sql).run(...p); }
  exec(sql) { this.raw.exec(sql); }

  /** Transacción. Anidable (usa SAVEPOINT). Si fn lanza un error, se deshace todo. */
  tx(fn) {
    const sp = 'sp' + this.depth;
    if (this.depth === 0) this.raw.exec('BEGIN IMMEDIATE'); else this.raw.exec('SAVEPOINT ' + sp);
    this.depth++;
    try {
      const r = fn();
      if (r && typeof r.then === 'function') throw new Error('tx() no admite funciones asíncronas');
      this.depth--;
      if (this.depth === 0) this.raw.exec('COMMIT'); else this.raw.exec('RELEASE ' + sp);
      return r;
    } catch (e) {
      this.depth--;
      if (this.depth === 0) this.raw.exec('ROLLBACK'); else this.raw.exec('ROLLBACK TO ' + sp + '; RELEASE ' + sp);
      throw e;
    }
  }

  /**
   * Aplica las migraciones pendientes. Algunas reconstruyen tablas (SQLite no permite cambiar un CHECK):
   * por eso las llaves foráneas se desactivan durante la migración y, antes de confirmar, se verifica que
   * no quedó ninguna referencia rota (procedimiento recomendado por SQLite). Si algo falla, no cambia nada.
   */
  migrate() {
    const cur = this.raw.prepare('PRAGMA user_version').get().user_version;
    if (cur >= migrations.length) return;
    this.raw.exec('PRAGMA foreign_keys = OFF');
    try {
      for (let v = cur; v < migrations.length; v++) {
        this.raw.exec('BEGIN IMMEDIATE');
        try {
          this.raw.exec(migrations[v]);
          const broken = this.raw.prepare('PRAGMA foreign_key_check').all();
          if (broken.length) throw new Error('referencias rotas en ' + [...new Set(broken.map((b) => b.table))].join(', '));
          this.raw.exec('PRAGMA user_version = ' + (v + 1));
          this.raw.exec('COMMIT');
        } catch (e) { this.raw.exec('ROLLBACK'); throw new Error('Migración ' + (v + 1) + ' falló: ' + e.message); }
      }
    } finally { this.raw.exec('PRAGMA foreign_keys = ON'); }
  }

  /** Siguiente número de una secuencia (recibos, facturas, códigos de cliente). Debe usarse dentro de tx(). */
  nextSeq(name) {
    this.run('INSERT INTO sequences(name, value) VALUES (?, 0) ON CONFLICT(name) DO NOTHING', name);
    this.run('UPDATE sequences SET value = value + 1 WHERE name = ?', name);
    return this.get('SELECT value FROM sequences WHERE name = ?', name).value;
  }

  /** Copia consistente de la base (para respaldos), sin detener el servidor. */
  snapshotTo(file) {
    if (fs.existsSync(file)) fs.unlinkSync(file);
    this.raw.exec(`VACUUM INTO '${String(file).replace(/'/g, "''")}'`);
  }

  close() { this.raw.close(); }
}

module.exports = { Db };
