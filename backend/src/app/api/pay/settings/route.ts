import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { hasSecretsKey, seal } from "@/lib/crypto";
import { MpError, mpWhoAmI } from "@/lib/mercadopago";
import { UUID } from "@/lib/publicbase";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 20;
export const OPTIONS = preflight;

/**
 * Conecta (o desconecta) la cuenta de Mercado Pago de la empresa. Solo propietario/administrador.
 * El Access Token se valida contra Mercado Pago y se guarda CIFRADO; nunca vuelve a la app.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY || !hasSecretsKey()) {
    return json({ error: "Falta configurar SECRETS_KEY y SUPABASE_SERVICE_ROLE_KEY en el servidor", code: "no_secrets" }, 503);
  }
  const body = await readJson(req, 4_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);
  const orgId = typeof body.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  if (!orgId) return json({ error: "Empresa no válida" }, 400);
  const { data: role } = await auth.supabase.rpc("my_org_role", { p_org: orgId });
  if (role !== "owner" && role !== "admin") return json({ error: "Solo el propietario o un administrador puede conectar cobros" }, 403);

  const admin = createAdminClient();
  const token = typeof body.mp_access_token === "string" ? body.mp_access_token.trim() : null;
  if (!token) {
    await admin.from("org_secrets").upsert({ org_id: orgId, mp_token_enc: null, updated_at: new Date().toISOString() });
    await admin.from("org_pay_settings").upsert({ org_id: orgId, mp_enabled: false, updated_at: new Date().toISOString() });
    return json({ ok: true, mp_enabled: false });
  }
  if (!/^(APP_USR|TEST)-[\w-]{20,250}$/.test(token)) return json({ error: "Ese no parece un Access Token de Mercado Pago (empieza con APP_USR-)" }, 400);
  try {
    await mpWhoAmI(token);
  } catch (e) {
    return json({ error: e instanceof MpError && e.message === "mp_401" ? "Mercado Pago rechazó el token. Copia el Access Token de PRODUCCIÓN." : "No se pudo verificar con Mercado Pago" }, 400);
  }
  const { error: e1 } = await admin.from("org_secrets").upsert({ org_id: orgId, mp_token_enc: seal(token), updated_at: new Date().toISOString() });
  const { error: e2 } = await admin.from("org_pay_settings").upsert({ org_id: orgId, mp_enabled: true, updated_at: new Date().toISOString() });
  if (e1 || e2) return json({ error: "Falta ejecutar la migración 20261101_negocio_pro.sql" }, 500);
  return json({ ok: true, mp_enabled: true });
}
