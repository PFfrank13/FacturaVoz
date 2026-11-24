/**
 * Destinos internos permitidos después de iniciar sesión (evita redirecciones abiertas).
 * Solo rutas del espacio de trabajo de una empresa: /erp/{uuid}[/{módulo}], /solvex/ir/{uuid} y /login/nueva
 * (crear contraseña tras abrir el enlace del correo).
 */
const ALLOWED = /^\/(?:login\/nueva|erp\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:\/[a-z0-9_-]{1,40})?|solvex\/ir\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;

export function safeNext(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 120) return null;
  return ALLOWED.test(value) ? value : null;
}
