import { createHmac, createPublicKey, timingSafeEqual, verify as edVerify } from "node:crypto";

/**
 * Cliente de licencias de Solvex Hub para FacturaVoz (producto en la nube, multi-empresa).
 * Es el mismo algoritmo que el cliente oficial del Hub (integraciones/node/solvex-license.js), con tipos:
 *   verifyToken()   → firma Ed25519, alg/typ, emisor, audiencia (esta instancia), nbf/exp con ±2 min.
 *   verifyWebhook() → HMAC-SHA256 del CUERPO CRUDO con el secreto de la instancia, rechaza > 5 min (anti-reproducción).
 *   effectiveMode() → si el token anunció un corte que ya pasó, "restricted" aunque no llegue nada.
 * La clave de la instancia y el secreto del webhook viven SOLO en variables de entorno del servidor.
 */

export type LicensePayload = {
  iss: string;
  aud?: string;
  sub?: string;
  jti?: string;
  iat: number;
  nbf?: number;
  exp: number;
  lic?: string;
  tenant?: string | null;
  product?: string;
  plan?: string;
  status?: string;
  mode?: "full" | "warning" | "restricted" | "blocked";
  suspension?: string | null;
  auto_cut?: boolean;
  period_end?: string | null;
  grace_end?: string | null;
  cut_at?: string | null;
  features?: Record<string, boolean | number>;
  message?: string | null;
  pay_url?: string | null;
};

const SPKI_ED25519_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
const b64u = (s: string) => Buffer.from(s, "base64url");

export class LicenseError extends Error {}

/** keys: llaves públicas Ed25519 en base64 crudo (32 bytes), como las muestra el Hub (raw_b64). */
export function verifyToken(
  token: string,
  keys: string[],
  { audience = null, clockSkewSec = 120, now = Date.now() }: { audience?: string | null; clockSkewSec?: number; now?: number } = {},
): LicensePayload {
  const [h, p, s] = String(token || "").split(".");
  if (!h || !p || !s) throw new LicenseError("token mal formado");
  let header: { alg?: string; typ?: string };
  let payload: LicensePayload;
  try {
    header = JSON.parse(b64u(h).toString("utf8"));
    payload = JSON.parse(b64u(p).toString("utf8"));
  } catch {
    throw new LicenseError("token ilegible");
  }
  if (header.alg !== "EdDSA" || header.typ !== "slx-license+jwt") throw new LicenseError("algoritmo no permitido");
  const ok = keys.some((k) => {
    try {
      const raw = Buffer.from(k, "base64");
      if (raw.length !== 32) return false;
      const key = createPublicKey({ key: Buffer.concat([SPKI_ED25519_PREFIX, raw]), format: "der", type: "spki" });
      return edVerify(null, Buffer.from(`${h}.${p}`), key, b64u(s));
    } catch {
      return false;
    }
  });
  if (!ok) throw new LicenseError("firma inválida");
  const t = Math.floor(now / 1000);
  if (payload.iss !== "solvex-hub") throw new LicenseError("emisor inválido");
  if (audience && payload.aud !== audience) throw new LicenseError("el token no es para esta instancia");
  if (typeof payload.nbf === "number" && t + clockSkewSec < payload.nbf) throw new LicenseError("token aún no válido");
  if (typeof payload.exp !== "number" || t - clockSkewSec > payload.exp) throw new LicenseError("token vencido");
  return payload;
}

/** Verifica un webhook del Hub. rawBody: el cuerpo EXACTO recibido (sin volver a serializar). */
export function verifyWebhook({
  secret,
  timestamp,
  signature,
  rawBody,
  toleranceSec = 300,
  now = Date.now(),
}: {
  secret: string;
  timestamp: string | null;
  signature: string | null;
  rawBody: string;
  toleranceSec?: number;
  now?: number;
}): boolean {
  const ts = Number(timestamp);
  if (!secret || !Number.isInteger(ts) || Math.abs(now / 1000 - ts) > toleranceSec) return false;
  const want = Buffer.from("v1=" + createHmac("sha256", secret).update(`${ts}.${rawBody}`).digest("hex"));
  const got = Buffer.from(String(signature ?? ""));
  return want.length === got.length && timingSafeEqual(want, got);
}

/** Modo efectivo AHORA (corta sin conexión si el token anunció un corte que ya pasó). */
export function effectiveMode(payload: LicensePayload | null, now = Date.now()): "full" | "warning" | "restricted" | "blocked" {
  if (!payload || !payload.mode) return "blocked";
  const cut = payload.auto_cut ? payload.cut_at || payload.grace_end : null;
  if ((payload.mode === "full" || payload.mode === "warning") && cut && now > Date.parse(cut)) return "restricted";
  return payload.mode;
}

// ───────────────────────── Configuración y llamadas al Hub ─────────────────────────

export type HubConfig = { url: string; apiKey: string; instanceId: string; webhookSecret: string; keys: string[] };

