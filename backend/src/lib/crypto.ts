import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

/**
 * Cifrado AES-256-GCM para secretos de terceros (token de Mercado Pago de cada empresa).
 * La clave (SECRETS_KEY, 32 bytes en base64) vive solo en Vercel; en la base de datos solo queda el texto cifrado.
 * Formato: v1.<iv>.<tag>.<datos> (base64url).
 */
function key(b64: string | undefined): Buffer {
  const k = Buffer.from(b64 ?? "", "base64");
  if (k.length !== 32) throw new Error("SECRETS_KEY debe ser 32 bytes en base64 (openssl rand -base64 32)");
  return k;
}

export function seal(plain: string, keyB64 = process.env.SECRETS_KEY): string {
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", key(keyB64), iv);
  const data = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  return ["v1", iv.toString("base64url"), c.getAuthTag().toString("base64url"), data.toString("base64url")].join(".");
}

export function unseal(sealed: string, keyB64 = process.env.SECRETS_KEY): string {
  const [v, iv, tag, data] = sealed.split(".");
  if (v !== "v1" || !iv || !tag || data === undefined) throw new Error("Secreto con formato no válido");
  const d = createDecipheriv("aes-256-gcm", key(keyB64), Buffer.from(iv, "base64url"));
  d.setAuthTag(Buffer.from(tag, "base64url"));
  return Buffer.concat([d.update(Buffer.from(data, "base64url")), d.final()]).toString("utf8");
}

export const hasSecretsKey = () => {
  try {
    key(process.env.SECRETS_KEY);
    return true;
  } catch {
    return false;
  }
};
