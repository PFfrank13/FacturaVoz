import { readFileSync, writeFileSync } from 'node:fs';

const production = 'https://factura-voz-two.vercel.app';
const placeholders = {
  SUPABASE_URL: 'https://fv-config-project.invalid',
  SUPABASE_ANON_KEY: 'sb_publishable_FVBUILDKEY0000',
  API_BASE_URL: 'https://fv-config-api.invalid',
};

function origin(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password ||
      url.search || url.hash || url.pathname !== '/') {
    throw new Error('La configuración del cliente requiere orígenes HTTPS.');
  }
  return url.origin;
}

function isPublicKey(key, project) {
  if (/^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(key)) return true;
  if (!/^[\w-]+\.[\w-]+\.[\w-]+$/.test(key)) return false;
  try {
    const { role, ref } = JSON.parse(Buffer.from(key.split('.')[1], 'base64url'));
    const host = new URL(project).hostname;
    return role === 'anon' && (!ref || !host.endsWith('.supabase.co') || host === ref + '.supabase.co');
  } catch {
    return false;
  }
}

function configuration() {
  let project = process.env.NEXT_PUBLIC_SUPABASE_URL;
  let key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  let api = process.env.PUBLIC_BASE_URL || production;
  if (!project && !key && process.env.VERCEL_ENV === 'preview') {
    console.log('Vista previa sin conexión: las variables públicas de Supabase no están configuradas.');
    project = 'https://preview-data.invalid';
    key = 'sb_publishable_OFFLINEPREVIEW0000';
    api = 'https://preview-api.invalid';
  }
  if (!project || !key) {
    throw new Error('Configura NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_ANON_KEY para el cliente web.');
  }
  project = origin(project);
  if (!isPublicKey(key || '', project)) throw new Error('Se requiere una clave pública Supabase del mismo proyecto.');
  return { SUPABASE_URL: project, SUPABASE_ANON_KEY: key, API_BASE_URL: origin(api) };
}

const [action, file, config] = process.argv.slice(2);
if (action === 'config') {
  writeFileSync(file, JSON.stringify(configuration()), { mode: 0o600 });
} else if (action === 'verify' || action === 'bind') {
  let js = readFileSync(file, 'utf8');
  const values = action === 'bind' ? JSON.parse(readFileSync(config, 'utf8')) : null;
  for (const [name, marker] of Object.entries(placeholders)) {
    if (!js.includes(marker)) throw new Error('El artefacto no contiene el marcador de ' + name);
    if (values) js = js.replaceAll(marker, () => values[name]);
  }
  if (values) writeFileSync(file, js);
} else {
  throw new Error('Acción de configuración Flutter desconocida.');
}
