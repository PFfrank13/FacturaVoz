import { NextResponse } from "next/server";
import { readJson } from "@/lib/api-auth";
import { unseal } from "@/lib/crypto";
import { MpError, mpCreatePreference } from "@/lib/mercadopago";
import { isToken, publicBase } from "@/lib/publicbase";
import { getPublicInvoice, sameOrigin } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 20;

const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

/** Crea el checkout de Mercado Pago por el saldo pendiente y devuelve la URL de pago. */
export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Origen no permitido" }, 403);
  const body = await readJson(req, 2_000);
  if (!body || !isToken(body.token)) return json({ error: "Solicitud no válida" }, 400);
  const inv = await getPublicInvoice(body.token);
  if (!inv) return json({ error: "Comprobante no encontrado" }, 404);
  if (!inv.payable) return json({ error: "Este comprobante ya no tiene saldo pendiente" }, 409);
  if (!inv.pay.mp) return json({ error: "Este negocio no acepta tarjeta en línea" }, 409);

  const { data: sec } = await createAdminClient().from("org_secrets").select("mp_token_enc").eq("org_id", inv.orgId).maybeSingle();
  if (!sec?.mp_token_enc) return json({ error: "Pago con tarjeta no disponible" }, 409);
  const base = publicBase(req);
  try {
    const url = await mpCreatePreference(unseal(sec.mp_token_enc as string), {
      title: `${inv.business || "Pago"} · ${inv.number}`,
      amount: inv.balance,
      currency: inv.currency,
      externalRef: body.token,
      notificationUrl: `${base}/api/pay/mp/webhook?t=${body.token}`,
      backUrl: `${base}/pagar/${body.token}`,
    });
    return json({ url });
  } catch (e) {
    console.error("mp: preference failed", e instanceof MpError ? e.message : e instanceof Error ? e.name : "unknown");
    return json({ error: "No se pudo abrir el pago con tarjeta. Usa otro medio o inténtalo luego." }, 502);
  }
}
