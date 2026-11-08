import { authenticateBearer, corsHeaders, jsonWith, preflight } from "@/lib/api-auth";
import { sniffImage } from "@/lib/groq";
import { licenseAllows } from "@/lib/license-check";

export const runtime = "nodejs";
export const maxDuration = 60;
export const OPTIONS = preflight;

const MAX_INPUT_BYTES = 3_000_000;
const MAX_OUTPUT_BYTES = 4_000_000;

/**
 * Product photos: authenticated, tenant-scoped and rate-limited server proxy.
 * The paid provider key never reaches Flutter. The PNG is returned in memory:
 * Flutter must explicitly accept it and upload to private Supabase Storage.
 */
export async function POST(req: Request) {
  const origin = req.headers.get("origin");
  const json = jsonWith(origin);
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "Inicia sesión para editar imágenes." }, 401);
  if (Number(req.headers.get("content-length") ?? "0") > MAX_INPUT_BYTES + 100_000) {
    return json({ error: "La foto supera los 3 MB permitidos." }, 413);
  }

  let orgId: string | null = null;
  let file: File | null = null;
  try {
    const form = await req.formData();
    const org = form.get("org_id");
    orgId = typeof org === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(org)
      ? org : null;
    file = form.get("image") instanceof File ? form.get("image") as File : null;
  } catch {
    return json({ error: "Foto no válida." }, 400);
  }

  if (!orgId || !file || file.size < 12 || file.size > MAX_INPUT_BYTES) {
    return json({ error: "Elige una empresa y una imagen JPG/PNG/WebP de hasta 3 MB." }, 400);
  }
  if (!await licenseAllows(auth.supabase, orgId, "stock")) {
    return json({ error: "Tu licencia no permite editar fotografías del catálogo." }, 403);
  }
  const access = await auth.supabase.rpc("my_access", { p_org: orgId });
  if (access.error || access.data?.can?.products_edit !== true) {
    return json({ error: "Solo un usuario con permisos de catálogo puede editar estas fotos." }, 403);
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const mime = sniffImage(bytes);
  if (!mime) return json({ error: "Formato de imagen no admitido." }, 415);
  const { data: allowed, error: limitError } = await auth.supabase.rpc("consume_api_quota", {
    p_per_minute: 3, p_per_day: 30,
  });
  if (limitError) return json({ error: "No se pudo comprobar la cuota de procesamiento." }, 503);
  if (allowed !== true) return json({ error: "Límite de imágenes alcanzado. Prueba más tarde." }, 429);

  const apiKey = process.env.REMOVE_BG_API_KEY;
  if (!apiKey) return json({ error: "La eliminación de fondo aún no está configurada en el servidor." }, 503);

  try {
    const input = new FormData();
    input.append("image_file", new Blob([bytes as BlobPart], { type: mime }), "producto.jpg");
    input.append("size", "auto");
    const response = await fetch("https://api.remove.bg/v1.0/removebg", {
      method: "POST",
      headers: { "X-Api-Key": apiKey },
      body: input,
      signal: AbortSignal.timeout(50_000),
    });
    if (!response.ok) {
      console.error("remove-bg: provider status", response.status);
      return json(
        { error: response.status === 402 ? "No hay créditos disponibles para procesar fotos."
          : response.status === 429 ? "El servicio está ocupado. Vuelve a intentarlo."
          : "No fue posible quitar el fondo. Puedes conservar la foto original." },
        response.status === 429 ? 429 : 502,
      );
    }
    const processed = await response.arrayBuffer();
    if (processed.byteLength < 12 || processed.byteLength > MAX_OUTPUT_BYTES ||
        sniffImage(new Uint8Array(processed)) !== "image/png") {
      return json({ error: "La respuesta de la IA no es un PNG válido." }, 502);
    }
    return new Response(processed, {
      status: 200,
      headers: {
        ...corsHeaders(origin), "Content-Type": "image/png",
        "X-Content-Type-Options": "nosniff",
        "Content-Disposition": 'inline; filename="producto-sin-fondo.png"',
      },
    });
  } catch (error) {
    console.error("remove-bg: request failed", error instanceof Error ? error.name : "unknown");
    return json({ error: "No se pudo conectar con el servicio de imágenes." }, 503);
  }
}
