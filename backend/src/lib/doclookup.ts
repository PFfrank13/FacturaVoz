/**
 * Consulta de DNI (RENIEC) y RUC (SUNAT) por un proveedor peruano (sin datos inventados).
 *
 * Proveedor por defecto: APISPERU (https://dniruc.apisperu.com). El token va como parámetro "token" en la URL:
 *   DNI → https://dniruc.apisperu.com/api/v1/dni/{n}?token={token}
 *   RUC → https://dniruc.apisperu.com/api/v1/ruc/{n}?token={token}
 * Variables de entorno (solo servidor):
 *   DOC_API_TOKEN     token del proveedor (OBLIGATORIA; nunca se escribe en archivos ni en registros)
 *   DOC_API_DNI_URL   opcional: plantilla con {n} y, si el token va en la URL, {token}
 *   DOC_API_RUC_URL   opcional: igual para RUC
 * Si la plantilla NO tiene {token}, el token se envía como "Authorization: Bearer <token>" (otros proveedores).
 * Si falta el token o el proveedor falla, la app deja escribir los datos a mano (nunca bloquea la venta).
 */

export type DocKind = "dni" | "ruc";

export type DocResult = {
  kind: DocKind;
  number: string;
  name: string; // DNI: nombres y apellidos · RUC: razón social
  firstNames: string; // DNI
  lastNames: string; // DNI
  tradeName: string; // RUC: nombre comercial
  address: string;
  district: string;
  province: string;
  department: string;
  ubigeo: string;
  status: string; // RUC: ACTIVO / BAJA DE OFICIO / SUSPENSION TEMPORAL…
  condition: string; // RUC: HABIDO / NO HABIDO / NO HALLADO
  warning: string; // aviso en lenguaje simple si el RUC no está ACTIVO y HABIDO
  source: string;
};

export const DEFAULT_DNI_URL = "https://dniruc.apisperu.com/api/v1/dni/{n}?token={token}";
export const DEFAULT_RUC_URL = "https://dniruc.apisperu.com/api/v1/ruc/{n}?token={token}";

/** Dígito verificador del RUC (módulo 11). */
export function rucValid(ruc: string): boolean {
  if (!/^(10|15|16|17|20)\d{9}$/.test(ruc)) return false;
  const w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const sum = w.reduce((s, x, i) => s + x * Number(ruc[i]), 0);
  const r = 11 - (sum % 11);
  const dv = r === 10 ? 0 : r === 11 ? 1 : r;
  return dv === Number(ruc[10]);
}

export function kindOf(number: string): DocKind | null {
  if (/^\d{8}$/.test(number)) return "dni";
  if (/^\d{11}$/.test(number) && rucValid(number)) return "ruc";
  return null;
}

const s = (v: unknown) => (typeof v === "string" ? v.replace(/\s+/g, " ").trim() : typeof v === "number" ? String(v) : "");
const first = (o: Record<string, unknown>, keys: string[]) => {
  for (const k of keys) {
    const v = s(o[k]);
    if (v && v !== "-") return v;
  }
  return "";
};

/** Aviso antes de emitir: SUNAT no acepta bien facturas a RUC dados de baja o no habidos. */
export function rucWarning(status: string, condition: string): string {
  const st = status.toUpperCase();
  const co = condition.toUpperCase();
  if (st && st !== "ACTIVO") return `Ojo: este RUC figura como "${st}" en SUNAT. Confirma con tu cliente antes de emitirle una factura.`;
  if (co && co !== "HABIDO") return `Ojo: este RUC figura como "${co}" en SUNAT. Confirma la dirección con tu cliente antes de emitir.`;
  return "";
}

