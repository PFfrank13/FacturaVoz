"use server";
import { z } from "zod";
import { revalidatePath } from "next/cache";
import { workspaceContext } from "@/lib/erp/context";
import { cents } from "@/lib/retail/money";
import { can, hasFeature } from "@/lib/erp/access";

const sale = z.object({
  currency: z.string().regex(/^[A-Z]{3}$/), taxBasisPoints: z.number().int().min(0).max(10000),
  requestId: z.uuid(), method: z.enum(["efectivo", "yape", "plin", "tarjeta", "transferencia"]),
  items: z.array(z.object({ product_id: z.uuid(), quantity: z.number().positive().max(100000),
    unit_price: z.number().nonnegative().max(10000000) })).min(1).max(50),
});
export type CheckoutResult = { ok: boolean; message: string; invoiceId?: string; charged?: number; uncertain?: boolean };

export async function checkout(org: string, input: unknown): Promise<CheckoutResult> {
  const c = await workspaceContext(org);
  if (!hasFeature(c.license, "facturar") || !can(c.access, "sell") || !can(c.access, "collect"))
    return { ok: false, message: "Necesitas permiso para vender y registrar cobros." };
  const parsed = sale.safeParse(input);
  if (!parsed.success || new Set(parsed.data.items.map(i => i.product_id)).size !== parsed.data.items.length)
    return { ok: false, message: "Revisa los productos y cantidades de la venta." };
  const { items, requestId, method } = parsed.data;
  const previous = await c.db.from("fast_checkout_requests").select("invoice_id").eq("org_id", org).eq("request_id", requestId).eq("user_id", c.user.id).maybeSingle();
  if (previous.error) return { ok: false, uncertain: true, message: "No pudimos verificar el estado de la operación. Reintenta el mismo cobro." };
  const invoke = async (lines: Array<{ product_id: string; quantity: number; unit_price: number; description: string }>): Promise<CheckoutResult> => {
    const { data, error } = await c.db.rpc("fast_checkout_atomic", {
      p_org_id: org, p_request_id: requestId, p_method: method,
      p_currency: c.organization.currency || "PEN", p_tax_rate: Number(c.organization.default_tax_rate ?? 18),
      p_notes: null, p_items: lines,
    });
    if (error || !data?.[0]?.invoice_id)
      return { ok: false, uncertain: true, message: "Cobro sin confirmar. Reintenta la misma operación para evitar duplicados. Si persiste, solicita revisar el servicio de ventas." };
    revalidatePath(`/erp/${org}`, "layout");
    return { ok: true, message: "Venta y cobro registrados.", invoiceId: data[0].invoice_id, charged: Number(data[0].charged) };
  };
  // A committed receipt must remain recoverable even if its products/prices changed.
  if (previous.data?.invoice_id) return invoke(items.map(i => ({ ...i, description: "Recuperación de venta" })));
  if (parsed.data.currency !== (c.organization.currency || "PEN") || parsed.data.taxBasisPoints !== cents(Number(c.organization.default_tax_rate ?? 18)))
    return { ok: false, message: "Cambió la moneda o el impuesto. Revisa el ticket antes de confirmar." };
  const products = await c.db.from("products").select("id,name,unit_price").eq("org_id", org).eq("active", true).in("id", items.map(i => i.product_id));
  if (products.error || products.data?.length !== items.length)
    return { ok: false, message: "No pudimos verificar el catálogo de tu empresa." };
  // No client-provided price/description is trusted. Price changes need review before charging.
  if (items.some(i => Number(products.data.find(p => p.id === i.product_id)?.unit_price) !== i.unit_price))
    return { ok: false, message: "Cambió un precio del catálogo. Revisa la venta antes de confirmar." };
  return invoke(items.map(i => ({ ...i, description: products.data.find(p => p.id === i.product_id)!.name })));
}
