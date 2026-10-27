/** URL pública del backend (páginas /cotizacion y /pagar, webhooks). */
export function publicBase(req?: Request): string {
  const env = process.env.PUBLIC_BASE_URL?.trim().replace(/\/+$/, "");
  if (env && /^https:\/\//.test(env)) return env;
  const vercel = process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim();
  if (vercel) return `https://${vercel.replace(/^https?:\/\//, "").replace(/\/+$/, "")}`;
  if (req) {
    const host = req.headers.get("host");
    if (host) return `${host.startsWith("localhost") ? "http" : "https"}://${host}`;
  }
  return "";
}

/** Los tokens públicos son 64 caracteres hexadecimales (private.new_token). */
export const isToken = (s: unknown): s is string => typeof s === "string" && /^[0-9a-f]{64}$/.test(s);

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const SYMBOLS: Record<string, string> = { PEN: "S/", USD: "US$", EUR: "€" };

/** "S/ 1,234.50" */
export function fmtMoney(n: number, currency: string): string {
  const v = (Math.round((n + Number.EPSILON) * 100) / 100).toFixed(2);
  const [i, d] = v.split(".");
  return `${SYMBOLS[currency] ?? currency} ${i.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${d}`;
}

/** "2026-11-05" → "05/11/2026" */
export const fmtDate = (iso: string | null | undefined) => {
  const p = (iso ?? "").split("-");
  return p.length === 3 ? `${p[2]}/${p[1]}/${p[0]}` : "";
};

type Item = { quantity: number | string; unit_price: number | string };
const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

/** Totales con impuesto por línea (igual que la app, la base de datos y SUNAT). */
export function totalsOf(items: Item[], taxRate: number | string) {
  const rate = Number(taxRate);
  let sub = 0;
  let tax = 0;
  for (const i of items) {
    const base = r2(Number(i.quantity) * Number(i.unit_price));
    sub += base;
    tax += r2((base * rate) / 100);
  }
  sub = r2(sub);
  tax = r2(tax);
  return { subtotal: sub, tax, total: r2(sub + tax) };
}
