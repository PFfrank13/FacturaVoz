import { authenticateBearer, jsonWith, preflight } from "@/lib/api-auth";
import { GroqError, sniffImage, visionJson } from "@/lib/groq";
import { PAYMENT_SYSTEM, sanitizeDocScan, sanitizePaymentScan, SCAN_SYSTEM } from "@/lib/scan";

export const maxDuration = 60;
export const OPTIONS = preflight;

// Groq acepta imágenes en base64 de hasta ~4 MB: la app ya las comprime a ~1600 px.
const MAX_IMAGE = 3_000_000;

/** Lee una foto: kind=document (factura/boleta de compra) o kind=payment (constancia Yape/Plin/banco). */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Servicio de IA no configurado en el servidor", code: "no_key" }, 503);
  if (Number(req.headers.get("content-length") ?? "0") > MAX_IMAGE + 100_000) return json({ error: "La foto es demasiado grande" }, 413);

  let bytes: Uint8Array | null = null;
  let kind: "document" | "payment" = "document";
  try {
    const form = await req.formData();
    const f = form.get("image");
    if (f instanceof File && f.size > 0 && f.size <= MAX_IMAGE) bytes = new Uint8Array(await f.arrayBuffer());
    kind = form.get("kind") === "payment" ? "payment" : "document";
  } catch {
    return json({ error: "Solicitud no válida" }, 400);
  }
  if (!bytes) return json({ error: "Foto no válida o demasiado grande" }, 400);
  const mime = sniffImage(bytes);
  if (!mime) return json({ error: "Formato de imagen no válido (usa JPG o PNG)" }, 400);

  const { data: allowed, error: qErr } = await auth.supabase.rpc("consume_api_quota", { p_per_minute: 5, p_per_day: 100 });
  if (qErr) return json({ error: "Falta ejecutar la migración de cuotas en Supabase", code: "quota_rpc" }, 500);
  if (allowed !== true) return json({ error: "Demasiadas lecturas seguidas. Espera un minuto." }, 429);

  const dataUrl = `data:${mime};base64,${Buffer.from(bytes).toString("base64")}`;
  try {
    if (kind === "payment") {
      const raw = await visionJson(key, PAYMENT_SYSTEM, "Extrae los datos de esta constancia de pago.", dataUrl, 800);
      return json({ kind, payment: sanitizePaymentScan(raw) });
    }
    const raw = await visionJson(key, SCAN_SYSTEM, "Extrae los datos de este comprobante.", dataUrl, 2500);
    const doc = sanitizeDocScan(raw);
    if (doc.total <= 0 && doc.items.length === 0 && !doc.supplier_name) {
      return json({ error: "No pude leer el comprobante. Toma la foto de frente, con buena luz y sin cortes.", code: "unreadable" }, 422);
    }
    return json({ kind, document: doc });
  } catch (e) {
    if (e instanceof GroqError && e.status === 429) return json({ error: "Servicio ocupado, inténtalo en un minuto" }, 503);
    console.error("scan: failed", e instanceof GroqError ? e.code : e instanceof Error ? e.name : "unknown");
    return json({ error: "No pude leer la foto. Inténtalo de nuevo.", code: e instanceof GroqError ? e.code : "scan" }, 502);
  }
}
