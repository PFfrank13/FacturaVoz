// Cliente de Lycet (API REST sobre Greenter) desplegado en tu VPS.
// Producción: Caddy exige Basic Auth (LYCET_API_KEY) y añade internamente el token de Lycet.
// Desarrollo local: define LYCET_TOKEN para hablar directo con Lycet (?token=).

export class LycetError extends Error {
  constructor(message: string, readonly status = 0) {
    super(message);
  }
}

function endpoint(path: string): URL {
  const base = process.env.LYCET_URL;
  if (!base) throw new LycetError("Servicio de facturación no configurado");
  const u = new URL(path, base.endsWith("/") ? base : base + "/");
  if (u.protocol !== "https:" && !(process.env.NODE_ENV !== "production" && u.hostname === "localhost")) {
    throw new LycetError("LYCET_URL debe usar https");
  }
  if (process.env.LYCET_TOKEN) u.searchParams.set("token", process.env.LYCET_TOKEN);
  return u;
}

function authHeaders(): Record<string, string> {
  const key = process.env.LYCET_API_KEY;
  if (process.env.LYCET_TOKEN || !key) return {};
  return { Authorization: "Basic " + Buffer.from(`lycet:${key}`).toString("base64") };
}

async function call(method: string, path: string, body: unknown, timeoutMs: number, extraQuery?: Record<string, string>) {
  const url = endpoint(path);
  for (const [k, v] of Object.entries(extraQuery ?? {})) url.searchParams.set(k, v);
  let res: Response;
  try {
    res = await fetch(url, {
      method,
      headers: { ...authHeaders(), ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeoutMs),
      cache: "no-store",
    });
  } catch {
    throw new LycetError("No se pudo contactar al servicio de facturación");
  }
  const text = await res.text();
  let json: unknown = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    /* respuesta no JSON */
  }
  return { status: res.status, json: json as Record<string, unknown> | null };
}

export type SunatOutcome = {
  status: "accepted" | "rejected" | "error";
  code: string;
  message: string;
  hash?: string;
  xml?: string;
  cdr?: string;
};

type SendResponse = {
  xml?: string;
  hash?: string;
  sunatResponse?: {
    success?: boolean;
    cdrZip?: string;
    cdrResponse?: { id?: string; code?: string; description?: string; notes?: string[] };
    error?: { code?: string; message?: string };
  };
};

/** Interpreta la respuesta de SUNAT según los rangos oficiales de códigos. */
export function interpretSend(r: SendResponse | null): SunatOutcome {
  const s = r?.sunatResponse;
  if (!r || !s) return { status: "error", code: "LYCET", message: "Respuesta no válida del servicio de facturación" };
  if (s.success && s.cdrResponse) {
    const code = String(s.cdrResponse.code ?? "");
    const notes = (s.cdrResponse.notes ?? []).join(" | ");
    const description = s.cdrResponse.description ?? "";
    const n = Number(code);
    // 0 = aceptado; 4000+ = aceptado con observaciones; 2000-3999 = rechazado
    if (code === "0" || n >= 4000)
      return { status: "accepted", code, message: [description, notes].filter(Boolean).join(" — "), hash: r.hash, xml: r.xml, cdr: s.cdrZip };
    return { status: "rejected", code, message: description || notes, hash: r.hash, xml: r.xml, cdr: s.cdrZip };
  }
  const code = String(s.error?.code ?? "");
  const message = s.error?.message ?? "SUNAT no procesó el comprobante";
  const n = Number(code);
  if (Number.isFinite(n) && n >= 2000 && n < 4000) return { status: "rejected", code, message, hash: r.hash, xml: r.xml };
  // 0100-1999 (autenticación, servicio, ya registrado...) y errores de red: no es un rechazo del documento
  return { status: "error", code: code || "SUNAT", message, hash: r.hash, xml: r.xml };
}

export async function sendInvoice(payload: unknown): Promise<SunatOutcome> {
  const { status, json } = await call("POST", "api/v1/invoice/send", payload, 40_000);
  if (status === 400 || status === 422) {
    const detail = JSON.stringify(json ?? {}).slice(0, 400);
    return { status: "error", code: "VALIDACION", message: `Datos del comprobante no válidos: ${detail}` };
  }
  if (status >= 500 || status === 0) return { status: "error", code: "LYCET", message: "El servicio de facturación no respondió correctamente" };
  if (status === 401 || status === 403) return { status: "error", code: "LYCET_AUTH", message: "Credenciales del servicio de facturación inválidas" };
  return interpretSend(json as SendResponse);
}

export async function sendNote(payload: unknown): Promise<SunatOutcome> {
  const { status, json } = await call("POST", "api/v1/note/send", payload, 40_000);
  if (status === 400 || status === 422) {
    const detail = JSON.stringify(json ?? {}).slice(0, 400);
    return { status: "error", code: "VALIDACION", message: `Datos de la nota no válidos: ${detail}` };
  }
  if (status >= 500 || status === 0) return { status: "error", code: "LYCET", message: "El servicio de facturación no respondió correctamente" };
  if (status === 401 || status === 403) return { status: "error", code: "LYCET_AUTH", message: "Credenciales del servicio de facturación inválidas" };
  return interpretSend(json as SendResponse);
}

/** Consulta el CDR de un comprobante ya enviado (recupera un envío cuyo resultado se perdió). */
export async function statusCdr(ruc: string, tipo: string, serie: string, numero: string): Promise<SunatOutcome | null> {
  const { status, json } = await call("GET", "api/v1/invoice/status", null, 25_000, { ruc, tipo, serie, numero });
  if (status !== 200 || !json) return null;
  const j = json as { success?: boolean; cdrZip?: string; cdrResponse?: { code?: string; description?: string; notes?: string[] } };
  if (!j.success || !j.cdrResponse) return null;
  const code = String(j.cdrResponse.code ?? "");
  const n = Number(code);
  const message = [j.cdrResponse.description, (j.cdrResponse.notes ?? []).join(" | ")].filter(Boolean).join(" — ");
  if (code === "0" || n >= 4000) return { status: "accepted", code, message, cdr: j.cdrZip };
  return { status: "rejected", code, message, cdr: j.cdrZip };
}

export async function putCompany(ruc: string, body: Record<string, string>): Promise<void> {
  const { status } = await call("PUT", `api/v1/configuration/company/${ruc}`, body, 20_000);
  if (status !== 200) throw new LycetError("No se pudo registrar la empresa en el servicio de facturación", status);
}

export const FE_URL = {
  beta: "https://e-beta.sunat.gob.pe/ol-ti-itcpfegem-beta/billService",
  prod: "https://e-factura.sunat.gob.pe/ol-ti-itcpfegem/billService",
} as const;
