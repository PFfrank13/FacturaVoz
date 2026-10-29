'use strict';
/** Punto de entrada: npm start (producción) o npm run dev (desarrollo). */
const { build } = require('./config');
const { createHub } = require('./hub');

let config;
try { config = build(); } catch (e) { console.error(e.message); process.exit(1); }

const hub = createHub(config);
const server = hub.app.server();
server.listen(config.port, config.host, () => {
  console.log(`Solvex Hub ${config.dev ? '(DESARROLLO) ' : ''}escuchando en http://${config.host}:${config.port}`);
  console.log(`Panel: ${config.publicUrl}/panel/`);
  if (config.dev) console.log('Modo desarrollo: secretos de prueba en data/dev-secrets.json. Pasarela simulada. Correos solo en consola.');
  const owners = hub.db.get('SELECT COUNT(*) n FROM users').n;
  if (!owners) console.log('Aún no hay usuarios: crea el primero con  npm run crear-admin');
});
if (config.schedulerEnabled) hub.scheduler.start();

const stop = (sig) => {
  console.log(sig + ': cerrando...');
  server.close(() => { hub.shutdown(); process.exit(0); });
  setTimeout(() => server.closeAllConnections(), 1500).unref(); // cierra los canales en vivo (SSE) del panel
  setTimeout(() => process.exit(0), 8000).unref();
};
process.on('SIGTERM', () => stop('SIGTERM'));
process.on('SIGINT', () => stop('SIGINT'));
process.on('unhandledRejection', (e) => console.error('unhandledRejection', e && e.stack || e));
