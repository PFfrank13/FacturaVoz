'use strict';
/**
 * Equipo de Solvex: usuarios, contraseñas, doble factor (TOTP), sesiones y permisos.
 *
 * - Contraseña (scrypt) + código de app autenticadora OBLIGATORIO para todos.
 * - Bloqueo por cuenta tras 5 fallos (15 min, luego crece) y límite por IP en las rutas.
 * - Sesión en cookie HttpOnly + Secure + SameSite=Strict. En la base solo se guarda el hash del token.
 * - Caduca por inactividad (30 min) y por duración máxima (10 h).
 * - "Modo confirmación" (sudo): las acciones delicadas piden de nuevo el código 2FA (vale 10 min).
 */
const crypto = require('node:crypto');
const C = require('../lib/crypto');
const totp = require('../lib/totp');
const { nowIso } = require('../lib/time');
const { HttpError } = require('../http/app');

const ROLES = {
  propietario: { label: 'Propietario', perms: ['*'] },
  administrador: { label: 'Administrador', perms: ['dashboard.view', 'clients.view', 'clients.edit', 'clients.verify', 'clients.delete', 'clients.export', 'licenses.view', 'licenses.edit', 'licenses.suspend', 'licenses.keys', 'billing.view', 'payments.register', 'payments.approve', 'payments.reverse', 'invoices.manage', 'products.manage', 'instances.manage', 'leads.manage', 'tickets.manage', 'expenses.manage', 'complaints.manage', 'audit.view', 'settings.manage'] },
  finanzas: { label: 'Finanzas', perms: ['dashboard.view', 'clients.view', 'licenses.view', 'billing.view', 'payments.register', 'payments.approve', 'payments.reverse', 'invoices.manage', 'expenses.manage', 'audit.view'] },
  soporte: { label: 'Soporte', perms: ['dashboard.view', 'clients.view', 'licenses.view', 'billing.view', 'payments.register', 'tickets.manage', 'leads.manage', 'complaints.manage'] },
  implementacion: { label: 'Implementación', perms: ['dashboard.view', 'clients.view', 'clients.edit', 'licenses.view', 'licenses.edit', 'tickets.manage'] },
  lectura: { label: 'Solo lectura', perms: ['dashboard.view', 'clients.view', 'licenses.view', 'billing.view'] },
};
const ALL_PERMS = [...new Set(Object.values(ROLES).flatMap((r) => r.perms).filter((p) => p !== '*')), 'team.manage'];

function can(user, perm) {
  if (!user || !user.active) return false;
  const r = ROLES[user.role]; if (!r) return false;
  return r.perms.includes('*') || r.perms.includes(perm);
}
function permsOf(user) { const r = ROLES[user.role]; return r && r.perms.includes('*') ? ALL_PERMS : (r ? r.perms : []); }

const COMMON = new Set(['123456789012', 'contraseña123', 'password1234', 'qwertyuiop12', 'administrador', 'solvex123456', 'barberia1234', 'peru12345678', '1234567890ab', 'iloveyou1234', 'abcdefghijkl', 'aaaaaaaaaaaa', 'contrasena12', 'password123!', 'qwerty123456']);

function passwordProblem(pw, user = {}) {
  const s = String(pw || '');
  if (s.length < 12) return 'Usa al menos 12 caracteres (una frase de 3 o 4 palabras es ideal).';
  if (s.length > 200) return 'Máximo 200 caracteres.';
  const low = s.toLowerCase();
  if (COMMON.has(low)) return 'Esa contraseña es demasiado común.';
  if (/^(.)\1+$/.test(s) || /^(0123456789|1234567890|abcdefghij)/.test(low)) return 'Evita secuencias o caracteres repetidos.';
  if (/solvex|frank/.test(low)) return 'No uses el nombre de la empresa ni nombres del equipo.';
  const local = String(user.email || '').split('@')[0].toLowerCase();
  if (local.length >= 4 && low.includes(local)) return 'No uses tu correo dentro de la contraseña.';
  if (new Set(s).size < 6) return 'Usa más variedad de caracteres.';
  return '';
}

class Auth {
  constructor({ db, vault, audit, config }) {
    this.db = db; this.vault = vault; this.audit = audit; this.cfg = config;
    this.cookieName = config.production ? '__Host-slx_sid' : 'slx_sid';
  }

