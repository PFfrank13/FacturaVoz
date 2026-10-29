import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

/**
 * API pública de FacturaVoz para conectar tiendas en línea o sistemas propios.
 * Autenticación: "Authorization: Bearer fvk_…" (clave creada por el dueño en la app; solo se guarda su hash).
 * Permisos por clave (invoices:read, clients:read, products:read, orders:write) y 120 solicitudes por minuto.
 */
export type ApiCtx = { orgId: string; keyId: string; admin: ReturnType<typeof createAdminClient> };

export const apiJson = (body: unknown, status = 200) =>
  NextResponse.json(body, { status, headers: { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Authorization, Content-Type" } });

export const hashKey = (key: string) => createHash("sha256").update(key, "utf8").digest("hex");

export async function apiAuth(req: Request, scope: "invoices:read" | "clients:read" | "products:read" | "orders:write"): Promise<ApiCtx | NextResponse> {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return apiJson({ error: "service_unavailable" }, 503);
  const m = /^Bearer (fvk_[0-9a-f]{64})$/.exec(req.headers.get("authorization") ?? "");
  if (!m) return apiJson({ error: "unauthorized", message: "Falta la clave: Authorization: Bearer fvk_…" }, 401);
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("api_key_auth", { p_hash: hashKey(m[1]), p_scope: scope });
  if (error) {
    if (error.code === "28000") return apiJson({ error: "unauthorized", message: "Clave no válida o revocada" }, 401);
    if (error.code === "42501") return apiJson({ error: "forbidden", message: "La clave no tiene permiso para esto" }, 403);
    if (error.code === "P0001") return apiJson({ error: "rate_limited", message: "Máximo 120 solicitudes por minuto" }, 429);
    return apiJson({ error: "server_error" }, 500);
  }
  const row = ((data ?? []) as { org_id: string; key_id: string }[])[0];
  if (!row) return apiJson({ error: "unauthorized" }, 401);
  // Kill-switch: con la licencia cortada la API tampoco responde.
  const { data: mode } = await admin.rpc("org_mode_service", { p_org: row.org_id });
  if (mode !== "full" && mode !== "warning") return apiJson({ error: "license", message: "La licencia de esta empresa no está activa" }, 402);
  return { orgId: row.org_id, keyId: row.key_id, admin };
}

export const OPTIONS_API = () =>
  new NextResponse(null, { status: 204, headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Max-Age": "86400" } });