/** null = Hub no configurado → la app funciona en "modo desarrollo" (licencia simulada, claramente marcada). */
export function hubConfig(): HubConfig | null {
  const url = (process.env.SOLVEX_HUB_URL ?? "").trim().replace(/\/+$/, "");
  const apiKey = (process.env.SOLVEX_API_KEY ?? "").trim();
  const instanceId = (process.env.SOLVEX_INSTANCE_ID ?? "").trim();
  if (!url || !apiKey || !instanceId) return null;
  if (!/^https:\/\//.test(url) && !(process.env.NODE_ENV !== "production" && /^http:\/\/(localhost|127\.0\.0\.1)/.test(url))) return null;
  if (!/^slxk_[a-z0-9]{8}_[A-Za-z0-9_-]{40,60}$/.test(apiKey) || !/^ins_[a-z0-9]{20}$/.test(instanceId)) return null;
  const keys = (process.env.SOLVEX_PUBLIC_KEYS ?? "")
    .split(",")
    .map((k) => k.trim())
    .filter((k) => /^[A-Za-z0-9+/]{43}=$/.test(k));
  return { url, apiKey, instanceId, webhookSecret: (process.env.SOLVEX_WEBHOOK_SECRET ?? "").trim(), keys };
}

let keyCache: { at: number; keys: string[] } | null = null;

/** Llaves públicas: las de SOLVEX_PUBLIC_KEYS (recomendado) o, si faltan, las publicadas por el Hub (HTTPS, caché 1 h). */
export async function publicKeys(cfg: HubConfig): Promise<string[]> {
  if (cfg.keys.length) return cfg.keys;
  if (keyCache && Date.now() - keyCache.at < 3600_000) return keyCache.keys;
  const r = await fetch(`${cfg.url}/.well-known/solvex-license-keys.json`, { signal: AbortSignal.timeout(10_000), cache: "no-store" });
  if (!r.ok) throw new LicenseError(`No se pudieron leer las llaves del Hub (HTTP ${r.status})`);
  const j = (await r.json()) as { issuer?: string; keys?: { raw_b64?: string }[] };
  if (j.issuer !== "solvex-hub") throw new LicenseError("Respuesta de llaves no válida");
  const keys = (j.keys ?? []).map((k) => k.raw_b64 ?? "").filter((k) => /^[A-Za-z0-9+/]{43}=$/.test(k));
  if (!keys.length) throw new LicenseError("El Hub no publicó llaves");
  keyCache = { at: Date.now(), keys };
  return keys;
}

async function hubCall(cfg: HubConfig, path: string, init: { method?: string; body?: unknown } = {}) {
  const r = await fetch(cfg.url + path, {
    method: init.method ?? "GET",
    headers: { Authorization: `Bearer ${cfg.apiKey}`, ...(init.body ? { "Content-Type": "application/json" } : {}) },
    body: init.body ? JSON.stringify(init.body) : undefined,
    signal: AbortSignal.timeout(15_000),
    cache: "no-store",
  });
  let json: Record<string, unknown> | null = null;
  try {
    json = (await r.json()) as Record<string, unknown>;
  } catch {
    json = null;
  }
  return { status: r.status, json };
}

export type TenantToken = { tenant: string; token: string; payload: LicensePayload };

/** Todas las licencias de la instancia (sincronización periódica para tolerar webhooks perdidos). */
export async function syncAll(cfg: HubConfig): Promise<{ ok: TenantToken[]; bad: number }> {
  const { status, json } = await hubCall(cfg, "/v1/instance/licenses");
  if (status !== 200 || !json) throw new LicenseError(`Hub HTTP ${status}`);
  const keys = await publicKeys(cfg);
  const ok: TenantToken[] = [];
  let bad = 0;
  for (const x of (json.licenses as { tenant_ref: string; token: string }[]) ?? []) {
    try {
      const payload = verifyToken(x.token, keys, { audience: cfg.instanceId });
      if (payload.tenant !== x.tenant_ref) throw new LicenseError("tenant no coincide");
      ok.push({ tenant: x.tenant_ref, token: x.token, payload });
    } catch {
      bad++;
    }
  }
  return { ok, bad };
}

/** Prueba gratis de 3 días (una por RUC). 409 PRUEBA_USADA si ese RUC ya la usó. */
export async function requestTrial(
  cfg: HubConfig,
  t: { tenant: string; ruc: string; businessName: string; email?: string | null },
): Promise<{ status: "ok"; data: TenantToken } | { status: "used" | "error"; message: string }> {
  const { status, json } = await hubCall(cfg, "/v1/instance/trials", {
    method: "POST",
    body: {
      tenant_ref: t.tenant,
      doc_type: t.ruc.length === 8 ? "DNI" : "RUC",
      doc_number: t.ruc,
      business_name: t.businessName.slice(0, 120),
      ...(t.email ? { email: t.email } : {}),
    },
  });
  if ((status === 200 || status === 201) && json && typeof json.token === "string") {
    const payload = verifyToken(json.token, await publicKeys(cfg), { audience: cfg.instanceId });
    if (payload.tenant !== t.tenant) return { status: "error", message: "tenant no coincide" };
    return { status: "ok", data: { tenant: t.tenant, token: json.token, payload } };
  }
  const message = (json?.message as string) || `Hub HTTP ${status}`;
  if (status === 409 && json?.error === "PRUEBA_USADA") return { status: "used", message };
  return { status: "error", message };
}

export async function heartbeat(cfg: HubConfig, tenants: number): Promise<void> {
  await hubCall(cfg, "/v1/instance/heartbeat", { method: "POST", body: { version: "facturavoz-2.0", tenants } }).catch(() => undefined);
}

/** tenant_ref = id de la organización (uuid). */
export const isOrgId = (s: unknown): s is string => typeof s === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
