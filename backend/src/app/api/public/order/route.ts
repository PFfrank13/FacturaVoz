import { NextResponse } from "next/server";
import { readJson } from "@/lib/api-auth";
import { sendResend } from "@/lib/collections";
import { escapeHtml } from "@/lib/email";
import { fmtMoney } from "@/lib/publicbase";
import { sameOrigin, userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 20;

const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

type Row = { quote_id: string; quote_number: string; org_id: string; public_token: string; total: number; currency: string; business: string; whatsapp: string | null };

/** Pedido desde la tienda pública. Los precios los pone la base de datos, no el navegador. */
export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Origen no permitido" }, 403);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  const body = await readJson(req, 12_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);
  const slug = typeof body.slug === "string" ? body.slug.slice(0, 40) : "";
  const name = typeof body.name === "string" ? body.name.slice(0, 120) : "";
  const phone = typeof body.phone === "string" ? body.phone.replace(/\D/g, "").replace(/^51(?=9\d{8}$)/, "") : "";
  const note = typeof body.note === "string" ? body.note.replace(/[\u0000-\u001f]/g, " ").slice(0, 300) : "";
  const table = typeof body.table === "string" && /^[0-9A-Za-z \-]{1,12}$/.test(body.table) ? body.table : "";
  const fulfillment = body.fulfillment === "delivery" ? "delivery" : body.fulfillment === "mesa" ? "mesa" : "recojo";
  const address = typeof body.address === "string" ? body.address.replace(/[\u0000-\u001f]/g, " ").slice(0, 200) : "";
  const items = Array.isArray(body.items)
    ? body.items.slice(0, 30).map((i) => {
        const o = (i ?? {}) as Record<string, unknown>;
        return { product_id: String(o.product_id ?? ""), qty: String(o.qty ?? "") };
      })
    : [];
  if (items.length === 0) return json({ error: "Tu pedido está vacío" }, 400);

  const admin = createAdminClient();
  // v2 (mesa, recojo/delivery, comandas). Si la migración 20261108 aún no corre, se usa la función original.
  let { data, error } = await admin.rpc("store_place_order2", {
    p_slug: slug, p_name: name, p_phone: phone, p_note: note, p_items: items,
    p_table: table || null, p_fulfillment: fulfillment, p_address: address || null,
  });
  if (error && (error.code === "PGRST202" || error.code === "42883")) {
    ({ data, error } = await admin.rpc("store_place_order", { p_slug: slug, p_name: name, p_phone: phone, p_note: note, p_items: items }));
  }
  if (error) {
    // Los mensajes de la función son nuestros y seguros para mostrar.
    const status = error.code === "P0002" ? 404 : error.code === "P0001" ? 429 : error.code === "22023" ? 400 : 500;
    return json({ error: status === 500 ? "No se pudo registrar el pedido" : error.message }, status);
  }
  const row = ((data ?? []) as Row[])[0];
  if (!row) return json({ error: "No se pudo registrar el pedido" }, 500);

  // Aviso al dueño (la app además lo muestra en vivo).
  const { data: owner } = await admin.from("organization_members").select("user_id").eq("org_id", row.org_id).eq("role", "owner").limit(1).maybeSingle();
  const to = owner ? await userEmail(owner.user_id as string) : null;
  if (to) {
    const total = fmtMoney(Number(row.total), row.currency);
    await sendResend(
      to,
      `${table ? `🍽️ Mesa ${table}` : "🛍️ Nuevo pedido web"} ${row.quote_number} · ${total}`,
      `<!doctype html><html lang="es"><body style="font-family:Arial,Helvetica,sans-serif;background:#f8f6fd;padding:24px;color:#26254b">
<div style="max-width:520px;margin:auto;background:#fff;border-radius:20px;padding:24px">
<h2 style="margin:0 0 10px">Nuevo pedido desde tu tienda</h2>
<p style="font-size:15px;line-height:1.5;color:#55577a"><b>${escapeHtml(name.trim())}</b> (cel. ${escapeHtml(phone)}) pidió por <b>${escapeHtml(total)}</b>.</p>
${note ? `<p style="padding:12px;background:#f3f1fc;border-radius:12px">“${escapeHtml(note)}”</p>` : ""}
<p style="font-size:15px;color:#55577a">Ábrelo en FacturaVoz → Cotizar y conviértelo en factura con un toque.</p></div></body></html>`,
    );
  }
  return json({
    number: row.quote_number,
    token: row.public_token,
    total: Number(row.total),
    currency: row.currency,
    business: row.business,
    whatsapp: row.whatsapp ?? "",
  });
}
