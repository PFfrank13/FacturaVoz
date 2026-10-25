import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { CertError, toLycetPem } from "@/lib/fiscal/cert";
import { isValidRuc } from "@/lib/fiscal/ids";
import { FE_URL, LycetError, putCompany } from "@/lib/fiscal/lycet";

export const maxDuration = 30;
export const OPTIONS = preflight;

const str = (v: unknown, max: number) => (typeof v === "string" && v.length > 0 && v.length <= max ? v : null);

/**
 * Registra la empresa del usuario en Lycet (RUC + usuario SOL secundario + certificado digital).
 * Los secretos NO se guardan en Supabase: viajan por HTTPS a tu VPS y quedan solo allí.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);

  const body = await readJson(req, 200_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);

  const solUser = str(body.sol_user, 30);
  const solPass = str(body.sol_password, 80);
  const certB64 = str(body.certificate_b64, 150_000);
  const format = body.certificate_format === "pem" ? "pem" : body.certificate_format === "pfx" ? "pfx" : null;
  const certPass = typeof body.certificate_password === "string" ? body.certificate_password.slice(0, 120) : "";
  const env = body.env === "prod" ? "prod" : body.env === "beta" ? "beta" : null;
  if (!solUser || !/^[A-Za-z0-9ñÑ_.-]+$/.test(solUser)) return json({ error: "Usuario SOL no válido" }, 400);
  if (!solPass || !certB64 || !format || !env) return json({ error: "Faltan datos" }, 400);

  // Empresa: la indicada (UUID) o la primera del usuario; solo propietario/administrador conecta SUNAT
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let orgId = typeof body.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  if (!orgId) {
    const { data: first } = await auth.supabase.from("organization_members").select("org_id").eq("user_id", auth.userId).order("created_at").limit(1).maybeSingle();
    orgId = (first?.org_id as string | undefined) ?? null;
  }
  if (!orgId) return json({ error: "No tienes una empresa. Ejecuta la migración multi-empresa." }, 412);
  const { data: role } = await auth.supabase.rpc("my_org_role", { p_org: orgId });
  if (role !== "owner" && role !== "admin") return json({ error: "Solo el propietario o un administrador puede conectar SUNAT" }, 403);
  const { data: org } = await auth.supabase.from("organizations").select("tax_id").eq("id", orgId).maybeSingle();
  const ruc = (org?.tax_id ?? "").trim();
  if (!isValidRuc(ruc)) return json({ error: "Primero escribe un RUC válido en «Datos del negocio»" }, 400);

  // 1) Certificado válido (antes de reclamar el RUC)
  let cert;
  try {
    cert = toLycetPem(certB64, format, certPass);
  } catch (e) {
    return json({ error: e instanceof CertError ? e.message : "Certificado no válido" }, 400);
  }
  // En producción el certificado debe pertenecer a ese RUC (evita que alguien «reclame» el RUC de otro)
  if (env === "prod" && !cert.subject.includes(ruc))
    return json({ error: "El certificado no corresponde al RUC. Si es correcto, contacta a soporte." }, 400);

  // 2) Un RUC pertenece a UN solo usuario
  const admin = createAdminClient();
  const { data: claim, error: claimErr } = await admin.rpc("fiscal_claim_company", { p_org: orgId, p_user: auth.userId, p_ruc: ruc, p_env: env });
  if (claimErr) return json({ error: "Error inesperado" }, 500);
  if (claim === "ruc_taken") return json({ error: "Ese RUC ya está registrado por otra empresa. Contacta a soporte." }, 409);
  if (claim === "other_ruc") return json({ error: "Esta empresa ya usa otro RUC. Contacta a soporte para cambiarlo." }, 409);

  // 3) Registro en Lycet (el SOL_USER es RUC + usuario)
  try {
    await putCompany(ruc, {
      SOL_USER: `${ruc}${solUser}`,
      SOL_PASS: solPass,
      certificate: Buffer.from(cert.pem).toString("base64"),
      FE_URL: FE_URL[env],
    });
  } catch (e) {
    return json({ error: e instanceof LycetError ? e.message : "Error inesperado" }, 502);
  }
  return json({ ok: true, ruc, env, cert_expires: cert.notAfter.toISOString().slice(0, 10) });
}
