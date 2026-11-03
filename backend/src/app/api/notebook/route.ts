import { authenticateBearer, jsonWith, preflight } from "@/lib/api-auth";
import { GroqError, sniffImage, visionJson } from "@/lib/groq";
import { NOTEBOOK_SYSTEM, sanitizeNotebook } from "@/lib/notebook";
import { UUID } from "@/lib/publicbase";
import { licenseAllows } from "@/lib/license-check";

export const maxDuration = 45;
export const OPTIONS = preflight;
const MAX = 6_000_000;

/** Foto de cuaderno / nota / WhatsApp → venta lista para confirmar. multipart: "image" (+ "org_id" para usar el catálogo). */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Servicio de IA no configurado en el servidor", code: "no_key" }, 503);
  if (Number(req.headers.get("content-length") ?? "0") > MAX + 100_000) return json({ error: "Imagen demasiado grande" }, 413);
  let bytes: Uint8Array | null = null;
  let orgId: string | null = null;
  try {
    const form = await req.formData();
    const f = form.get("image");
    if (f instanceof File && f.size > 0 && f.size <= MAX) bytes = new Uint8Array(await f.arrayBuffer());
    const o = form.get("org_id");
    orgId = typeof o === "string" && UUID.test(o) ? o : null;
  } catch {
    return json({ error: "Solicitud no válida" }, 400);
  }
  if (!bytes) return json({ error: "Imagen no válida" }, 400);
  const type = sniffImage(bytes);
  if (!type) return json({ error: "Usa una foto JPG, PNG o WEBP" }, 400);
  if (!await licenseAllows(auth.supabase, orgId, "cuaderno_ia")) {
    return json({ error: "Tu licencia no incluye el cuaderno inteligente.", code: "license" }, 402);
  }
  const { data: allowed } = await auth.supabase.rpc("consume_api_quota", { p_per_minute: 5, p_per_day: 100 });
  if (allowed !== true) return json({ error: "Demasiadas lecturas seguidas. Espera un minuto." }, 429);

  // Catálogo (para reconocer productos y completar precios). Solo nombres y precios.
  let catalog = "";
  if (orgId) {
    const { data: prods } = await auth.supabase.from("products").select("name, unit_price").eq("org_id", orgId).eq("active", true).order("name").limit(150);
    if (prods?.length) catalog = (prods as { name: string; unit_price: number | string }[]).map((p) => `${p.name}: ${Number(p.unit_price).toFixed(2)}`).join("\n");
  }
  try {
    const dataUrl = `data:${type};base64,${Buffer.from(bytes).toString("base64")}`;
    const prompt = catalog ? `Extrae la venta de esta foto. CATÁLOGO del negocio (precios sin IGV):\n<catalogo>\n${catalog}\n</catalogo>` : "Extrae la venta de esta foto.";
    const raw = await visionJson(key, NOTEBOOK_SYSTEM, prompt, dataUrl, 2500);
    return json({ sale: sanitizeNotebook(raw) });
  } catch (e) {
    if (e instanceof GroqError && e.status === 429) return json({ error: "Servicio ocupado, inténtalo en un minuto" }, 503);
    console.error("notebook: failed", e instanceof GroqError ? e.code : "unknown");
    return json({ error: "No pude leer la foto. Intenta con más luz y la hoja completa." }, 502);
  }
}
