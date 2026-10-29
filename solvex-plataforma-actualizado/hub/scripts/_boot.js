'use strict';
/** Carga la configuración y los servicios del Hub sin abrir el servidor (para los scripts). */
const path = require('node:path');
process.chdir(path.join(__dirname, '..'));
const { build } = require('../src/config');
const { createHub } = require('../src/hub');

function boot({ requireDev = false } = {}) {
  let config;
  try { config = build(); } catch (e) { console.error(e.message); process.exit(1); }
  if (requireDev && !config.dev) { console.error('Este script solo funciona en modo desarrollo (npm run ... -- --dev o NODE_ENV distinto de production).'); process.exit(1); }
  const quiet = { info() {}, warn: console.warn, error: console.error, log() {} };
  return createHub(config, { log: quiet });
}
module.exports = { boot };