  publicUser(u) {
    return { id: u.id, email: u.email, name: u.name, role: u.role, roleLabel: ROLES[u.role]?.label, perms: permsOf(u), totpEnabled: !!u.totp_enabled, mustChangePassword: !!u.must_change_password, active: !!u.active, lastLoginAt: u.last_login_at, createdAt: u.created_at, lockedUntil: u.locked_until };
  }

  /* ---------------- usuarios ---------------- */
  async createUser({ email, name, role, password }, actor, ip) {
    if (!ROLES[role]) throw new HttpError(400, 'ROL', 'Rol no válido.');
    const prob = passwordProblem(password, { email });
    if (prob) throw new HttpError(400, 'CONTRASENA_DEBIL', prob);
    const id = C.newId('usr'), now = nowIso(), hash = await C.hashPassword(password);
    this.db.tx(() => {
      this.db.run(`INSERT INTO users (id,email,name,role,password_hash,must_change_password,created_at,updated_at,password_changed_at)
        VALUES (?,?,?,?,?,1,?,?,?)`, id, email.toLowerCase(), name, role, hash, now, now, now);
      this.audit.log({ actor, action: 'usuario.creado', entity: ['user', id], ip, data: { email: email.toLowerCase(), role } });
    });
    return this.db.get('SELECT * FROM users WHERE id = ?', id);
  }

  /* ---------------- inicio de sesión ---------------- */
  async login(email, password, ctx) {
    const u = this.db.get('SELECT * FROM users WHERE email = ?', String(email || '').toLowerCase().trim());
    const generic = new HttpError(401, 'CREDENCIALES', 'Correo o contraseña incorrectos.');
    if (!u) { await C.dummyVerify(password); this.audit.log({ actor: { type: 'publico', label: 'desconocido' }, action: 'login.fallido', ip: ctx.ip, data: { reason: 'usuario_inexistente' } }); throw generic; }
    if (u.locked_until && u.locked_until > nowIso()) {
      await C.dummyVerify(password);
      throw new HttpError(429, 'CUENTA_BLOQUEADA', 'Cuenta bloqueada temporalmente por intentos fallidos. Intenta más tarde.');
    }
    const ok = await C.verifyPassword(password, u.password_hash);
    if (!ok || !u.active) {
      const n = u.failed_logins + 1;
      const lock = n >= 5 ? new Date(Date.now() + Math.min(24 * 60, 15 * 2 ** (n - 5)) * 60000).toISOString() : null;
      this.db.run('UPDATE users SET failed_logins = ?, locked_until = COALESCE(?, locked_until), updated_at = ? WHERE id = ?', n, lock, nowIso(), u.id);
      this.audit.log({ actor: { type: 'publico', label: u.email }, action: lock ? 'login.bloqueo' : 'login.fallido', entity: ['user', u.id], ip: ctx.ip, data: { intentos: n, inactivo: !u.active || undefined } });
      throw generic;
    }
    this.db.run('UPDATE users SET failed_logins = 0, locked_until = NULL, updated_at = ? WHERE id = ?', nowIso(), u.id);
    const s = this.createSession(u, ctx, false);
    return { session: s, user: u, next: u.must_change_password ? 'cambiar_contrasena' : (u.totp_enabled ? 'codigo' : 'activar_2fa') };
  }

  createSession(u, ctx, mfaOk) {
    const token = C.newSecret(32), id = C.sha256(token), csrf = C.newSecret(18), now = Date.now();
    const exp = new Date(now + this.cfg.session.absoluteHours * 3600e3).toISOString();
    this.db.run(`INSERT INTO sessions (id,user_id,csrf,mfa_ok,ip,ua,created_at,last_seen_at,expires_at) VALUES (?,?,?,?,?,?,?,?,?)`,
      id, u.id, csrf, mfaOk ? 1 : 0, ctx.ip, String(ctx.header('user-agent')).slice(0, 200), nowIso(now), nowIso(now), exp);
    ctx.setCookie(this.cookieName, token, { maxAge: this.cfg.session.absoluteHours * 3600, secure: this.cfg.production });
    return { id, csrf, token };
  }

