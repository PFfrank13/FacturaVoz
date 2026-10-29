'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const totp = require('../src/lib/totp');
const { startHub, Client, makeUser, code, login, sudo, PASSWORD } = require('./helpers');

test('primer ingreso: contraseña temporal → cambio obligatorio → activar 2FA con QR → códigos de respaldo', async (t) => {
  const h = await startHub(); t.after(h.stop);
  await h.hub.auth.createUser({ email: 'nuevo@solvex.pe', name: 'Nuevo', role: 'propietario', password: 'TEMP-ABCD-EFGH-JKMN' }, { type: 'sistema', label: 'x' });
  const c = new Client(h.base);
  let r = await c.post('/api/admin/auth/login', { email: 'nuevo@solvex.pe', password: 'TEMP-ABCD-EFGH-JKMN' });
  assert.equal(r.status, 200); assert.equal(r.json.stage, 'cambiar_contrasena');
  // con sesión parcial no se accede a nada
  assert.equal((await c.get('/api/admin/dashboard')).status, 401);
  assert.equal((await c.post('/api/admin/auth/enroll/start')).status, 403);
  r = await c.post('/api/admin/auth/password', { current: 'TEMP-ABCD-EFGH-JKMN', next: 'corta' });
  assert.equal(r.status, 400);
  r = await c.post('/api/admin/auth/password', { current: 'TEMP-ABCD-EFGH-JKMN', next: PASSWORD });
  assert.equal(r.status, 200); assert.equal(r.json.stage, 'activar_2fa');
  r = await c.post('/api/admin/auth/enroll/start');
  assert.equal(r.status, 200); assert.match(r.json.qrSvg, /^<svg/); assert.match(r.json.otpauth, /^otpauth:\/\/totp\//);
  const secret = r.json.secret.replace(/\s/g, '');
  r = await c.post('/api/admin/auth/enroll/finish', { code: '000000' === totp.hotp(secret, totp.counterAt(Date.now())) ? '111111' : '000000' });
  assert.equal(r.status, 400);
  r = await c.post('/api/admin/auth/enroll/finish', { code: totp.hotp(secret, totp.counterAt(Date.now())) });
  assert.equal(r.status, 200); assert.equal(r.json.stage, 'listo'); assert.equal(r.json.recoveryCodes.length, 8);
  assert.equal((await c.get('/api/admin/dashboard')).status, 200);
});

test('login: mensaje genérico, bloqueo tras 5 fallos, código 2FA y código de respaldo de un solo uso', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub);
  const c = new Client(h.base);
  const a = await c.post('/api/admin/auth/login', { email: 'noexiste@solvex.pe', password: 'x' });
  const b = await c.post('/api/admin/auth/login', { email: u.email, password: 'incorrecta' });
  assert.equal(a.status, 401); assert.equal(b.status, 401); assert.equal(a.json.message, b.json.message, 'no revela si el correo existe');
  for (let i = 0; i < 3; i++) await c.post('/api/admin/auth/login', { email: u.email, password: 'incorrecta' });
  const locked = await c.post('/api/admin/auth/login', { email: u.email, password: 'incorrecta' });
  assert.equal(locked.status, 401);
  const evenGood = await c.post('/api/admin/auth/login', { email: u.email, password: PASSWORD });
  assert.equal(evenGood.status, 429, 'bloqueada aunque la contraseña sea correcta');
  h.hub.db.run('UPDATE users SET locked_until = NULL, failed_logins = 0');
  // 2FA
  const c2 = new Client(h.base);
  assert.equal((await c2.post('/api/admin/auth/login', { email: u.email, password: PASSWORD })).json.stage, 'codigo');
  assert.equal((await c2.post('/api/admin/auth/totp', { code: '123456' })).status, 400);
  const enroll = h.hub.auth.finishEnrollment.bind(h.hub.auth);
  void enroll;
  const ok = await c2.post('/api/admin/auth/totp', { code: code(h.hub, u) });
  assert.equal(ok.status, 200); assert.equal(ok.json.stage, 'listo');
  // códigos de respaldo
  await sudo(h, c2, u);
  const rc = await c2.post('/api/admin/auth/recovery-codes');
  const c3 = new Client(h.base);
  await c3.post('/api/admin/auth/login', { email: u.email, password: PASSWORD });
  assert.equal((await c3.post('/api/admin/auth/totp', { code: rc.json.recoveryCodes[0] })).status, 200);
  const c4 = new Client(h.base);
  await c4.post('/api/admin/auth/login', { email: u.email, password: PASSWORD });
  assert.equal((await c4.post('/api/admin/auth/totp', { code: rc.json.recoveryCodes[0] })).status, 400, 'el código de respaldo no se reutiliza');
});

