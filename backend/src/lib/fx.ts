/**
 * Tipo de cambio desde un proveedor configurable (sin datos inventados).
 *   FX_API_URL  p. ej. https://api.decolecta.com/v1/tipo-cambio/sunat?date={date}   ({date} = AAAA-MM-DD, {currency} = USD)
 *   FX_API_TOKEN (o DOC_API_TOKEN) → "Authorization: Bearer <token>"
 */
export type Fx = { buy: number | null; sell: number | null; source: string };

const num = (v: unknown) => {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v.replace(",", ".")) : NaN;
  return Number.isFinite(n) && n > 0 && n < 100000 ? Math.round(n * 10000) / 10000 : null;
};

export function normalizeFx(raw: unknown): { buy: number | null; sell: number | null } | null {
  if (!raw || typeof raw !== "object") return null;
  let o = raw as Record<string, unknown>;
  if (Array.isArray(raw)) o = (raw[raw.length - 1] ?? {}) as Record<string, unknown>;
  if (o.data && typeof o.data === "object") o = { ...o, ...(o.data as Record<string, unknown>) };
  const pick = (keys: string[]) => {
    for (const k of keys) {
      const v = num(o[k]);
      if (v != null) return v;
    }
    return null;
  };
  const buy = pick(["buy_price", "compra", "precioCompra", "buy"]);
  const sell = pick(["sell_price", "venta", "precioVenta", "sell"]);
  return buy == null && sell == null ? null : { buy, sell };
}

export async function fetchFx(date: string, currency: string): Promise<Fx | null> {
  const tpl = process.env.FX_API_URL ?? "";
  if (!/^https:\/\//.test(tpl)) return null;
  const url = tpl.replace("{date}", encodeURIComponent(date)).replace("{currency}", encodeURIComponent(currency));
  const token = (process.env.FX_API_TOKEN ?? process.env.DOC_API_TOKEN ?? "").trim();
  try {
    const r = await fetch(url, { headers: { Accept: "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, signal: AbortSignal.timeout(8_000), cache: "no-store" });
    if (!r.ok) return null;
    const v = normalizeFx(await r.json());
    return v ? { ...v, source: new URL(url).hostname } : null;
  } catch {
    return null;
  }
}
