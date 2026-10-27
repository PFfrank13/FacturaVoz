import { timingSafeEqual } from "node:crypto";

/** Vercel Cron y los Database Webhooks envían `Authorization: Bearer <CRON_SECRET>`. */
export function hasCronSecret(req: Request): boolean {
  const secret = process.env.CRON_SECRET;
  const m = /^Bearer (.+)$/.exec(req.headers.get("authorization") ?? "");
  if (!secret || secret.length < 16 || !m) return false;
  const a = Buffer.from(m[1]);
  const b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Traduce el error de la base de datos a la causa probable y cómo resolverla. */
export function diagnoseRpcError(code: string | undefined, message: string | undefined): string {
  const c = code ?? "";
  const m = (message ?? "").toLowerCase();
  if (c === "PGRST202" || c === "42883" || m.includes("could not find the function"))
    return "Falta ejecutar en Supabase la migración 20261101_negocio_pro.sql (o el esquema no se recargó: ejecuta  NOTIFY pgrst, 'reload schema';  en el SQL Editor).";
  if (c === "42P01" || c === "PGRST205") return "Faltan tablas: ejecuta en orden las migraciones 20261101_negocio_pro.sql y 20261102_revolucion.sql.";
  if (c === "42501" || m.includes("permission denied"))
    return "Permiso denegado para service_role: vuelve a ejecutar 20261101_negocio_pro.sql (otorga acceso al esquema private) y revisa que SUPABASE_SERVICE_ROLE_KEY sea la clave service_role, no la anon.";
  if (c === "PGRST301" || c === "PGRST302" || m.includes("jwt") || m.includes("invalid api key"))
    return "SUPABASE_SERVICE_ROLE_KEY no es válida para este proyecto: cópiala de nuevo en Supabase → Project Settings → API.";
  return "Error de base de datos inesperado; revisa el detalle en los logs de Vercel.";
}
