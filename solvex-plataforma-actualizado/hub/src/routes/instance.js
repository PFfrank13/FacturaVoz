'use strict';
/**
 * API para los PRODUCTOS (barbería, restaurante, sistemas a medida).
 *
 * SaaS multi-negocio (ej. la barbería que aloja a muchas barberías):
 *   Authorization: Bearer slxk_xxxxxxxx_<secreto>      (clave de la instancia; en el Hub solo se guarda su hash)
 *   GET  /v1/instance/licenses             → token firmado de cada negocio de la instancia
 *   GET  /v1/instance/licenses/:tenant     → token de un negocio
 *   POST /v1/instance/heartbeat            → "sigo vivo" (versión, cantidad de negocios)
 *   POST /v1/instance/trials               → prueba gratis autoservicio de un negocio nuevo (una por RUC/DNI)
 *
 * Producto instalable en el equipo del cliente (licencia con clave):
 *   POST /v1/activate  { license_key, fingerprint, label }  → activa el equipo y devuelve un token
 *   POST /v1/refresh   { license_key, fingerprint }         → renueva el token
 */
const v = require('../lib/validate');
const C = require('../lib/crypto');
const T = require('../lib/time');
const sec = require('../http/security');
const { HttpError } = require('../http/app');

module.exports = (app, s) => {
  const { db, licenses, audit, config } = s;
  const api = sec.headers('api', { production: config.production });
  const limInst = sec.rateLimit({ max: 600, windowMs: 60e3, name: 'inst', key: (ctx) => ctx.state.instance ? ctx.state.instance.id : ctx.ip });
  const limBadKey = sec.rateLimit({ max: 20, windowMs: 15 * 60e3, name: 'inst-bad', message: 'Demasiados intentos con claves inválidas.' });
  const limKey = sec.rateLimit({ max: 30, windowMs: 15 * 60e3, name: 'key', message: 'Demasiados intentos de activación. Espera 15 minutos.' });

  function instanceAuth(ctx) {
    api(ctx);
    const h = ctx.header('authorization');
    const key = h.startsWith('Bearer ') ? h.slice(7).trim() : '';
    const inst = /^slxk_[a-z0-9]{8}_[A-Za-z0-9_-]{40,60}$/.test(key) ? db.get('SELECT * FROM instances WHERE api_key_hash = ?', C.sha256(key)) : null;
    if (!inst || inst.status !== 'activa') {
      limBadKey(ctx);
      throw new HttpError(401, 'INSTANCIA_NO_AUTORIZADA', 'Clave de instancia inválida o revocada.');
    }
    if (inst.allowed_ips && !sec.ipAllowed(ctx.ip, inst.allowed_ips.split(',').filter(Boolean))) {
      audit.log({ actor: { type: 'instancia', id: inst.id, label: inst.name }, action: 'instancia.ip_no_permitida', entity: ['instance', inst.id], ip: ctx.ip });
      throw new HttpError(403, 'IP_NO_PERMITIDA', 'IP no permitida para esta instancia.');
    }
    ctx.state.instance = inst;
    limInst(ctx);
    if (!inst.last_seen_at || Date.now() - Date.parse(inst.last_seen_at) > 60e3) db.run('UPDATE instances SET last_seen_at = ?, last_seen_ip = ? WHERE id = ?', T.nowIso(), ctx.ip, inst.id);
  }

  app.get('/v1/instance/licenses', instanceAuth, (ctx) => {
    const inst = ctx.state.instance;
    const rows = db.all('SELECT * FROM licenses WHERE instance_id = ? AND tenant_ref IS NOT NULL', inst.id);
    ctx.ok({ server_time: T.nowIso(), next_poll_seconds: 300, licenses: rows.map((l) => ({ tenant_ref: l.tenant_ref, license_code: l.code, token: licenses.token(l, { aud: inst.id }) })) });
  });

  app.get('/v1/instance/licenses/:tenant', instanceAuth, (ctx) => {
    const inst = ctx.state.instance;
    const l = db.get('SELECT * FROM licenses WHERE instance_id = ? AND tenant_ref = ?', inst.id, String(ctx.params.tenant).slice(0, 80));
    // Negocio desconocido para esta instancia: 404 (la instancia debe tratarlo como NO habilitado).
    if (!l) throw new HttpError(404, 'SIN_LICENCIA', 'Este negocio no tiene licencia en esta instancia.');
    ctx.ok({ server_time: T.nowIso(), tenant_ref: l.tenant_ref, license_code: l.code, token: licenses.token(l, { aud: inst.id }) });
  });

  /* ---------------- prueba gratis autoservicio (SaaS) ----------------
   * POST /v1/instance/trials  { tenant_ref, doc_type:'RUC'|'DNI', doc_number, business_name, email?, phone?, plan_code? }
   * La instancia (con SU clave) pide la prueba gratis de un negocio que se acaba de registrar en el producto.
   *  - Una sola licencia por tenant_ref en la instancia: si ya existe, devuelve su token (idempotente).
   *  - Una sola PRUEBA por documento (RUC/DNI) y producto: si ese cliente ya tuvo prueba → 409 PRUEBA_USADA.
   *  - Plan: el indicado (plan_code) o, si no, el plan activo con prueba más completo (mayor precio).
   *  - Límite de intentos por instancia y por IP. Todo queda en la bitácora de auditoría.
   */
  const limTrialInst = sec.rateLimit({ max: 60, windowMs: 60 * 60e3, name: 'trial-inst', key: (ctx) => ctx.state.instance ? ctx.state.instance.id : ctx.ip, message: 'Demasiadas pruebas solicitadas. Intenta en una hora.' });
  const limTrialIp = sec.rateLimit({ max: 120, windowMs: 60 * 60e3, name: 'trial-ip', message: 'Demasiadas pruebas solicitadas. Intenta en una hora.' });
  const trialSchema = {
    tenant_ref: v.str({ min: 2, max: 80, pattern: /^[A-Za-z0-9_-]{2,80}$/ }),
    doc_type: v.oneOf(['RUC', 'DNI'], { default: 'RUC' }),
    doc_number: v.str({ min: 8, max: 11 }),
    business_name: v.str({ min: 2, max: 120 }),
    email: v.email({ optional: true }),
    phone: v.phone({ optional: true }),
    plan_code: v.str({ max: 40, pattern: /^[A-Z0-9_-]{1,40}$/, optional: true }),
  };

  app.post('/v1/instance/trials', instanceAuth, async (ctx) => {
    limTrialInst(ctx); limTrialIp(ctx);
    const inst = ctx.state.instance;
    const b = v.parse(await ctx.json(4096), trialSchema);
    b.doc_number = v.docNumber(b.doc_type, b.doc_number);
    const actor = { type: 'instancia', id: inst.id, label: inst.name };

    const existing = db.get('SELECT * FROM licenses WHERE instance_id = ? AND tenant_ref = ?', inst.id, b.tenant_ref);
    if (existing) {
      ctx.ok({ server_time: T.nowIso(), created: false, tenant_ref: existing.tenant_ref, license_code: existing.code, token: licenses.token(existing, { aud: inst.id }) });
      return;
    }
    const product = db.get('SELECT * FROM products WHERE id = ?', inst.product_id);
    if (!product || product.status !== 'activo') throw new HttpError(409, 'PRODUCTO', 'El producto no está activo.');
    const plan = b.plan_code
      ? db.get('SELECT * FROM plans WHERE product_id = ? AND code = ? AND active = 1', product.id, b.plan_code)
      : db.get('SELECT * FROM plans WHERE product_id = ? AND active = 1 AND trial_days > 0 ORDER BY price_cents DESC, created_at ASC LIMIT 1', product.id);
    if (!plan) throw new HttpError(409, 'SIN_PLAN', 'No hay un plan activo con prueba para este producto.');
    if (!(plan.trial_days > 0)) throw new HttpError(409, 'SIN_PRUEBA', 'El plan no tiene días de prueba.');

    const bidx = s.vault.bidx('doc', b.doc_type + ':' + b.doc_number);
    const known = db.get('SELECT * FROM clients WHERE doc_bidx = ? AND deleted_at IS NULL', bidx);
    if (known) {
      const used = db.get(`SELECT l.code FROM licenses l WHERE l.client_id = ? AND l.product_id = ?
          AND (l.is_trial = 1 OR EXISTS (SELECT 1 FROM license_grants g WHERE g.license_id = l.id AND g.kind = 'prueba')) LIMIT 1`, known.id, product.id);
      if (used) {
        audit.log({ actor, action: 'licencia.prueba_rechazada', entity: ['client', known.id], ip: ctx.ip, data: { motivo: 'prueba ya usada', tenant: b.tenant_ref } });
        throw new HttpError(409, 'PRUEBA_USADA', 'Este RUC/DNI ya usó su prueba gratis. Elige un plan para continuar.');
      }
    }

    const out = db.tx(() => {
      const client = known || s.clients.create({
        kind: b.doc_type === 'RUC' ? 'empresa' : 'persona', display_name: b.business_name, legal_name: b.business_name,
        doc_type: b.doc_type, doc_number: b.doc_number, country: 'PE', email: b.email || undefined, phone: b.phone || undefined,
        notes: 'Registrado automáticamente al pedir la prueba gratis desde ' + inst.name,
      }, actor, ctx.ip);
      const r = licenses.create({ client_id: client.id, plan_id: plan.id, instance_id: inst.id, tenant_ref: b.tenant_ref, label: b.business_name, start: 'prueba' }, actor, ctx.ip);
      audit.log({ actor, action: 'licencia.prueba_autoservicio', entity: ['license', r.license.id], ip: ctx.ip, data: { tenant: b.tenant_ref, plan: plan.code, dias: plan.trial_days } });
      return r.license;
    });
    ctx.send(201, { server_time: T.nowIso(), created: true, tenant_ref: out.tenant_ref, license_code: out.code, token: licenses.token(out, { aud: inst.id }) });
  });

  app.post('/v1/instance/heartbeat', instanceAuth, async (ctx) => {
    const b = v.parse(await ctx.json(2048), { version: v.str({ max: 40, optional: true }), tenants: v.int({ min: 0, max: 1e6, optional: true }) });
    db.run('UPDATE instances SET app_version = ?, last_seen_at = ?, last_seen_ip = ? WHERE id = ?', b.version, T.nowIso(), ctx.ip, ctx.state.instance.id);
    ctx.ok({ server_time: T.nowIso() });
  });

  /* ---------------- productos instalables ---------------- */
  const keySchema = { license_key: v.str({ min: 10, max: 40, pattern: /^SLX(-[A-Z0-9]{5}){4}$/ }), fingerprint: v.str({ min: 16, max: 200 }), label: v.str({ max: 80, optional: true }) };

  function byKey(ctx, key) {
    const l = db.get('SELECT * FROM licenses WHERE key_hash = ?', C.sha256(key));
    if (!l) { audit.log({ actor: { type: 'publico', label: 'activación' }, action: 'activacion.clave_invalida', ip: ctx.ip }); throw new HttpError(403, 'LICENCIA_INVALIDA', 'Clave de licencia no válida.'); }
    return l;
  }

  app.post('/v1/activate', limKey, async (ctx) => {
    api(ctx);
    const b = v.parse(await ctx.json(2048), keySchema);
    const l = byKey(ctx, b.license_key.toUpperCase());
    const fp = C.sha256('fp:' + b.fingerprint);
    const out = db.tx(() => {
      const existing = db.get('SELECT * FROM activations WHERE license_id = ? AND fingerprint_hash = ?', l.id, fp);
      if (existing && existing.revoked_at) throw new HttpError(403, 'EQUIPO_REVOCADO', 'Este equipo fue desactivado. Comunícate con Solvex.');
      if (!existing) {
        const used = db.get('SELECT COUNT(*) n FROM activations WHERE license_id = ? AND revoked_at IS NULL', l.id).n;
        if (used >= l.max_activations) throw new HttpError(409, 'LIMITE_EQUIPOS', `La licencia ya está activada en ${used} equipo(s), el máximo permitido.`);
        db.run('INSERT INTO activations (id,license_id,fingerprint_hash,label,ip,first_seen_at,last_seen_at) VALUES (?,?,?,?,?,?,?)', C.newId('act'), l.id, fp, b.label, ctx.ip, T.nowIso(), T.nowIso());
        audit.log({ actor: { type: 'publico', label: b.label || 'equipo' }, action: 'activacion.nueva', entity: ['license', l.id], ip: ctx.ip });
      } else db.run('UPDATE activations SET last_seen_at = ?, ip = ? WHERE id = ?', T.nowIso(), ctx.ip, existing.id);
      return licenses.token(l, { aud: 'onprem', fingerprint: fp });
    });
    ctx.ok({ license_code: l.code, token: out });
  });

  app.post('/v1/refresh', limKey, async (ctx) => {
    api(ctx);
    const b = v.parse(await ctx.json(2048), keySchema);
    const l = byKey(ctx, b.license_key.toUpperCase());
    const fp = C.sha256('fp:' + b.fingerprint);
    const a = db.get('SELECT * FROM activations WHERE license_id = ? AND fingerprint_hash = ?', l.id, fp);
    if (!a || a.revoked_at) throw new HttpError(403, 'NO_ACTIVADO', 'Este equipo no está activado para la licencia.');
    db.run('UPDATE activations SET last_seen_at = ?, ip = ? WHERE id = ?', T.nowIso(), ctx.ip, a.id);
    ctx.ok({ license_code: l.code, token: licenses.token(l, { aud: 'onprem', fingerprint: fp }) });
  });
};
