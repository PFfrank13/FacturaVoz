/**
 * Consulta de DNI (RENIEC) y RUC (SUNAT) a través de un proveedor peruano CONFIGURABLE (sin datos inventados).
 * Variables de entorno:
 *   DOC_API_DNI_URL   p. ej. https://api.decolecta.com/v1/reniec/dni?numero={n}
 *   DOC_API_RUC_URL   p. ej. https://api.decolecta.com/v1/sunat/ruc?numero={n}
 *   DOC_API_TOKEN     token del proveedor (se envía como "Authorization: Bearer <token>")
 * Si no están configuradas o el proveedor falla, la app deja escribir los datos a mano (nunca bloquea la venta).
 * El normalizador acepta los nombres de campo de los proveedores más usados (decolecta / apis.net.pe y similares).
 */

export type DocKind = "dni" | "ruc";

export type DocResult = {
  kind: DocKind;
  number: string;
  name: string; // nombre completo o razón social
  address: string;
  district: string;
  province: string;
  department: string;
  ubigeo: string;
  status: string; // RUC: ACTIVO / BAJA... (vacío en DNI)
  condition: string; // RUC: HABIDO / NO HABIDO
  source: string;
};

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
    if (v) return v;
  }
  return "";
};

/** Convierte la respuesta del proveedor (cualquiera de los formatos comunes) al formato de FacturaVoz. */
export function normalizeDoc(kind: DocKind, number: string, raw: unknown, source = "proveedor"): DocResult | null {
  if (!raw || typeof raw !== "object") return null;
  let o = raw as Record<string, unknown>;
  if (o.data && typeof o.data === "object" && !Array.isArray(o.data)) o = { ...o, ...(o.data as Record<string, unknown>) };
  let name = "";
  if (kind === "dni") {
    const full = first(o, ["full_name", "nombre_completo", "nombreCompleto", "nombre"]);
    const given = first(o, ["first_name", "nombres"]);
    const p1 = first(o, ["first_last_name", "apellido_paterno", "apellidoPaterno"]);
    const p2 = first(o, ["second_last_name", "apellido_materno", "apellidoMaterno"]);
    name = given && p1 ? `${given} ${p1} ${p2}`.trim() : full;
  } else {
    name = first(o, ["razon_social", "razonSocial", "nombre_o_razon_social", "nombre", "name"]);
  }
  name = name.replace(/\s+/g, " ").toUpperCase().slice(0, 200);
  if (!name) return null;
  return {
    kind,
    number,
    name,
    address: first(o, ["direccion", "direccion_completa", "domicilio_fiscal", "address"]).slice(0, 300),
    district: first(o, ["distrito", "district"]),
    province: first(o, ["provincia", "province"]),
    department: first(o, ["departamento", "department"]),
    ubigeo: first(o, ["ubigeo"]).replace(/\D/g, "").slice(0, 6),
    status: kind === "ruc" ? first(o, ["estado", "estado_contribuyente", "status"]).toUpperCase() : "",
    condition: kind === "ruc" ? first(o, ["condicion", "condicion_domicilio", "condition"]).toUpperCase() : "",
    source,
  };
}

export function providerUrl(kind: DocKind, number: string): string | null {
  const tpl = (kind === "dni" ? process.env.DOC_API_DNI_URL : process.env.DOC_API_RUC_URL) ?? "";
  if (!/^https:\/\/[^\s]+\{n\}/.test(tpl)) return null;
  return tpl.replace("{n}", encodeURIComponent(number));
}

export async function fetchDoc(kind: DocKind, number: string): Promise<{ ok: true; data: DocResult } | { ok: false; reason: "not_configured" | "not_found" | "limit" | "error" }> {
  const url = providerUrl(kind, number);
  if (!url) return { ok: false, reason: "not_configured" };
  const token = (process.env.DOC_API_TOKEN ?? "").trim();
  let res: Response;
  try {
    res = await fetch(url, {
      headers: { Accept: "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      signal: AbortSignal.timeout(8_000),
      cache: "no-store",
    });
  } catch {
    return { ok: false, reason: "error" };
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
  const data = normalizeDoc(kind, number, body, new URL(url).hostname);
  return data ? { ok: true, data } : { ok: false, reason: "not_found" };
}
