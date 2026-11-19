"use server";

import { createSafeActionClient } from "next-safe-action";
import { createClient } from "@/lib/supabase/server";
import { invoiceInputSchema, type ActionResult } from "@/lib/schemas";
import { z } from "zod";
import { workspaceContext } from "@/lib/erp/context";
import { can, hasFeature } from "@/lib/erp/access";
import { revalidatePath } from "next/cache";

// Solo los SafeError llegan al cliente; cualquier otro error se oculta (sin fugas de información interna)
class SafeError extends Error {}

const safeAction = createSafeActionClient({
  handleServerError: (e) => (e instanceof SafeError ? e.message : "Error inesperado"),
});

const run = safeAction
  .inputSchema(invoiceInputSchema.extend({ org_id: z.uuid() }))
  .action(async ({ parsedInput }) => {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) throw new SafeError("Sesión no válida");
    const c = await workspaceContext(parsedInput.org_id);
    if (!can(c.access, "sell") || !hasFeature(c.license, "facturar")) throw new SafeError("Tu licencia o rol no permite facturar.");

    // Creación atómica en la base de datos (cliente + número correlativo + cabecera + líneas)
    const { data, error } = await supabase.rpc("create_invoice", {
      p_client_name: parsedInput.client_name,
      p_client_tax_id: parsedInput.client_tax_id || null,
      p_tax_rate: parsedInput.tax_rate,
      p_currency: c.organization.currency || "PEN",
      p_org_id: c.org,
      p_notes: parsedInput.notes ?? null,
      p_transcript: parsedInput.transcript ?? null,
      p_items: parsedInput.items,
    });
    const row = Array.isArray(data) ? data[0] : null;
    if (error || !row) throw new SafeError("No se pudo crear la factura");
    revalidatePath(`/erp/${c.org}`, "layout");
    return { id: row.invoice_id as string, number: row.invoice_number as string };
  });

export async function createInvoice(
  input: unknown
): Promise<ActionResult<{ id: string; number: string }>> {
  try {
    const res = await run(input as never);
    if (res?.validationErrors) return { success: false, error: "Datos no válidos" };
    if (res?.serverError) return { success: false, error: String(res.serverError) };
    if (!res?.data) return { success: false, error: "Error desconocido" };
    return { success: true, data: res.data };
  } catch {
    return { success: false, error: "Error inesperado" };
  }
}
