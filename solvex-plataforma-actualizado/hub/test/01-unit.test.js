'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const C = require('../src/lib/crypto');
const T = require('../src/lib/time');
const totp = require('../src/lib/totp');
const jws = require('../src/lib/jws');
const v = require('../src/lib/validate');
const { effective, graceEndOf } = require('../src/services/licenses');
const { addBusinessDays } = require('../src/routes/public');

test('cifrado de campos: ida y vuelta, AAD y manipulación', () => {
  const vault = new C.Vault({ keys: { k1: crypto.randomBytes(32) }, active: 'k1', bidxKey: crypto.randomBytes(32) });
  const enc = vault.encrypt('20100047218', 'clients.doc_number:cli_1');
  assert.notEqual(enc, '20100047218');
  assert.equal(vault.decrypt(enc, 'clients.doc_number:cli_1'), '20100047218');
  assert.throws(() => vault.decrypt(enc, 'clients.doc_number:cli_2'), 'otra fila no puede descifrarlo');
  const parts = enc.split('.'); parts[3] = Buffer.from('x' + Buffer.from(parts[3], 'base64url').toString('latin1').slice(1), 'latin1').toString('base64url');
  assert.throws(() => vault.decrypt(parts.join('.'), 'clients.doc_number:cli_1'), 'manipulado');
  assert.notEqual(vault.encrypt('a', 'x'), vault.encrypt('a', 'x'), 'IV aleatorio');
  assert.equal(vault.bidx('doc', 'ABC'), vault.bidx('doc', 'abc'));
});

test('rotación de llave: lo viejo se lee, lo nuevo usa la llave activa', () => {
  const k1 = crypto.randomBytes(32), k2 = crypto.randomBytes(32), b = crypto.randomBytes(32);
  const old = new C.Vault({ keys: { k1 }, active: 'k1', bidxKey: b }).encrypt('hola', 'a');
  const nv = new C.Vault({ keys: { k1, k2 }, active: 'k2', bidxKey: b });
  assert.equal(nv.decrypt(old, 'a'), 'hola');
  assert.equal(nv.keyIdOf(nv.encrypt('x', 'a')), 'k2');
});

test('contraseñas scrypt', async () => {
  const h = await C.hashPassword('una frase larga y segura');
  assert.ok(h.startsWith('scrypt$'));
  assert.equal(await C.verifyPassword('una frase larga y segura', h), true);
  assert.equal(await C.verifyPassword('otra', h), false);
});

test('códigos aleatorios sin caracteres ambiguos', () => {
  const s = C.randomCode(500);
  assert.ok(!/[01OIL]/.test(s));
  assert.equal(new Set(Array.from({ length: 200 }, () => C.newId('x'))).size, 200);
});

