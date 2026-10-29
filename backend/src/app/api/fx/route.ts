import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { fetchFx } from "@/lib/fx";
import { limaToday } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 15;
export const OPTIONS = preflight;

/**
 * Tipo de cambio oficial (SUNAT) del día para facturar en dólares. Proveedor configurable (FX_API_URL).
 * Se guarda en fx_rates; si no hay proveedor, la app pide escribirlo (nunca se inventa).
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = (await readJson(req, 500)) ?? {};
  const date = typeof body.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date) ? body.date : limaToday();
  const currency = typeof body.currency === "string" && /^[A-Z]{3}$/.test(body.currency) ? body.currency : "USD";
  const { data: row } = await auth.supabase.from("fx_rates").select("buy, sell, source, day").eq("day", date).eq("currency", currency).maybeSingle();
  if (row) return json({ ok: true, ...row });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ ok: false, message: "Escribe el tipo de cambio del día." });
  const r = await fetchFx(date, currency);
  if (!r) return json({ ok: false, message: "No hay tipo de cambio automático configurado (FX_API_URL). Escríbelo: lo publica SUNAT cada día." });
  await createAdminClient().from("fx_rates").upsert({ day: date, currency, buy: r.buy, sell: r.sell, source: r.source });
  return json({ ok: true, day: date, buy: r.buy, sell: r.sell, source: r.source });
}
