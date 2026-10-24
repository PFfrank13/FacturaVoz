import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * Cliente con service_role: SOLO para el módulo fiscal (series, correlativos y resultados de SUNAT),
 * que ningún usuario debe poder escribir. Nunca importar desde código de cliente ni exponer la clave.
 */
export function createAdminClient() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY no configurada");
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