test('TOTP: vector RFC y anti-repetición', () => {
  assert.equal(totp.hotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', 1), '287082');
  const s = totp.generateSecret(), now = Date.now(), c = totp.hotp(s, totp.counterAt(now));
  const ctr = totp.verify(s, c, { now });
  assert.ok(ctr > 0);
  assert.equal(totp.verify(s, c, { now, lastCounter: ctr }), -1, 'el mismo código no sirve dos veces');
  assert.equal(totp.verify(s, '000000', { now }) < 0 || totp.hotp(s, totp.counterAt(now)) === '000000', true);
});

test('zona horaria: fin de día en Lima', () => {
  assert.equal(T.endOfLocalDay('2026-11-18', 'America/Lima'), '2026-11-19T04:59:59.999Z');
  assert.equal(T.localDate('2026-11-19T04:59:59Z', 'America/Lima'), '2026-11-18');
  assert.equal(T.lastCoveredDay('2026-10-19', 'month', 1, 1), '2026-11-18');
  assert.equal(T.lastCoveredDay('2026-01-31', 'month', 1, 1, 31), '2026-02-27');
  assert.equal(T.nextBoundary('2026-02-28', 'month', 1, 31), '2026-03-31', 'vuelve al día ancla');
  assert.equal(T.lastCoveredDay('2026-10-19', 'year', 1, 1), '2027-10-18');
});

test('días hábiles del Libro de Reclamaciones', () => {
  assert.equal(addBusinessDays('2026-10-16', 1), '2026-10-19'); // viernes + 1 hábil = lunes
  assert.equal(addBusinessDays('2026-10-19', 15), '2026-11-09');
});

test('tokens Ed25519: firma, manipulación, vencimiento, llave desconocida', () => {
  const kp = jws.generateKeyPair(), key = jws.loadPrivateKey(Buffer.from(kp.privatePem).toString('base64')), kid = jws.kidOf(kp.publicPem);
  const now = Math.floor(Date.now() / 1000);
  const tok = jws.sign(key, kid, { iss: 'solvex-hub', status: 'activa', exp: now + 60, nbf: now - 1 });
  assert.equal(jws.verify(tok, { [kid]: kp.publicPem }).status, 'activa');
  const [h, p, s] = tok.split('.');
  const forged = h + '.' + Buffer.from(JSON.stringify({ iss: 'solvex-hub', status: 'activa', exp: now + 9e6 })).toString('base64url') + '.' + s;
  assert.throws(() => jws.verify(forged, { [kid]: kp.publicPem }), /firma/);
  assert.throws(() => jws.verify(jws.sign(key, kid, { iss: 'solvex-hub', exp: now - 1000 }), { [kid]: kp.publicPem }), /vencido/);
  assert.throws(() => jws.verify(tok, { otro: kp.publicPem }), /desconocida/);
  const other = jws.generateKeyPair();
  assert.throws(() => jws.verify(tok, { [kid]: other.publicPem }), /firma/);
  void p;
});

test('validación: RUC con dígito verificador, montos sin flotantes, campos de más se ignoran', () => {
  assert.equal(v.rucOk('20100047218'), true);
  assert.equal(v.rucOk('20100047219'), false);
  const r = v.parse({ amount: '0.1', role: 'propietario' }, { amount: v.money() });
  assert.deepEqual(r, { amount: 10 });
  assert.equal(v.parse({ a: '19.99' }, { a: v.money() }).a, 1999);
  assert.throws(() => v.parse({ a: '1e5' }, { a: v.money() }));
  assert.throws(() => v.parse({ u: 'javascript:alert(1)' }, { u: v.url() }));
  assert.throws(() => v.parse({ u: 'https://user:pass@x.com' }, { u: v.url() }));
  assert.equal(v.clean('hola‮evil'), 'holaevil', 'quita caracteres de control bidireccional');
});

test('estado efectivo de una licencia (función pura)', () => {
  const base = { status: 'activa', activated_at: 'x', timezone: 'America/Lima', grace_days: 5, auto_cut: 1, is_trial: 0, suspension_kind: null };
  const now = Date.parse('2026-10-19T15:00:00Z');
  const l = Object.assign({}, base, { period_end: '2026-10-20T04:59:59.999Z' });
  l.grace_end = graceEndOf(l);
  assert.equal(l.grace_end, '2026-10-25T04:59:59.999Z');
  assert.equal(effective(l, now).status, 'activa');
  assert.equal(effective(l, Date.parse('2026-10-21T00:00:00Z')).status, 'gracia');
  assert.equal(effective(l, Date.parse('2026-10-25T04:59:59Z')).status, 'gracia', 'último segundo de gracia en Lima');
  assert.equal(effective(l, Date.parse('2026-10-25T05:00:00Z')).status, 'suspendida');
  assert.equal(effective(Object.assign({}, l, { auto_cut: 0 }), Date.parse('2027-01-01T00:00:00Z')).status, 'gracia', 'sin corte automático');
  assert.equal(effective(Object.assign({}, l, { suspension_kind: 'manual' }), now).status, 'suspendida');
  assert.equal(effective(Object.assign({}, l, { activated_at: null }), now).status, 'pendiente');
  const trial = Object.assign({}, base, { is_trial: 1, period_end: '2026-10-20T04:59:59.999Z' }); trial.grace_end = graceEndOf(trial);
  assert.equal(effective(trial, Date.parse('2026-10-21T00:00:00Z')).status, 'suspendida', 'tras la prueba no hay gracia');
});