  /** Cambia el token de sesión (tras el 2FA) para evitar fijación de sesión. */
  rotateSession(ctx, patch = {}) {
    const old = ctx.state.session;
    const token = C.newSecret(32), id = C.sha256(token);
    this.db.tx(() => {
      this.db.run('UPDATE sessions SET revoked_at = ? WHERE id = ?', nowIso(), old.id);
      this.db.run(`INSERT INTO sessions (id,user_id,csrf,mfa_ok,sudo_until,ip,ua,created_at,last_seen_at,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?)`,
        id, old.user_id, C.newSecret(18), patch.mfa_ok ?? old.mfa_ok, patch.sudo_until ?? old.sudo_until, ctx.ip, old.ua, old.created_at, nowIso(), old.expires_at);
    });
    ctx.setCookie(this.cookieName, token, { maxAge: (Date.parse(old.expires_at) - Date.now()) / 1000, secure: this.cfg.production });
    const s = this.db.get('SELECT * FROM sessions WHERE id = ?', id);
    ctx.state.session = s;
    return s;
  }

  /** Lee la sesión de la cookie. Devuelve null si no hay o está vencida. */
  readSession(ctx) {
    const token = ctx.cookies[this.cookieName];
    if (!token || token.length > 100) return null;
    const s = this.db.get('SELECT * FROM sessions WHERE id = ?', C.sha256(token));
    if (!s || s.revoked_at) return null;
    const now = Date.now();
    if (Date.parse(s.expires_at) < now || Date.parse(s.last_seen_at) + this.cfg.session.idleMin * 60e3 < now) {
      this.db.run('UPDATE sessions SET revoked_at = ? WHERE id = ?', nowIso(), s.id);
      return null;
    }
    if (now - Date.parse(s.last_seen_at) > 30e3) this.db.run('UPDATE sessions SET last_seen_at = ? WHERE id = ?', nowIso(now), s.id);
    const u = this.db.get('SELECT * FROM users WHERE id = ?', s.user_id);
    if (!u || !u.active) return null;
    return { session: s, user: u };
  }

  logout(ctx) {
    if (ctx.state.session) this.db.run('UPDATE sessions SET revoked_at = ? WHERE id = ?', nowIso(), ctx.state.session.id);
    ctx.setCookie(this.cookieName, '', { maxAge: 0, secure: this.cfg.production });
  }

  revokeAllSessions(userId, exceptId = null) {
    this.db.run('UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL AND id IS NOT ?', nowIso(), userId, exceptId);
  }

  /* ---------------- 2FA ---------------- */
  startEnrollment(u) {
    if (u.totp_enabled) throw new HttpError(409, 'YA_ACTIVO', 'El doble factor ya está activo.');
    const secret = totp.generateSecret();
    this.db.run('UPDATE users SET totp_secret_enc = ?, totp_last_counter = -1, updated_at = ? WHERE id = ?', this.vault.encrypt(secret, 'users.totp:' + u.id), nowIso(), u.id);
    return { secret, otpauth: totp.otpauthUrl({ secret, account: u.email, issuer: this.cfg.company.name + ' Hub' }) };
  }

  /** Verifica un código TOTP del usuario (y lo marca como usado). */
  checkTotp(u, code) {
    if (!u.totp_secret_enc) return false;
    const secret = this.vault.decrypt(u.totp_secret_enc, 'users.totp:' + u.id);
    const ctr = totp.verify(secret, code, { lastCounter: u.totp_last_counter });
    if (ctr < 0) return false;
    // UPDATE condicional: si dos peticiones usan el mismo código a la vez, solo una gana.
    const r = this.db.run('UPDATE users SET totp_last_counter = ? WHERE id = ? AND totp_last_counter < ?', ctr, u.id, ctr);
    return r.changes === 1;
  }

  finishEnrollment(u, code) {
    if (!this.checkTotp(u, code)) return null;
    const codes = Array.from({ length: 8 }, () => C.randomCode(10));
    this.db.run('UPDATE users SET totp_enabled = 1, recovery_codes = ?, updated_at = ? WHERE id = ?', JSON.stringify(codes.map((c) => C.sha256(c))), nowIso(), u.id);
    return codes.map((c) => c.slice(0, 5) + '-' + c.slice(5));
  }

