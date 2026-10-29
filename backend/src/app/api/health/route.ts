import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const maxDuration = 10;

/**
 * Estado del servicio (G) para una página de estado o un monitor gratuito (UptimeRobot, Better Stack free).
 * Solo dice SI cada pieza está configurada/responde. Nunca muestra valores de claves.
 */
export async function GET() {
  const has = (k: string) => !!(process.env[k] ?? "").trim();
  let db = false;
  const t0 = Date.now();
  if (has("SUPABASE_SERVICE_ROLE_KEY")) {
    try {
      const { error } = await createAdminClient().from("organizations").select("id", { head: true, count: "exact" }).limit(1);
      db = !error;
    } catch {
      db = false;
    }
  }
  const body = {
    ok: db,
    time: new Date().toISOString(),
    db_ms: Date.now() - t0,
    services: {
      database: db,
      ia_copiloto: has("GROQ_API_KEY"),
      voz_premium: has("ELEVENLABS_API_KEY"),
      dni_ruc: has("DOC_API_TOKEN"),
      correo: has("RESEND_API_KEY"),
      licencias_hub: has("SOLVEX_API_KEY"),
      crons: has("CRON_SECRET"),
    },
  };
  return NextResponse.json(body, { status: db ? 200 : 503, headers: { "Cache-Control": "no-store" } });
}
