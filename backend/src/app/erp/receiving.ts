"use server";
import { z } from "zod";
import { revalidatePath } from "next/cache";
import { workspaceContext } from "@/lib/erp/context";
import { can, hasFeature } from "@/lib/erp/access";
const receipt = z.object({ requestId: z.uuid(), supplier: z.string().trim().min(1).max(120), reference: z.string().trim().min(1).max(80),
  lines: z.array(z.object({product_id: z.uuid(), quantity: z.number().positive().max(100000).multipleOf(.01), unit_cost: z.number().min(0).max(10000000).multipleOf(.01)})).min(1).max(50) });
export async function receiveStock(org: string, input: unknown): Promise<{ok: boolean; message: string; id?: string; rejected?: boolean}> {
  const c = await workspaceContext(org);
  if (!can(c.access,"finance") || !hasFeature(c.license,"stock")) return {ok:false,rejected:true,message:"Necesitas permiso de finanzas e inventario."};
  const parsed = receipt.safeParse(input);
  if (!parsed.success || new Set(parsed.data.lines.map(l=>l.product_id)).size!==parsed.data.lines.length) return {ok:false,rejected:true,message:"Revisa proveedor, referencia, productos únicos, cantidad y costo (hasta dos decimales)."};
  const p = parsed.data;
  const {data,error} = await c.db.rpc("retail_receive", {p_org:org,p_request:p.requestId,p_supplier:p.supplier,p_reference:p.reference,
    p_lines:p.lines});
  if (error && ['22023','23505','42501','23514'].includes(error.code)) return {ok:false,rejected:true,message:error.code==='23505'?"Este proveedor y documento ya están registrados. Consulta el historial antes de corregir la referencia.":"El servidor rechazó la recepción sin aplicar cambios. Revisa productos, cantidades, costos y permisos."};
  if (error || typeof data !== "string") return {ok:false,message:"Recepción sin confirmar. Reintenta la misma operación. Verifica que el servicio de recepción esté disponible."};
  revalidatePath(`/erp/${org}`,"layout");
  return {ok:true,id:data,message:"Mercadería recibida. Existencias y último costo actualizados en el servidor. No se registró un pago al proveedor."};
}
