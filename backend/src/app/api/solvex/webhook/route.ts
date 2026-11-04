import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { hubConfig, isOrgId, LicenseError, publicKeys, verifyToken, verifyWebhook } from "@/lib/solvex";

export const maxDuration = 20;

const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

/**
 * Webhook de Solvex Hub (cambios de licencia en tiempo real).
 * 1) Firma HMAC-SHA256 del cuerpo CRUDO con SOLVEX_WEBHOOK_SECRET y marca de tiempo ≤ 5 min (anti-reproducción).
 * 2) Cada evento se procesa UNA vez (solvex_events).
 * 3) El token Ed25519 que viene dentro se verifica (emisor, audiencia = esta instancia, vigencia) antes de creerle.
 * 4) Se guarda el estado en org_licenses (license_apply descarta tokens más viejos que el último aplicado).
 */
export async function POST(req: Request) {
  const cfg = hubConfig();
  if (!cfg || !cfg.webhookSecret) return json({ error: "Hub no configurado" }, 503);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  if (Number(req.headers.get("content-length") ?? "0") > 64_000) return json({ error: "Demasiado grande" }, 413);
  const raw = await req.text();
  if (raw.length > 64_000) return json({ error: "Demasiado grande" }, 413);
  const ok = verifyWebhook({
    secret: cfg.webhookSecret,
    timestamp: req.headers.get("solvex-timestamp"),
    signature: req.headers.get("solvex-signature"),
    rawBody: raw,
  });
  if (!ok) return json({ error: "Firma no válida" }, 401);

  let evt: { id?: unknown; type?: unknown; data?: { token?: unknown; tenant_ref?: unknown } };
  try {
    evt = JSON.parse(raw);
  } catch {
    return json({ error: "JSON no válido" }, 400);
  }
  const id = typeof evt.id === "string" && /^[A-Za-z0-9_-]{3,80}$/.test(evt.id) ? evt.id : null;
  if (!id) return json({ error: "Evento sin id" }, 400);

  const admin = createAdminClient();
  const { error: dup } = await admin.from("solvex_events").insert({ id });
  if (dup) {
    if (dup.code === "23505") return json({ ok: true, duplicate: true });
    console.error("solvex webhook: events insert", dup.code);
    return json({ error: "No disponible" }, 500);
  }
  if (evt.type === "ping") return json({ ok: true, pong: true });
  if (evt.type !== "license.updated" || typeof evt.data?.token !== "string") return json({ ok: true, ignored: true });

  try {
    const payload = verifyToken(evt.data.token, await publicKeys(cfg), { audience: cfg.instanceId });
    const tenant = payload.tenant ?? (typeof evt.data.tenant_ref === "string" ? evt.data.tenant_ref : null);
    if (!isOrgId(tenant)) return json({ ok: true, ignored: "tenant" });
    const { data, error } = await admin.rpc("license_apply", { p_org: tenant, p_payload: payload, p_token: evt.data.token });
    if (error) throw new Error(error.code ?? "rpc");
    return json({ ok: true, result: data });
  } catch (e) {
    // Si falla, se libera el id para que el reintento del Hub vuelva a intentarlo.
    await admin.from("solvex_events").delete().eq("id", id);
    if (e instanceof LicenseError) return json({ error: e.message }, 400);
    console.error("solvex webhook: apply failed", e instanceof Error ? e.message : "unknown");
    return json({ error: "No se pudo aplicar" }, 500);
  }
}
