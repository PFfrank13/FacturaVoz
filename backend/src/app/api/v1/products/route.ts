import { apiAuth, apiJson, OPTIONS_API } from "@/lib/apikey";

export const OPTIONS = OPTIONS_API;

/** GET /api/v1/products — catálogo activo (precio sin IGV, stock y código de barras). */
export async function GET(req: Request) {
  const ctx = await apiAuth(req, "products:read");
  if (ctx instanceof Response) return ctx;
  const { data, error } = await ctx.admin
    .from("products")
    .select("id, name, unit_price, unit, stock, barcode, category, in_store")
    .eq("org_id", ctx.orgId)
    .eq("active", true)
    .order("name")
    .limit(2000);
  if (error) return apiJson({ error: "server_error" }, 500);
  return apiJson({ data: data ?? [] });
}
