import { authenticateBearer, jsonWith, preflight } from "@/lib/api-auth";
import { analyzeWorkbook } from "@/lib/workbook-import";
import { readXlsx } from "@/lib/xlsx";

export const maxDuration = 30;
export const OPTIONS = preflight;

const MAX_BYTES = 4 * 1024 * 1024; // límite de Vercel para el cuerpo de una petición (~4,5 MB)

/**
 * Analiza un libro Excel con varias hojas (clientes, comprobantes, detalle, catálogo) y devuelve:
 *   preview: hojas detectadas, conteos, totales por moneda y avisos (para la pantalla de confirmación)
 *   payload: datos normalizados que la app guarda por bloques con las funciones wb_import_* (con su sesión y RLS).
 * No guarda nada. El archivo no se almacena.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > MAX_BYTES) return json({ error: "El archivo pesa más de 4 MB. Divídelo en dos (por ejemplo, por año) e impórtalos por separado." }, 413);
  const { data: allowed } = await auth.supabase.rpc("consume_api_quota", { p_per_minute: 5, p_per_day: 60 });
  if (allowed === false) return json({ error: "Muchos archivos seguidos. Espera un minuto." }, 429);

  const buf = Buffer.from(await req.arrayBuffer());
  if (buf.length > MAX_BYTES) return json({ error: "El archivo pesa más de 4 MB. Divídelo en dos e impórtalos por separado." }, 413);
  if (buf.length < 100) return json({ error: "El archivo está vacío." }, 400);
  const rate = Number(new URL(req.url).searchParams.get("rate") ?? "18");
  try {
    const t0 = Date.now();
    const sheets = readXlsx(buf);
    // A single-sheet Excel (SUNAT's sales register, another system's list) goes to the old-receipts import, like the app.
    const mode = new URL(req.url).searchParams.get("mode");
    if (mode === "table" || (mode === "auto" && sheets.filter(s => s.rows.length).length < 2)) {
      const first = sheets.find(s => s.rows.length);
      if (!first) return json({ error: "El Excel está vacío." }, 422);
      return json({ kind: "table", rows: first.rows.map(r => r.map(c => (c == null ? "" : String(c)))) });
    }
    const { preview, payload } = analyzeWorkbook(sheets, Number.isFinite(rate) && rate >= 0 && rate <= 100 ? rate : 18);
    const relational = preview.sheets.filter((s) => s.role !== "ignorada").length;
    if (!preview.counts.documents && !preview.counts.clients && !preview.counts.products) {
      return json({ error: "No encontré clientes, comprobantes ni productos en este archivo. Revisa que la primera fila de cada hoja tenga los nombres de las columnas.", preview }, 422);
    }
    return json({ preview, payload, relational, ms: Date.now() - t0 });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "No pude leer el Excel." }, 422);
  }
}
