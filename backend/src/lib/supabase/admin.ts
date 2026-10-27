import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * Cliente con service_role: SOLO para lo que ningún usuario debe poder escribir directamente:
 * módulo fiscal (series, correlativos y resultados de SUNAT), importaciones, y "Negocio Pro"
 * (páginas públicas /cotizacion y /pagar que se abren con token, pagos reportados, webhook de
 * Mercado Pago, secretos cifrados y cron de cobranza). Nunca importar desde código de cliente ni exponer la clave.
 */
export function createAdminClient() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY no configurada");
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
