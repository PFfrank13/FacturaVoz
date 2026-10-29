'use strict';
/**
 * Genera el archivo .env con todos los secretos (una sola vez).
 *   npm run setup
 * NUNCA lo vuelvas a generar en un servidor con datos: si cambias DATA_KEYS o BACKUP_KEY pierdes
 * acceso a la información cifrada. Guarda una copia de .env en un gestor de contraseñas.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const jws = require('../src/lib/jws');

const file = path.join(__dirname, '..', '.env');
if (fs.existsSync(file) && !process.argv.includes('--force')) {
  console.error('Ya existe .env. No se sobrescribe para no perder tus llaves. (Si de verdad quieres empezar de cero: npm run setup -- --force)');
  process.exit(1);
}
const r = () => crypto.randomBytes(32).toString('base64');
const kp = jws.generateKeyPair();
const kid = jws.kidOf(kp.publicPem);
const env = `# ===== Solvex Hub · generado el ${new Date().toISOString()} =====
# GUARDA UNA COPIA DE ESTE ARCHIVO EN UN GESTOR DE CONTRASEÑAS (1Password, Bitwarden).
# Si pierdes DATA_KEYS no se pueden leer los datos cifrados. Si pierdes BACKUP_KEY no se pueden abrir los respaldos.
# Nunca lo subas a Git.

NODE_ENV=production
HOST=127.0.0.1
PORT=8080
# Dirección pública del Hub (con https). Ej: https://hub.solvex.pe
PUBLIC_URL=https://hub.solvex.pe
# Cantidad de proxies delante (Nginx/Caddy = 1; Cloudflare + Nginx = 2)
TRUST_PROXY=1
DB_PATH=./data/hub.db
DEFAULT_TIMEZONE=America/Lima
COMPANY_NAME=Solvex
SUPPORT_EMAIL=
SUPPORT_WHATSAPP=

# Orígenes del sitio web que pueden enviar el formulario (separados por coma)
SITE_ORIGINS=https://solvex.pe,https://www.solvex.pe
# Opcional: IPs o rangos que pueden abrir el panel (vacío = cualquiera; recomendado usar Cloudflare Access)
ADMIN_ALLOWED_IPS=

# ---- Llaves (32 bytes en base64). NO las cambies después de empezar a usar el Hub ----
DATA_KEYS=k1:${r()}
DATA_KEY_ACTIVE=k1
BIDX_KEY=${r()}
AUDIT_KEY=${r()}
BACKUP_KEY=${r()}

# ---- Firma de licencias (Ed25519). La clave pública (kid ${kid}) va en cada producto ----
LICENSE_SIGNING_KEY=${Buffer.from(kp.privatePem).toString('base64')}
TOKEN_TTL_HOURS=72

# ---- Culqi (empieza con llaves de PRUEBA) ----
CULQI_PUBLIC_KEY=
CULQI_SECRET_KEY=
# Registra en Culqi el webhook:  PUBLIC_URL/webhooks/culqi/<CULQI_WEBHOOK_SECRET>
CULQI_WEBHOOK_SECRET=${crypto.randomBytes(24).toString('hex')}

# ---- Comprobantes electrónicos (boleta/factura): none | nubefact ----
# Ruta y token: panel de Nubefact → API (Integración). Empieza con la ruta y token de DEMO.
EINVOICE_PROVIDER=none
NUBEFACT_URL=
NUBEFACT_TOKEN=

# ---- Merchant of Record (opcional) ----
# Webhook: PUBLIC_URL/webhooks/mor/paddle  o  PUBLIC_URL/webhooks/mor/lemonsqueezy
PADDLE_WEBHOOK_SECRET=
LEMONSQUEEZY_WEBHOOK_SECRET=

# ---- Correo (resend | brevo | log) ----
EMAIL_PROVIDER=log
EMAIL_API_KEY=
EMAIL_FROM="Solvex <cobros@solvex.pe>"

# ---- WhatsApp Cloud API (plantillas aprobadas por Meta) ----
WA_TOKEN=
WA_PHONE_ID=
WA_API_VERSION=v21.0
WA_LANG=es

# ---- Cloudflare Turnstile (anti-robots del formulario, opcional) ----
TURNSTILE_SECRET=
`;
fs.writeFileSync(file, env, { mode: 0o600 });
console.log('Listo: .env creado con secretos nuevos (permisos 600).');
console.log('\nClave PÚBLICA de licencias (kid ' + kid + ') — cópiala en cada producto:\n');
console.log(kp.publicPem);
console.log('Formato para PHP/libsodium (SOLVEX_PUBLIC_KEY):', jws.rawPublicKeyB64(kp.publicPem));
console.log('\nSiguiente paso: edita PUBLIC_URL y los datos de Culqi/correo en .env, luego:  npm run crear-admin');
