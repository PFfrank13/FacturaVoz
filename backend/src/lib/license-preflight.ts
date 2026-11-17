import type { LicensePayload, TenantToken } from "@/lib/solvex";

/**
 * Evaluación PURA (sin red ni escrituras) de lo que pasaría al reconciliar una empresa con el Hub.
 * Entrada: tokens del Hub YA verificados (firma Ed25519, emisor, audiencia = esta instancia; ver syncAll) y el estado
 * actual de la empresa en Supabase. Salida: un veredicto GO/NO-GO explicable, sin códigos ni tokens completos.
 */
export type OrgLicenseState = {
  source: string | null;
  license_code: string | null;
  pending_code: string | null;
  activated_code: string | null;
};

export type PreflightResult = {
  hub_tokens_for_tenant: number;
  rejected_tokens_in_instance: number;
  token: null | {
    plan: string | null; status: string | null; mode: string | null;
    period_end: string | null; grace_end: string | null; expires_at: string; issued_at: string;
    lic_last4: string | null; max_users: number | null;
  };
  current: { source: string | null; code_last4: string | null; pending: boolean; activated: boolean };
  checks: Record<string, boolean>;
  verdict: "GO" | "NO-GO";
  reasons: string[];
};

const last4 = (s: string | null | undefined) => (s ? s.slice(-4) : null);
const iso = (sec: number) => new Date(sec * 1000).toISOString();

export function evaluatePreflight(orgId: string, tokens: TenantToken[], bad: number, state: OrgLicenseState, now = Date.now()): PreflightResult {
  const mine = tokens.filter((t) => t.tenant === orgId && t.payload.tenant === orgId).sort((a, b) => (a.payload.iat ?? 0) - (b.payload.iat ?? 0));
  const p: LicensePayload | undefined = mine[mine.length - 1]?.payload;
  const expected = state.pending_code ?? state.license_code;
  const nowSec = Math.floor(now / 1000);
  const checks: Record<string, boolean> = {
    hub_responde_con_licencia_para_la_empresa: !!p,
    firma_emisor_audiencia_verificados: !!p, // syncAll solo devuelve tokens que pasaron verifyToken()
    tenant_coincide: !!p && p.tenant === orgId,
    producto_facturavoz: !!p && (p.product ?? "FACTURAVOZ") === "FACTURAVOZ",
    token_vigente: !!p && p.exp > nowSec,
    modo_permite_operar: !!p && (p.mode === "full" || p.mode === "warning"),
    periodo_vigente: !!p && (!p.period_end || Date.parse(p.period_end) > now || (!!p.grace_end && Date.parse(p.grace_end) > now)),
    codigo_coincide_con_el_de_la_empresa: !!p && !!p.lic && !!expected && p.lic === expected,
  };
  const reasons: string[] = [];
  if (!p) reasons.push("Solvex Hub no devolvió ninguna licencia firmada para esta empresa (tenant_ref). Asígnala en el Hub.");
  else {
    if (!checks.token_vigente) reasons.push("El token del Hub está vencido; el Hub debe reemitirlo.");
    if (!checks.modo_permite_operar) reasons.push(`El Hub indica modo '${p.mode}' (estado '${p.status}'): no permite operar.`);
    if (!checks.periodo_vigente) reasons.push("El período (prueba o pago) y la gracia ya vencieron en el Hub.");
    if (!checks.producto_facturavoz) reasons.push(`La licencia es del producto '${p.product}', no de FacturaVoz.`);
    if (!checks.codigo_coincide_con_el_de_la_empresa) {
      reasons.push("El código de la licencia del Hub no es el que tenía la empresa: la reconciliación automática NO se hará; el propietario deberá activar el código nuevo en la app (también sin corte).");
    }
  }
  const go = checks.hub_responde_con_licencia_para_la_empresa && checks.tenant_coincide && checks.producto_facturavoz
    && checks.token_vigente && checks.modo_permite_operar && checks.periodo_vigente && checks.codigo_coincide_con_el_de_la_empresa;
  const features = p?.features ?? {};
  return {
    hub_tokens_for_tenant: mine.length,
    rejected_tokens_in_instance: bad,
    token: p ? {
      plan: p.plan ?? null, status: p.status ?? null, mode: p.mode ?? null,
      period_end: p.period_end ?? null, grace_end: p.grace_end ?? null,
      expires_at: iso(p.exp), issued_at: iso(p.iat), lic_last4: last4(p.lic),
      max_users: typeof features.max_users === "number" ? features.max_users : null,
    } : null,
    current: {
      source: state.source, code_last4: last4(expected), pending: !!state.pending_code,
      activated: !!state.activated_code && state.activated_code === state.license_code,
    },
    checks,
    verdict: go ? "GO" : "NO-GO",
    reasons,
  };
}
