import { apiAuth, apiJson, OPTIONS_API } from "@/lib/apikey";

export const OPTIONS = OPTIONS_API;

/** GET /api/v1/clients?q=texto&limit=200 */
export async function GET(req: Request) {
  const ctx = await apiAuth(req, "clients:read");
  if (ctx instanceof Response) return ctx;
  const u = new URL(req.url);
  const term = (u.searchParams.get("q") ?? "").replace(/[%_,()]/g, " ").trim().slice(0, 60);
  const limit = Math.min(Math.max(Number(u.searchParams.get("limit") ?? "200") || 200, 1), 1000);
  let q = ctx.admin.from("clients").select("id, name, tax_id, email, phone, address, tags, created_at").eq("org_id", ctx.orgId).order("name").limit(limit);
  if (term) q = q.ilike("name", `%${term}%`);
  const { data, error } = await q;
  if (error) return apiJson({ error: "server_error" }, 500);
  return apiJson({ data: data ?? [] });
}
