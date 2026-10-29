'use strict';
/** Inicio de sesión, doble factor, contraseña, confirmación (sudo) y sesiones del equipo. */
const sec = require('../http/security');
const v = require('../lib/validate');
const qr = require('../lib/qr');
const { HttpError } = require('../http/app');
const { nowIso } = require('../lib/time');
const { base, U, actor } = require('./_admin');
const { requireUser } = require('../services/auth');

module.exports = (app, s) => {
  const { auth, audit, db } = s;
  const { guard } = base(s);
  const loginIp = sec.rateLimit({ max: 10, windowMs: 15 * 60_000, name: 'login-ip', message: 'Demasiados intentos desde tu red. Espera 15 minutos.' });
  const codeIp = sec.rateLimit({ max: 15, windowMs: 15 * 60_000, name: 'code-ip', message: 'Demasiados intentos. Espera 15 minutos.' });
  const partial = [guard, requireUser(auth, { mfa: false })];

  const me = (ctx) => {
    const { user: u, session } = ctx.state;
    const stage = u.must_change_password ? 'cambiar_contrasena' : !u.totp_enabled ? 'activar_2fa' : !session.mfa_ok ? 'codigo' : 'listo';
    return { user: auth.publicUser(u), csrf: session.csrf, stage, sudoUntil: session.sudo_until, company: s.config.company.name };
  };

  app.post('/api/admin/auth/login', guard, loginIp, async (ctx) => {
    const b = v.parse(await ctx.json(4096), { email: v.str({ min: 3, max: 254 }), password: v.str({ min: 1, max: 200 }) });
    const r = await auth.login(b.email, b.password, ctx);
    ctx.state.user = r.user; ctx.state.session = db.get('SELECT * FROM sessions WHERE id = ?', r.session.id);
    ctx.ok(me(ctx));
  });

  app.get('/api/admin/auth/me', ...partial, (ctx) => ctx.ok(me(ctx)));

  app.post('/api/admin/auth/password', ...partial, codeIp, async (ctx) => {
    const b = v.parse(await ctx.json(4096), { current: v.str({ min: 1, max: 200 }), next: v.str({ min: 1, max: 200 }) });
    await auth.changePassword(ctx.state.user, b.current, b.next, ctx);
    ctx.state.user = db.get('SELECT * FROM users WHERE id = ?', ctx.state.user.id);
    ctx.ok(me(ctx));
  });

  app.post('/api/admin/auth/enroll/start', ...partial, (ctx) => {
    const u = ctx.state.user;
    if (u.must_change_password) throw new HttpError(403, 'CAMBIAR_CONTRASENA', 'Primero cambia tu contraseña temporal.');
    const r = auth.startEnrollment(u);
    ctx.ok({ secret: r.secret.replace(/(.{4})/g, '$1 ').trim(), otpauth: r.otpauth, qrSvg: qr.toSvg(r.otpauth, { scale: 4 }) });
  });

  app.post('/api/admin/auth/enroll/finish', ...partial, codeIp, async (ctx) => {
    const b = v.parse(await ctx.json(1024), { code: v.str({ min: 6, max: 10 }) });
    const u = db.get('SELECT * FROM users WHERE id = ?', ctx.state.user.id);
    if (u.totp_enabled) throw new HttpError(409, 'YA_ACTIVO', 'El doble factor ya está activo.');
    const codes = auth.finishEnrollment(u, b.code);
    if (!codes) { auth.totpFailed(u, ctx); throw new HttpError(400, 'CODIGO', 'Código incorrecto. Revisa que la hora de tu celular sea automática.'); }
    audit.log({ actor: actor(ctx), action: '2fa.activado', entity: ['user', u.id], ip: ctx.ip });
    auth.rotateSession(ctx, { mfa_ok: 1, sudo_until: nowIso(Date.now() + 10 * 60e3) });
    ctx.state.user = db.get('SELECT * FROM users WHERE id = ?', u.id);
    auth.markLogin(ctx.state.user, ctx);
    ctx.ok(Object.assign(me(ctx), { recoveryCodes: codes }));
  });

  app.post('/api/admin/auth/totp', ...partial, codeIp, async (ctx) => {
    const b = v.parse(await ctx.json(1024), { code: v.str({ min: 6, max: 12 }) });
    const u = db.get('SELECT * FROM users WHERE id = ?', ctx.state.user.id);
    if (u.must_change_password || !u.totp_enabled) throw new HttpError(409, 'ETAPA', 'Paso no disponible.');
    const code = b.code.replace(/\s/g, '');
    const ok = /^\d{6}$/.test(code) ? auth.checkTotp(u, code) : auth.useRecoveryCode(u, code);
    if (!ok) { auth.totpFailed(u, ctx); throw new HttpError(400, 'CODIGO', 'Código incorrecto.'); }
    if (!/^\d{6}$/.test(code)) audit.log({ actor: { type: 'usuario', id: u.id, label: u.name }, action: '2fa.codigo_respaldo_usado', entity: ['user', u.id], ip: ctx.ip, data: { restantes: JSON.parse(db.get('SELECT recovery_codes FROM users WHERE id = ?', u.id).recovery_codes).length } });
    auth.rotateSession(ctx, { mfa_ok: 1, sudo_until: nowIso(Date.now() + 10 * 60e3) });
    ctx.state.user = db.get('SELECT * FROM users WHERE id = ?', u.id);
    auth.markLogin(ctx.state.user, ctx);
    ctx.ok(me(ctx));
  });

  app.post('/api/admin/auth/sudo', ...U(s), codeIp, async (ctx) => {
    const b = v.parse(await ctx.json(1024), { code: v.str({ min: 6, max: 6 }) });
    const u = db.get('SELECT * FROM users WHERE id = ?', ctx.state.user.id);
    if (!auth.checkTotp(u, b.code)) { auth.totpFailed(u, ctx); throw new HttpError(400, 'CODIGO', 'Código incorrecto.'); }
    const until = nowIso(Date.now() + 10 * 60e3);
    db.run('UPDATE sessions SET sudo_until = ? WHERE id = ?', until, ctx.state.session.id);
    audit.log({ actor: actor(ctx), action: 'sesion.confirmacion', entity: ['user', u.id], ip: ctx.ip });
    ctx.ok({ sudoUntil: until });
  });

  app.post('/api/admin/auth/logout', guard, (ctx) => {
    const r = auth.readSession(ctx);
    if (r) {
      ctx.state.session = r.session;
      const t = ctx.header('x-csrf-token');
      if (t && require('../lib/crypto').safeEqual(t, r.session.csrf)) { auth.logout(ctx); audit.log({ actor: { type: 'usuario', id: r.user.id, label: r.user.name }, action: 'logout', entity: ['user', r.user.id], ip: ctx.ip }); }
    }
    ctx.setCookie(auth.cookieName, '', { maxAge: 0, secure: s.config.production });
    ctx.ok();
  });

  app.get('/api/admin/auth/sessions', ...U(s), (ctx) => {
    ctx.ok({ sessions: db.all('SELECT id, ip, ua, created_at, last_seen_at, expires_at FROM sessions WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ? ORDER BY last_seen_at DESC', ctx.state.user.id, nowIso())
      .map((r) => ({ current: r.id === ctx.state.session.id, ip: r.ip, ua: r.ua, created_at: r.created_at, last_seen_at: r.last_seen_at, ref: r.id.slice(0, 8) })) });
  });

  app.post('/api/admin/auth/sessions/revoke-others', ...U(s), (ctx) => {
    auth.revokeAllSessions(ctx.state.user.id, ctx.state.session.id);
    audit.log({ actor: actor(ctx), action: 'sesion.cerrar_otras', entity: ['user', ctx.state.user.id], ip: ctx.ip });
    ctx.ok();
  });

  app.post('/api/admin/auth/recovery-codes', ...U(s, { sudo: true }), (ctx) => {
    const C = require('../lib/crypto');
    const codes = Array.from({ length: 8 }, () => C.randomCode(10));
    db.run('UPDATE users SET recovery_codes = ? WHERE id = ?', JSON.stringify(codes.map((c) => C.sha256(c))), ctx.state.user.id);
    audit.log({ actor: actor(ctx), action: '2fa.codigos_regenerados', entity: ['user', ctx.state.user.id], ip: ctx.ip });
    ctx.ok({ recoveryCodes: codes.map((c) => c.slice(0, 5) + '-' + c.slice(5)) });
  });
};
