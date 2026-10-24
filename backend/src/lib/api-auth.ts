import { NextResponse } from "next/server";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const allowedOrigins = () => (process.env.ALLOWED_ORIGINS ?? "").split(",").map((s) => s.trim()).filter(Boolean);

export function corsHeaders(origin: string | null, methods = "POST, OPTIONS"): Record<string, string> {
  const base: Record<string, string> = { "Cache-Control": "no-store", Vary: "Origin" };
  if (origin && allowedOrigins().includes(origin)) {
    return {
      ...base,
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": methods,
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Max-Age": "86400",
    };
  }
  return base;
}

export function preflight(req: Request) {
  const h = corsHeaders(req.headers.get("origin"));
  return new NextResponse(null, { status: h["Access-Control-Allow-Origin"] ? 204 : 403, headers: h });
}

export type AuthedUser = { supabase: SupabaseClient; userId: string };

/** Solo Bearer (apps Flutter). Valida el token contra Supabase Auth; RLS aplica con ese token. */
export async function authenticateBearer(req: Request): Promise<AuthedUser | null> {
  const m = /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/.exec(req.headers.get("authorization") ?? "");
  if (!m) return null;
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: `Bearer ${m[1]}` } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data } = await supabase.auth.getUser(m[1]);
  return data.user ? { supabase, userId: data.user.id } : null;
}

export function jsonWith(origin: string | null) {
  const cors = corsHeaders(origin);
  return (body: unknown, status = 200) => NextResponse.json(body, { status, headers: cors });
}

/** Lee JSON con tope de tamaño. */
export async function readJson(req: Request, maxBytes: number): Promise<Record<string, unknown> | null> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > maxBytes) return null;
  try {
    const text = await req.text();
    if (text.length > maxBytes) return null;
    const v = JSON.parse(text);
    return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}
