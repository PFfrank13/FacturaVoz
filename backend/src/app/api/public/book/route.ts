import { NextResponse } from "next/server";
import { readJson } from "@/lib/api-auth";
import { sameOrigin } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

const json = (b: unknown, s = 200) => NextResponse.json(b, { status: s, headers: { "Cache-Control": "no-store" } });

/** Reserva pública: llega a la Agenda del negocio como cita "por confirmar" + aviso en vivo al dueño. */
export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Origen no permitido" }, 403);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "No disponible" }, 503);
  const b = await readJson(req, 3_000);
  if (!b) return json({ error: "Solicitud no válida" }, 400);
  const str = (v: unknown, n: number) => (typeof v === "string" ? v.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, n) : "");
  const at = str(b.at, 40);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00-05:00$/.test(at)) return json({ error: "Elige día y hora" }, 400);
  const phone = str(b.phone, 20).replace(/\D/g, "").replace(/^51(?=9\d{8}$)/, "");
  const { error } = await createAdminClient().rpc("store_book", {
    p_slug: str(b.slug, 40),
    p_name: str(b.name, 120),
    p_phone: phone,
    p_service: str(b.service, 100),
    p_at: at,
    p_note: str(b.note, 300),
  });
  if (error) {
    const status = error.code === "P0002" ? 404 : error.code === "P0001" ? 429 : error.code === "22023" ? 400 : 500;
    return json({ error: status === 500 ? "No se pudo reservar" : error.message }, status);
  }
  return json({ ok: true });
}