test('CSRF, cookie segura, cierre de sesión y sesión vencida', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const u = await makeUser(h.hub);
  const c = await login(h, u);
  const csrf = c.csrf; c.csrf = null;
  const noToken = await c.post('/api/admin/clients', {});
  assert.equal(noToken.status, 403); assert.equal(noToken.json.error, 'CSRF');
  c.csrf = csrf;
  const form = await c.req('POST', '/api/admin/products', 'code=X', { 'Content-Type': 'application/x-www-form-urlencoded' });
  assert.equal(form.status, 415, 'no acepta formularios (solo JSON)');
  const evil = await c.post('/api/admin/products', { code: 'XX', name: 'x', kind: 'saas' }, { Origin: 'https://atacante.com' });
  assert.equal(evil.status, 403, 'origen distinto bloqueado');
  // sesión expirada por inactividad
  h.hub.db.run("UPDATE sessions SET last_seen_at = '2020-01-01T00:00:00.000Z'");
  assert.equal((await c.get('/api/admin/dashboard')).status, 401);
  const c2 = await login(h, u);
  await c2.post('/api/admin/auth/logout');
  assert.equal((await c2.get('/api/admin/dashboard')).status, 401);
});

test('el cookie de sesión en producción es __Host-, Secure, HttpOnly y SameSite=Strict', async (t) => {
  const h = await startHub({ dev: false, env: { PUBLIC_URL: 'https://hub.solvex.pe' } }); t.after(h.stop);
  const u = await makeUser(h.hub);
  const res = await fetch(h.base + '/api/admin/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: u.email, password: PASSWORD }) });
  const ck = res.headers.getSetCookie()[0];
  assert.match(ck, /^__Host-slx_sid=/); assert.match(ck, /HttpOnly/); assert.match(ck, /Secure/); assert.match(ck, /SameSite=Strict/);
  assert.match(res.headers.get('strict-transport-security'), /max-age=63072000/);
  assert.match(res.headers.get('content-security-policy'), /default-src 'none'/);
});

test('permisos por rol y acciones que exigen confirmación (sudo)', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const owner = await makeUser(h.hub);
  const reader = await makeUser(h.hub, { email: 'lectura@solvex.pe', name: 'Lector', role: 'lectura' });
  const cr = await login(h, reader);
  assert.equal((await cr.get('/api/admin/clients')).status, 200);
  assert.equal((await cr.post('/api/admin/clients', { display_name: 'X' })).status, 403);
  assert.equal((await cr.get('/api/admin/audit')).status, 403);
  const co = await login(h, owner);
  h.hub.db.run('UPDATE sessions SET sudo_until = NULL');
  const r = await co.post('/api/admin/team', { email: 'otro@solvex.pe', name: 'Otro', role: 'soporte' });
  assert.equal(r.status, 403); assert.equal(r.json.needSudo, true);
  await sudo(h, co, owner);
  const ok = await co.post('/api/admin/team', { email: 'otro@solvex.pe', name: 'Otro', role: 'soporte' });
  assert.equal(ok.status, 201); assert.ok(ok.json.tempPassword);
  // no se puede quitar el último propietario
  const last = await co.put('/api/admin/team/' + owner.id, { role: 'administrador', active: true, name: 'Dueño' });
  assert.equal(last.status, 409);
});

test('límite de intentos de login por IP', async (t) => {
  const h = await startHub(); t.after(h.stop);
  const c = new Client(h.base);
  let last;
  for (let i = 0; i < 11; i++) last = await c.post('/api/admin/auth/login', { email: `x${i}@x.pe`, password: 'x' });
  assert.equal(last.status, 429);
});