/** Convierte la respuesta del proveedor (APISPERU y otros formatos comunes) al formato de FacturaVoz. */
export function normalizeDoc(kind: DocKind, number: string, raw: unknown, source = "proveedor"): DocResult | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  let o = raw as Record<string, unknown>;
  if (o.success === false) return null;
  if (o.data && typeof o.data === "object" && !Array.isArray(o.data)) o = { ...o, ...(o.data as Record<string, unknown>) };
  let name = "";
  let firstNames = "";
  let lastNames = "";
  if (kind === "dni") {
    // Si el proveedor devuelve otro número, la respuesta no sirve (nunca se muestra el nombre de otra persona).
    const got = first(o, ["dni", "numero", "numeroDocumento", "document_number"]).replace(/\D/g, "");
    if (got && got !== number) return null;
    const full = first(o, ["full_name", "nombre_completo", "nombreCompleto", "nombre"]);
    firstNames = first(o, ["nombres", "first_name"]);
    const p1 = first(o, ["apellidoPaterno", "apellido_paterno", "first_last_name"]);
    const p2 = first(o, ["apellidoMaterno", "apellido_materno", "second_last_name"]);
    lastNames = `${p1} ${p2}`.trim();
    name = firstNames && lastNames ? `${firstNames} ${lastNames}` : full;
  } else {
    const got = first(o, ["ruc", "numeroDocumento", "numero"]).replace(/\D/g, "");
    if (got && got !== number) return null;
    name = first(o, ["razonSocial", "razon_social", "nombre_o_razon_social", "nombre", "name"]);
  }
  name = name.replace(/\s+/g, " ").toUpperCase().slice(0, 200);
  if (!name) return null;
  const status = kind === "ruc" ? first(o, ["estado", "estado_contribuyente", "status"]).toUpperCase().slice(0, 60) : "";
  const condition = kind === "ruc" ? first(o, ["condicion", "condicion_domicilio", "condition"]).toUpperCase().slice(0, 60) : "";
  return {
    kind,
    number,
    name,
    firstNames: firstNames.toUpperCase().slice(0, 120),
    lastNames: lastNames.toUpperCase().slice(0, 120),
    tradeName: kind === "ruc" ? first(o, ["nombreComercial", "nombre_comercial", "trade_name"]).replace(/^-$/, "").toUpperCase().slice(0, 200) : "",
    address: first(o, ["direccion", "direccion_completa", "domicilio_fiscal", "address"]).slice(0, 300),
    district: first(o, ["distrito", "district"]).slice(0, 80),
    province: first(o, ["provincia", "province"]).slice(0, 80),
    department: first(o, ["departamento", "department"]).slice(0, 80),
    ubigeo: first(o, ["ubigeo"]).replace(/\D/g, "").slice(0, 6),
    status,
    condition,
    warning: kind === "ruc" ? rucWarning(status, condition) : "",
    source,
  };
}

/** Plantilla → URL final. Devuelve también si el token viaja en la URL (para no repetirlo en cabeceras). */
export function providerUrl(kind: DocKind, number: string, token: string): { url: string; tokenInUrl: boolean } | null {
  const raw = ((kind === "dni" ? process.env.DOC_API_DNI_URL : process.env.DOC_API_RUC_URL) ?? "").trim();
  const tpl = raw || (kind === "dni" ? DEFAULT_DNI_URL : DEFAULT_RUC_URL);
  if (!/^https:\/\/[^\s]+\{n\}/.test(tpl)) return null;
  const tokenInUrl = tpl.includes("{token}");
  if (tokenInUrl && !token) return null;
  return { url: tpl.replace("{n}", encodeURIComponent(number)).replace("{token}", encodeURIComponent(token)), tokenInUrl };
}

/** Para registros y mensajes: NUNCA el token completo. */
export function maskUrl(url: string): string {
  return url.replace(/([?&](?:token|api_key|apikey|key)=)[^&#]*/gi, "$1***");
}

export type LookupFail = "not_configured" | "not_found" | "limit" | "error" | "auth";

export async function fetchDoc(kind: DocKind, number: string, fetchImpl: typeof fetch = fetch): Promise<{ ok: true; data: DocResult } | { ok: false; reason: LookupFail }> {
  const token = (process.env.DOC_API_TOKEN ?? "").trim();
  if (!token) return { ok: false, reason: "not_configured" };
  const p = providerUrl(kind, number, token);
  if (!p) return { ok: false, reason: "not_configured" };
  let res: Response;
  try {
    res = await fetchImpl(p.url, {
      headers: { Accept: "application/json", ...(p.tokenInUrl ? {} : { Authorization: `Bearer ${token}` }) },
      signal: AbortSignal.timeout(8_000),
      cache: "no-store",
    });
  } catch {
    return { ok: false, reason: "error" };
  }
  if (res.status === 401 || res.status === 403) {
    console.error("doclookup: proveedor rechazó el token", maskUrl(p.url).replace(/\d{8,11}/, "<doc>"));
    return { ok: false, reason: "auth" };
  }
  if (res.status === 404 || res.status === 422) return { ok: false, reason: "not_found" };
  if (res.status === 429 || res.status === 402) return { ok: false, reason: "limit" };
  if (!res.ok) return { ok: false, reason: "error" };
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { ok: false, reason: "error" };
  }
  const msg = body && typeof body === "object" ? s((body as Record<string, unknown>).message).toLowerCase() : "";
  if (/l[ií]mite|limit|exced|too many/.test(msg)) return { ok: false, reason: "limit" };
  if (/token/.test(msg) && /inv[aá]lid|expir|no autoriz/.test(msg)) return { ok: false, reason: "auth" };
  const data = normalizeDoc(kind, number, body, new URL(p.url).hostname);
  return data ? { ok: true, data } : { ok: false, reason: "not_found" };
}
