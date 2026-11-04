import type { SupabaseClient } from "@supabase/supabase-js";
import { hasFeature } from "./erp/access";

/** Verificación de licencia + función por empresa, antes de invocar proveedores de pago. */
export async function licenseAllows(client: SupabaseClient, orgId: string | null, feature: string): Promise<boolean> {
  if (!orgId) return false;
  const { data, error } = await client.rpc("my_license", { p_org: orgId });
  if (error || !data || typeof data !== "object") return false;
  const l = data as {
    source?: string; enforced?: boolean; dev?: boolean; mode?: string;
    features?: Record<string, unknown>;
  };
  return hasFeature(l, feature);
}
