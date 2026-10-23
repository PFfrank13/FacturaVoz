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
  .schema(invoiceInputSchema)
  .action(async ({ parsedInput }) => {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) throw new SafeError("Sesión no válida");

    let clientId: string;
    const { data: existing } = await supabase
      .from("clients")
      .select("id")
      .eq("user_id", user.id)
      .ilike("name", parsedInput.client_name.replace(/[%_\\]/g, "\\$&")) // sin comodines LIKE
      .limit(1)
      .maybeSingle();
    if (existing) {
      clientId = existing.id;
    } else {
      const { data: created, error } = await supabase
        .from("clients")
        .insert({ user_id: user.id, name: parsedInput.client_name })
        .select("id")
        .single();
      if (error || !created) throw new SafeError("No se pudo crear el cliente");
      clientId = created.id;
    }

    // Numeración correlativa con reintento ante colisión (unique user_id+number)
    for (let attempt = 0; attempt < 3; attempt++) {
      const { count } = await supabase
        .from("invoices")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id);
      const number = `F-${new Date().getFullYear()}-${String((count ?? 0) + 1 + attempt).padStart(4, "0")}`;

      const { data: invoice, error: invErr } = await supabase
        .from("invoices")
        .insert({
          user_id: user.id,
          client_id: clientId,
          number,
          tax_rate: parsedInput.tax_rate,
          notes: parsedInput.notes ?? null,
          transcript: parsedInput.transcript ?? null,
        })
        .select("id, number")
        .single();
      if (invErr?.code === "23505") continue;
      if (invErr || !invoice) throw new SafeError("No se pudo crear la factura");

      const { error: itemsErr } = await supabase.from("invoice_items").insert(
        parsedInput.items.map((i) => ({ ...i, user_id: user.id, invoice_id: invoice.id }))
      );
      if (itemsErr) {
        await supabase.from("invoices").delete().eq("id", invoice.id);
        throw new SafeError("No se pudieron guardar las líneas");
      }
      return { id: invoice.id, number: invoice.number };
    }
    throw new SafeError("No se pudo asignar número de factura");
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
