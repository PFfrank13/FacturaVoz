import { apiAuth, apiJson, OPTIONS_API } from "@/lib/apikey";

export const OPTIONS = OPTIONS_API;

/**
 * POST /api/v1/orders  → crea un pedido (cotización "Pedido API") que el negocio convierte en factura con un toque.
 * { "client_name": "…", "client_tax_id": "…", "phone": "…", "note": "…",
 *   "items": [{ "product_id": "uuid" , "quantity": 2 } | { "description": "Polo", "quantity": 1, "unit_price": 30 }] }
 * Con product_id el precio sale del catálogo (no del pedido).
 */
export async function POST(req: Request) {
  const ctx = await apiAuth(req, "orders:write");
  if (ctx instanceof Response) return ctx;
  let body: Record<string, unknown>;
  try {
    const text = await req.text();
    if (text.length > 30_000) return apiJson({ error: "too_large" }, 413);
    body = JSON.parse(text) as Record<string, unknown>;
  } catch {
    return apiJson({ error: "invalid_json" }, 400);
  }
  const s = (v: unknown, n: number) => (typeof v === "string" ? v.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, n) : "");
  const items = Array.isArray(body.items) ? body.items.slice(0, 50) : [];
  const { data, error } = await ctx.admin.rpc("api_create_order", {
    p_org: ctx.orgId,
    p_client_name: s(body.client_name, 120),
    p_client_tax_id: s(body.client_tax_id, 30),
    p_phone: s(body.phone, 30),
    p_note: s(body.note, 300),
    p_items: items,
  });
  if (error) {
    if (error.code === "22023") return apiJson({ error: "validation", message: error.message }, 400);
    if (error.code === "42501") return apiJson({ error: "license", message: error.message }, 402);
    return apiJson({ error: "server_error" }, 500);
  }
  const row = ((data ?? []) as { quote_id: string; quote_number: string; public_token: string }[])[0];
  return apiJson({ id: row?.quote_id, number: row?.quote_number }, 201);
}