  useRecoveryCode(u, code) {
    const h = C.sha256(String(code || '').toUpperCase().replace(/[^A-Z0-9]/g, ''));
    const list = JSON.parse(u.recovery_codes || '[]');
    const i = list.indexOf(h); if (i < 0) return false;
    list.splice(i, 1);
    this.db.run('UPDATE users SET recovery_codes = ?, updated_at = ? WHERE id = ?', JSON.stringify(list), nowIso(), u.id);
    return true;
  }

  /** Fallos de código 2FA cuentan para el bloqueo igual que la contraseña. */
  totpFailed(u, ctx) {
    const n = u.failed_logins + 1;
    const lock = n >= 5 ? new Date(Date.now() + 15 * 60000).toISOString() : null;
    this.db.run('UPDATE users SET failed_logins = ?, locked_until = COALESCE(?, locked_until) WHERE id = ?', n, lock, u.id);
    this.audit.log({ actor: { type: 'usuario', id: u.id, label: u.name }, action: '2fa.fallido', entity: ['user', u.id], ip: ctx.ip, data: { intentos: n } });
    if (lock) { this.revokeAllSessions(u.id); throw new HttpError(429, 'CUENTA_BLOQUEADA', 'Demasiados códigos incorrectos. La cuenta quedó bloqueada 15 minutos.'); }
  }

  async changePassword(u, current, next, ctx) {
    if (!(await C.verifyPassword(current, u.password_hash))) throw new HttpError(400, 'CONTRASENA_ACTUAL', 'La contraseña actual no es correcta.');
    const prob = passwordProblem(next, u); if (prob) throw new HttpError(400, 'CONTRASENA_DEBIL', prob);
    if (await C.verifyPassword(next, u.password_hash)) throw new HttpError(400, 'CONTRASENA_IGUAL', 'La nueva contraseña debe ser distinta.');
    const hash = await C.hashPassword(next);
    this.db.tx(() => {
      this.db.run('UPDATE users SET password_hash = ?, must_change_password = 0, password_changed_at = ?, updated_at = ? WHERE id = ?', hash, nowIso(), nowIso(), u.id);
      this.revokeAllSessions(u.id, ctx.state.session ? ctx.state.session.id : null);
      this.audit.log({ actor: { type: 'usuario', id: u.id, label: u.name }, action: 'usuario.contrasena_cambiada', entity: ['user', u.id], ip: ctx.ip });
    });
  }

  markLogin(u, ctx) {
    this.db.run('UPDATE users SET last_login_at = ?, last_login_ip = ?, failed_logins = 0, locked_until = NULL WHERE id = ?', nowIso(), ctx.ip, u.id);
    this.audit.log({ actor: { type: 'usuario', id: u.id, label: u.name }, action: 'login.exitoso', entity: ['user', u.id], ip: ctx.ip });
  }

  activeOwners() { return this.db.get("SELECT COUNT(*) n FROM users WHERE role = 'propietario' AND active = 1").n; }
}

/* ---------------- middleware ---------------- */
function requireUser(auth, { mfa = true, perm = null, sudo = false } = {}) {
  return (ctx) => {
    if (!ctx.state.user) {
      const r = auth.readSession(ctx);
      if (!r) throw new HttpError(401, 'SIN_SESION', 'Inicia sesión.');
      ctx.state.session = r.session; ctx.state.user = r.user;
    }
    const { session, user } = ctx.state;
    if (mfa && (!session.mfa_ok || user.must_change_password || !user.totp_enabled)) throw new HttpError(401, 'FALTA_2FA', 'Completa la verificación en dos pasos.');
    // CSRF: toda petición que cambia algo debe traer el token de la sesión en una cabecera.
    if (!['GET', 'HEAD', 'OPTIONS'].includes(ctx.method)) {
      const t = ctx.header('x-csrf-token');
      if (!t || !C.safeEqual(t, session.csrf)) throw new HttpError(403, 'CSRF', 'Solicitud no válida. Recarga la página.');
    }
    if (perm && !can(user, perm)) throw new HttpError(403, 'SIN_PERMISO', 'Tu rol no permite esta acción.');
    if (sudo && !(session.sudo_until && session.sudo_until > nowIso())) throw new HttpError(403, 'CONFIRMAR', 'Confirma con tu código de verificación para continuar.', { needSudo: true });
  };
}

module.exports = { Auth, ROLES, ALL_PERMS, can, permsOf, passwordProblem, requireUser };
