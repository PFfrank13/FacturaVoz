import { NextResponse } from "next/server";
import { readJson } from "@/lib/api-auth";
import { sameOrigin } from "@/lib/publicdata";
import { isPortalToken } from "@/lib/publicdocs";
import { createAdminClient } from "@/lib/supabase/admin";

const json = (b: unknown, s = 200) => NextResponse.json(b, { status: s, headers: { "Cache-Control": "no-store" } });

export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Origen no permitido" }, 403);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "No disponible" }, 503);
  const body = await readJson(req, 2_000);
  const token = body?.token;
  const score = Number(body?.score);
  const comment = typeof body?.comment === "string" ? body.comment.replace(/[\u0000-\u001f]/g, " ").slice(0, 500) : "";
  if (!isPortalToken(token) || !Number.isInteger(score) || score < 1 || score > 5) return json({ error: "Datos no válidos" }, 400);
  const { error } = await createAdminClient().rpc("survey_answer", { p_token: token, p_score: score, p_comment: comment });
  if (error) return json({ error: error.code === "P0002" ? "Encuesta no encontrada" : "No se pudo guardar" }, error.code === "P0002" ? 404 : 500);
  return json({ ok: true });
}
