/**
 * Mercado Pago Checkout Pro (disponible en Perú, sin costo fijo: solo comisión por venta aprobada).
 * Cada empresa conecta SU cuenta con su Access Token de producción; el dinero va directo a ella.
 */
const MP = "https://api.mercadopago.com";

export class MpError extends Error {}

async function mp<T>(token: string, path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${MP}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) throw new MpError(`mp_${res.status}`);
  return (await res.json()) as T;
}

/** Comprueba que el token sea válido. Devuelve el id de la cuenta. */
export async function mpWhoAmI(token: string): Promise<string> {
  const me = await mp<{ id?: number | string }>(token, "/users/me");
  if (me.id == null) throw new MpError("mp_me");
  return String(me.id);
}

export async function mpCreatePreference(
  token: string,
  o: { title: string; amount: number; currency: string; externalRef: string; notificationUrl: string; backUrl: string },
): Promise<string> {
  const pref = await mp<{ init_point?: string }>(token, "/checkout/preferences", {
    method: "POST",
    body: JSON.stringify({
      items: [{ title: o.title.slice(0, 250), quantity: 1, unit_price: o.amount, currency_id: o.currency }],
      external_reference: o.externalRef,
      notification_url: o.notificationUrl,
      back_urls: { success: o.backUrl, failure: o.backUrl, pending: o.backUrl },
      auto_return: "approved",
    }),
  });
  if (!pref.init_point || !/^https:\/\//.test(pref.init_point)) throw new MpError("mp_pref");
  return pref.init_point;
}

export type MpPayment = { id: number; status: string; transaction_amount: number; currency_id: string; external_reference: string | null };

export function mpGetPayment(token: string, id: string): Promise<MpPayment> {
  if (!/^\d{1,20}$/.test(id)) throw new MpError("mp_id");
  return mp<MpPayment>(token, `/v1/payments/${id}`);
}

/** Saca el id del pago de las distintas formas en que Mercado Pago notifica (webhook o IPN). */
export function paymentIdFrom(url: URL, body: Record<string, unknown> | null): string | null {
  const q = url.searchParams;
  const type = q.get("type") ?? q.get("topic") ?? (typeof body?.type === "string" ? body.type : null) ?? (typeof body?.topic === "string" ? body.topic : null);
  if (type && type !== "payment") return null;
  const data = (body?.data ?? null) as Record<string, unknown> | null;
  const id = q.get("data.id") ?? (data && data.id != null ? String(data.id) : null) ?? q.get("id");
  return id && /^\d{1,20}$/.test(id) ? id : null;
}
