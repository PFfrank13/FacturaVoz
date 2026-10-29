'use strict';
/**
 * Datos de DEMOSTRACIÓN para conocer el panel (solo en modo desarrollo).
 *   npm run demo
 * Crea un usuario propietario demo, productos, planes, clientes, licencias en todos los estados,
 * pagos, solicitudes, tickets y gastos. Imprime la contraseña y el secreto 2FA de la cuenta demo.
 */
const { boot } = require('./_boot');
const T = require('../src/lib/time');
const C = require('../src/lib/crypto');
const totp = require('../src/lib/totp');

(async () => {
  const hub = boot({ requireDev: true });
  const { db, vault } = hub;
  if (db.get('SELECT COUNT(*) n FROM clients').n) { console.error('La base ya tiene datos. Usa una base nueva (borra data/hub.db en desarrollo).'); process.exit(1); }
  const sys = { type: 'sistema', label: 'Datos demo' };
  const PASS = 'barba-tijera-navaja-2026';
  const secret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
  const mk = async (email, name, role) => {
    const u = await hub.auth.createUser({ email, name, role, password: PASS }, sys);
    db.run('UPDATE users SET must_change_password = 0, totp_enabled = 1, totp_secret_enc = ? WHERE id = ?', vault.encrypt(secret, 'users.totp:' + u.id), u.id);
    return u;
  };
  const owner = await mk('frank@solvex.pe', 'Frank Pineda', 'propietario');
  await mk('jack@solvex.pe', 'Jack Rosales', 'administrador');
  await mk('finanzas@solvex.pe', 'Finanzas Solvex', 'finanzas');
  const actor = { type: 'usuario', id: owner.id, label: owner.name };
  const now = T.nowIso();

  const prod = (code, name, kind, status, keys, pub) => { const id = C.newId('prd'); db.run('INSERT INTO products (id,code,name,kind,status,description,feature_keys,public,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)', id, code, name, kind, status, '', JSON.stringify(keys), pub ? 1 : 0, now, now); return id; };
  const plan = (pid, code, name, unit, count, soles, trial, grace, feats, pub) => { const id = C.newId('pln'); db.run('INSERT INTO plans (id,product_id,code,name,interval_unit,interval_count,price_cents,trial_days,grace_days,features,public,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,1,?,?)', id, pid, code, name, unit, count, Math.round(soles * 100), trial, grace, JSON.stringify(feats), pub ? 1 : 0, now, now); return id; };
  const pB = prod('BARBERIA', 'Sistema de Barbería', 'saas', 'activo', ['max_branches', 'max_barbers', 'online_payments', 'whatsapp'], true);
  const pR = prod('RESTAURANTE', 'Sistema de Restaurante', 'saas', 'borrador', ['max_tables', 'online_orders'], false);
  const pM = prod('A_MEDIDA', 'Software a la medida', 'a_medida', 'activo', [], false);
  const pI = prod('CAJA_POS', 'Caja POS instalable', 'instalable', 'activo', ['max_devices'], false);
  const bM = plan(pB, 'MENSUAL', 'Barbería mensual', 'month', 1, 150, 30, 5, { max_branches: 1, max_barbers: 6, online_payments: true, whatsapp: false }, true);
  const bT = plan(pB, 'TRIMESTRAL', 'Barbería trimestral', 'month', 3, 420, 30, 5, { max_branches: 2, max_barbers: 10, online_payments: true, whatsapp: true }, true);
  const bA = plan(pB, 'ANUAL', 'Barbería anual', 'year', 1, 1500, 30, 7, { max_branches: 3, max_barbers: -1, online_payments: true, whatsapp: true }, true);
  plan(pR, 'MENSUAL', 'Restaurante mensual', 'month', 1, 180, 30, 5, { max_tables: 20, online_orders: true }, false);
  const mH = plan(pM, 'HOSTING', 'Hosting y soporte mensual', 'month', 1, 80, 0, 5, {}, false);
  const mL = plan(pM, 'COMPRA', 'Compra de licencia (pago único)', 'none', 1, 6500, 0, 0, {}, false);
  const iA = plan(pI, 'ANUAL', 'Caja POS anual', 'year', 1, 600, 15, 7, { max_devices: 2 }, false);

  const instId = C.newId('ins'), key = `slxk_demo0001_${C.newSecret(32)}`;
  db.run("INSERT INTO instances (id,product_id,name,environment,webhook_url,webhook_secret_enc,api_key_hash,api_key_prefix,status,last_seen_at,app_version,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,'activa',?,?,?,?)",
    instId, pB, 'Barbería SaaS · producción', 'produccion', null, vault.encrypt('whsec_demo', 'instances.webhook_secret:' + instId), C.sha256(key), 'slxk_demo0001', now, '1.4.0', now, now);

  // Comprobantes simulados activos y Solvex inscrito como exportador (para ver facturas, boletas y exportación).
  hub.settings.set('einvoice', Object.assign({}, hub.settings.get('einvoice'), { enabled: true }), owner.id);
  hub.settings.set('tax', { regime: 'mype', export_registered: true }, owner.id);
  const ADDR = ['Av. Grau 123, Ica', 'Jr. Ucayali 455, Lima', 'Calle Lima 210, Ica', 'Av. Ejército 801, Arequipa', 'Av. Arequipa 2450, Lima', '', 'Av. Larco 300, Miraflores', 'Panamericana Sur km 300, Ica'];
  const cl = [
    ['empresa', 'Barbería Don Corte', 'RUC', '20100047218', 'Luis Ramos Quispe', 'luis@doncorte.pe', '987111222', 'Ica', 'verificado'],
    ['empresa', 'Navaja Real', 'RUC', '20131312955', 'Marco Villanueva', 'marco@navajareal.pe', '987222333', 'Lima', 'verificado'],
    ['empresa', 'Filo & Estilo', 'RUC', '20100070970', 'Diego Paredes', 'diego@filoestilo.pe', '987333444', 'Ica', 'verificado'],
    ['persona', 'Barber Lab', 'DNI', '45678912', 'Andrea Salas', 'andrea@barberlab.pe', '987444555', 'Arequipa', 'verificado'],
    ['empresa', 'El Patrón Barbershop', 'RUC', '20100130204', 'Jorge Ccopa', 'jorge@elpatron.pe', '987555666', 'Lima', 'verificado'],
    ['empresa', 'Corte Fino', 'RUC', '20100017491', 'Rafael Medina', 'rafael@cortefino.pe', '987666777', 'Trujillo', 'observado'],
    ['persona', "Gentleman's", 'DNI', '41234567', 'Kevin Huamán', 'kevin@gentlemans.pe', '987777888', 'Lima', 'pendiente'],
    ['empresa', 'Distribuidora Aybar', 'RUC', '20100113610', 'Patricia Aybar', 'patricia@aybar.pe', '987888999', 'Ica', 'verificado'],
  ].map((r, i) => hub.clients.create({ kind: r[0], display_name: r[1], legal_name: r[0] === 'empresa' ? r[1].toUpperCase() + ' S.A.C.' : r[4], doc_type: r[2], doc_number: r[3], contact_name: r[4], email: r[5], phone: r[6], city: r[7], address: ADDR[i] || undefined }, actor));
  // Cliente del extranjero (exportación de servicios, 0 % de IGV)
  const fx = hub.clients.create({ kind: 'empresa', display_name: 'Miami Barber Co', legal_name: 'MIAMI BARBER CO LLC', doc_type: 'EXT', doc_number: '12-3456789', country: 'US', region: 'FL', contact_name: 'John Pérez', email: 'john@miamibarber.co', city: 'Miami', address: '100 Biscayne Blvd, Miami FL' }, actor);
  cl.forEach((c, i) => { const ver = ['verificado', 'verificado', 'verificado', 'verificado', 'verificado', 'observado', 'pendiente', 'verificado'][i]; if (ver !== 'pendiente') hub.clients.verify(c.id, { verification: ver, checklist: { documento: true, ruc_sunat: true, local_redes: ver === 'verificado', contrato: ver === 'verificado' } }, actor); });

  const shift = (id, days) => { const l = db.get('SELECT period_end, grace_end FROM licenses WHERE id = ?', id); const mv = (x) => (x ? new Date(Date.parse(x) - days * 864e5).toISOString() : x); db.run('UPDATE licenses SET period_end = ?, grace_end = ? WHERE id = ?', mv(l.period_end), mv(l.grace_end), id); };
  const L = (o) => hub.licenses.create(Object.assign({ instance_id: instId }, o), actor).license;
  const pay = (licId, method, ref, soles) => {
    const l = db.get('SELECT * FROM licenses WHERE id = ?', licId);
    const inv = hub.billing.openInvoiceForLicense(l, { create: true }) || hub.billing.createInvoice({ client_id: l.client_id, license_id: l.id, kind: 'renovacion', periods: 1, amount_cents: l.price_cents, description: 'Renovación · ' + l.label }, actor);
    const p = hub.billing.registerPayment({ invoice_id: inv.id, method, amount_cents: Math.round((soles || l.price_cents / 100) * 100), operation_ref: ref }, actor);
    return hub.billing.approvePayment(p.id, actor);
  };

  // Don Corte: anual, al día
  const l1 = L({ client_id: cl[0].id, plan_id: bA, tenant_ref: 'don-corte', label: 'Don Corte · Ica', start: 'cortesia', note: 'Migración desde sistema anterior' });
  shift(l1.id, 300); hub.licenses.sync(l1.id); pay(l1.id, 'transferencia', 'BBVA-773410', 1500);
  // Navaja Real: mensual, vence en 5 días con cobro emitido
  const l2 = L({ client_id: cl[1].id, plan_id: bM, tenant_ref: 'navaja-real', start: 'cortesia', note: 'Alta inicial' }); shift(l2.id, 25); hub.billing.createRenewal(hub.licenses.get(l2.id));
  // Filo & Estilo: vence en 2 días + pago reportado por verificar
  const l3 = L({ client_id: cl[2].id, plan_id: bM, tenant_ref: 'filo-estilo', start: 'cortesia', note: 'Alta inicial' }); shift(l3.id, 28);
  { const inv = hub.billing.createRenewal(hub.licenses.get(l3.id)); hub.billing.registerPayment({ invoice_id: inv.id, method: 'yape', amount_cents: 15000, operation_ref: '00918273', paid_on: T.localDate(Date.now()), source: 'cliente' }, { type: 'publico', label: 'Cliente (enlace de pago)' }); }
  // Barber Lab: en prueba
  L({ client_id: cl[3].id, plan_id: bT, tenant_ref: 'barber-lab', start: 'prueba' });
  // El Patrón: en gracia (venció hace 3 días)
  const l5 = L({ client_id: cl[4].id, plan_id: bM, tenant_ref: 'el-patron', start: 'cortesia', note: 'Alta inicial' }); shift(l5.id, 33); hub.licenses.sync(l5.id);
  // Corte Fino: suspendida por falta de pago
  const l6 = L({ client_id: cl[5].id, plan_id: bM, tenant_ref: 'corte-fino', start: 'cortesia', note: 'Alta inicial' }); shift(l6.id, 45); hub.licenses.sync(l6.id);
  // Gentleman's: pendiente (implementación) con cobro de alta
  L({ client_id: cl[6].id, plan_id: bM, tenant_ref: 'gentlemans', start: 'cobro' });
  // Aybar: compra de software a medida (perpetua) + hosting mensual
  const l8 = hub.licenses.create({ client_id: cl[7].id, plan_id: mL, label: 'Sistema de distribución Aybar', start: 'cobro' }, actor);
  { const p = hub.billing.registerPayment({ invoice_id: l8.invoice.id, method: 'transferencia', amount_cents: 650000, operation_ref: 'BBVA-622100' }, actor); hub.billing.approvePayment(p.id, actor); }
  const l9 = hub.licenses.create({ client_id: cl[7].id, plan_id: mH, label: 'Hosting tienda en línea Aybar', start: 'cortesia', note: 'Primer mes incluido' }, actor).license; shift(l9.id, 20); pay(l9.id, 'yape', '00771234', 80);
  // Miami Barber Co: exportación (paga solo el valor de venta, factura al 0 %)
  const lx = L({ client_id: fx.id, plan_id: bM, tenant_ref: 'miami-barber', start: 'cobro' });
  { const inv = hub.billing.openInvoiceForLicense(hub.licenses.get(lx.id)); const p = hub.billing.registerPayment({ invoice_id: inv.id, method: 'transferencia', amount_cents: inv.amount_cents, operation_ref: 'WIRE-55120' }, actor); hub.billing.approvePayment(p.id, actor); }
  // Caja POS instalable
  const lp = hub.licenses.create({ client_id: cl[1].id, plan_id: iA, label: 'Caja POS · Navaja Real', start: 'cortesia', note: 'Venta anual', max_activations: 2 }, actor);
  db.run("INSERT INTO activations (id,license_id,fingerprint_hash,label,ip,first_seen_at,last_seen_at) VALUES (?,?,?,?,?,?,?)", C.newId('act'), lp.license.id, C.sha256('demo-fp'), 'Caja principal', '190.12.4.8', now, now);

  // Solicitudes, tickets, gastos
  const lead = (name, business, sector, contact, msg, status) => { const id = C.newId('led'); db.run('INSERT INTO leads (id,name_enc,business,sector,branches,contact_enc,message_enc,status,source,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)', id, vault.encrypt(name, 'leads.name:' + id), business, sector, '1 sede', vault.encrypt(contact, 'leads.contact:' + id), vault.encrypt(msg, 'leads.message:' + id), status, 'web', now, now); };
  lead('Carlos Ruiz', 'Barbería La Cumbre', 'Barbería', '956 123 456', 'Quiero reservas online y control de comisiones.', 'nuevo');
  lead('María Flores', 'Restaurante El Muelle', 'Restaurante', 'maria@elmuelle.pe', 'Necesitamos carta digital y pedidos.', 'contactado');
  lead('Pedro Salinas', 'Barbería Imperial', 'Barbería', '951 777 888', 'Somos 3 sedes.', 'demo');
  const tk = (cid, lid, subject, pr, st) => { const id = C.newId('tkt'); db.run("INSERT INTO tickets (id,number,client_id,license_id,subject,priority,status,assignee_id,created_by,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)", id, 'T-' + String(db.nextSeq('ticket')).padStart(5, '0'), cid, lid, subject, pr, st, owner.id, owner.id, now, now); };
  tk(cl[4].id, l5.id, 'No puedo entrar, dice pago pendiente', 'alta', 'abierto');
  tk(cl[1].id, l2.id, 'Quiero agregar una segunda sede', 'media', 'en_curso');
  tk(cl[0].id, l1.id, 'Reporte mensual de comisiones', 'baja', 'resuelto');
  const ex = (concept, cat, soles, daysAgo, pid) => db.run('INSERT INTO expenses (id,concept,category,amount_cents,spent_on,product_id,created_by,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)', C.newId('exp'), concept, cat, Math.round(soles * 100), T.addDays(T.localDate(Date.now()), -daysAgo), pid, owner.id, now, now);
  ex('Servidor VPS (Hetzner)', 'Infraestructura', 95, 3, pB); ex('Cloudflare R2', 'Infraestructura', 18, 5, pB); ex('WhatsApp Business (mensajes)', 'Comunicación', 60, 9, pB);
  ex('Publicidad en redes', 'Marketing', 250, 14, null); ex('Servidor VPS (Hetzner)', 'Infraestructura', 95, 33, pB); ex('Dominio solvex.pe', 'Infraestructura', 120, 60, null);
  hub.settings.set('payment_instructions', { yape_number: '987000111', yape_holder: 'Solvex S.A.C.', plin_number: '', plin_holder: '', bank_accounts: [{ bank: 'BCP', currency: 'PEN', account: '191-1234567-0-11', cci: '00219100123456701155', holder: 'Solvex S.A.C.' }], note: 'Después de pagar, envía el número de operación desde este enlace.' }, owner.id);
  hub.settings.set('company', { name: 'Solvex', legal_name: 'Solvex S.A.C.', ruc: '', address: 'Ica, Perú', email: 'hola@solvex.pe', phone: '', website: 'https://solvex.pe' }, owner.id);

  await hub.einvoice.run(); // envía los comprobantes al proveedor simulado
  console.log('\nDatos demo creados.');
  console.log('Panel:        ' + hub.config.publicUrl + '/panel/');
  console.log('Usuario:      frank@solvex.pe   (también jack@solvex.pe y finanzas@solvex.pe)');
  console.log('Contraseña:   ' + PASS);
  console.log('Secreto 2FA:  ' + secret + '  (agrégalo a tu app autenticadora; código actual: ' + totp.hotp(secret, totp.counterAt(Date.now())) + ')');
  console.log('Clave de la instancia demo (API de la barbería): ' + key);
  console.log('\nESTOS DATOS SON SOLO PARA DESARROLLO.');
  hub.shutdown();
})().catch((e) => { console.error(e); process.exit(1); });
