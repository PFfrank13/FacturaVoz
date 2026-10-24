"use server";

import { createSafeActionClient } from "next-safe-action";
import { createClient } from "@/lib/supabase/server";
import { invoiceInputSchema, type ActionResult } from "@/lib/schemas";

// Solo los SafeError llegan al cliente; cualquier otro error se oculta (sin fugas de información interna)
class SafeError extends Error {}

const safeAction = createSafeActionClient({
  handleServerError: (e) => (e instanceof SafeError ? e.message : "Error inesperado"),
});

const run = safeAction
  .inputSchema(invoiceInputSchema)
  .action(async ({ parsedInput }) => {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) throw new SafeError("Sesión no válida");

    // Creación atómica en la base de datos (cliente + número correlativo + cabecera + líneas)
    const { data, error } = await supabase.rpc("create_invoice", {
      p_client_name: parsedInput.client_name,
      p_client_tax_id: null,
      p_tax_rate: parsedInput.tax_rate,
      p_currency: "EUR", // la web heredada solo muestra EUR; la app Flutter usa la moneda del perfil
      p_notes: parsedInput.notes ?? null,
      p_transcript: parsedInput.transcript ?? null,
      p_items: parsedInput.items,
    });
    const row = Array.isArray(data) ? data[0] : null;
    if (error || !row) throw new SafeError("No se pudo crear la factura");
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
