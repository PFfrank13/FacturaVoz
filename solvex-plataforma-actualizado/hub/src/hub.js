'use strict';
/** Arma el Hub: servicios + rutas. Lo usan server.js, los scripts y las pruebas. */
const { Db } = require('./db');
const { Vault } = require('./lib/crypto');
const { App } = require('./http/app');
const sec = require('./http/security');
const { Audit } = require('./services/audit');
const { Auth } = require('./services/auth');
const { Settings } = require('./services/settings');
const { Bus, Outbox } = require('./services/events');
const { Notifier } = require('./services/notify');
const { Licenses } = require('./services/licenses');
const { Billing } = require('./services/billing');
const { Tax } = require('./services/tax');
const { Einvoice } = require('./services/einvoice');
const { Mor } = require('./services/mor');
const { makeProvider } = require('./gateways/einvoice');
const { Clients } = require('./services/clients');
const { Scheduler } = require('./services/scheduler');
const { makeViews } = require('./services/views');
const { CulqiGateway, FakeGateway } = require('./gateways/culqi');

function createHub(config, { db: dbOverride, gateway: gwOverride, einvoiceProvider: eiOverride, fetchImpl = globalThis.fetch, log = console } = {}) {
  const db = dbOverride || new Db(config.dbPath);
  const vault = new Vault({ keys: config.vaultKeys, active: config.vaultActive, bidxKey: config.bidxKey });
  const bus = new Bus(); bus.setMaxListeners(200);
  const audit = new Audit(db, config.auditKey, bus);
  const settings = new Settings(db);
  const outbox = new Outbox({ db, vault, bus, log, fetchImpl, allowPrivateWebhooks: config.dev });
  const notifier = new Notifier({ db, vault, config, log, fetchImpl });
  const licenses = new Licenses({ db, vault, audit, outbox, notifier, settings, config, bus });
  const tax = new Tax({ db, settings });
  const billing = new Billing({ db, vault, audit, licenses, notifier, settings, config, bus, tax });
  const einvoice = new Einvoice({ db, vault, audit, settings, config, bus, billing, tax, provider: eiOverride !== undefined ? eiOverride : makeProvider(config.einvoice, fetchImpl), log });
  const mor = new Mor({ db, vault, audit, billing, licenses, bus, config, log });
  const clients = new Clients({ db, vault, audit, bus });
  const auth = new Auth({ db, vault, audit, config });
  const views = makeViews({ db, vault, billing, einvoice, tax });
  let gateway = gwOverride || null;
  if (!gateway && config.culqi) gateway = new CulqiGateway({ secretKey: config.culqi.secretKey, apiBase: config.culqi.apiBase, fetchImpl });
  if (!gateway && config.dev) gateway = new FakeGateway();
  const scheduler = new Scheduler({ db, licenses, billing, outbox, notifier, settings, gateway, audit, einvoice, log });

  const s = { config, db, vault, bus, audit, settings, outbox, notifier, licenses, billing, tax, einvoice, mor, clients, auth, views, gateway, scheduler, log };

  const app = new App({ trustProxy: config.trustProxy, log });
  app.use((ctx) => {
    ctx.set('X-Request-Id', ctx.id);
    // En producción el Hub escucha solo en 127.0.0.1 detrás de Nginx/Caddy con HTTPS. Si el proxy avisa que llegó por http, se rechaza.
    if (config.production && ctx.header('x-forwarded-proto') === 'http' && ctx.path !== '/health') { sec.headers('api', { production: true })(ctx); ctx.send(400, { error: 'HTTPS', message: 'Usa HTTPS.' }); }
  });
  require('./routes/public')(app, s);
  require('./routes/instance')(app, s);
  require('./routes/admin-auth')(app, s);
  require('./routes/admin-core')(app, s);
  require('./routes/admin-billing')(app, s);
  require('./routes/admin-tax')(app, s);
  require('./routes/admin-more')(app, s);
  require('./routes/panel-static')(app, s);
  app.get('/health', (ctx) => { sec.headers('api')(ctx); ctx.ok({ ok: true }); });
  s.app = app;
  s.shutdown = () => { outbox.closed = true; einvoice.closed = true; scheduler.stop(); db.close(); };
  return s;
}

module.exports = { createHub };
