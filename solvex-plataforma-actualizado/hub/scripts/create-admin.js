'use strict';
/**
 * Crea un usuario del equipo con contraseña temporal. Al entrar por primera vez debe cambiarla
 * y activar el doble factor (app autenticadora).
 *   npm run crear-admin -- correo@solvex.pe "Nombre Apellido" [rol]
 */
const crypto = require('node:crypto');
const { boot } = require('./_boot');
const { ROLES } = require('../src/services/auth');
const C = require('../src/lib/crypto');

(async () => {
  const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  const [email, name, role = 'propietario'] = args;
  if (!email || !name || !ROLES[role]) {
    console.log('Uso: npm run crear-admin -- correo@solvex.pe "Nombre Apellido" [' + Object.keys(ROLES).join('|') + ']');
    process.exit(1);
  }
  const hub = boot();
  if (hub.db.get('SELECT 1 FROM users WHERE email = ?', email.toLowerCase())) { console.error('Ya existe ese usuario.'); process.exit(1); }
  const temp = C.randomCode(4) + '-' + C.randomCode(4) + '-' + C.randomCode(4) + '-' + C.randomCode(4);
  await hub.auth.createUser({ email, name, role, password: temp }, { type: 'sistema', label: 'consola del servidor' });
  console.log(`\nUsuario creado: ${email} (${ROLES[role].label})`);
  console.log(`Contraseña temporal: ${temp}`);
  console.log(`Entra a ${hub.config.publicUrl}/panel/ — te pedirá cambiarla y activar el doble factor.\n`);
  void crypto;
  hub.shutdown();
})();
