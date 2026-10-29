'use strict';
/**
 * Verifica la cadena de la bitácora de auditoría. Imprime la "cabeza" (hash del último registro).
 * Consejo: envía cada día esa cabeza a un lugar externo (correo, otro servidor). Si alguien con
 * acceso total reescribiera la base, la cabeza ya no coincidiría con la que guardaste afuera.
 */
const { boot } = require('./_boot');
const hub = boot();
const r = hub.audit.verify();
if (r.ok) console.log(`Bitácora íntegra: ${r.count} registros. Cabeza: ${r.head}`);
else { console.error(`BITÁCORA ALTERADA en el registro ${r.brokenAt}: ${r.reason}`); process.exitCode = 2; }
hub.shutdown();
