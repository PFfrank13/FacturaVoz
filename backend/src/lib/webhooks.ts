import { createHmac } from "node:crypto";

/**
 * Webhooks salientes de FacturaVoz (a los sistemas del cliente). Mismo esquema que Solvex Hub:
 *   FacturaVoz-Event, FacturaVoz-Timestamp, FacturaVoz-Signature: v1=HMAC-SHA256(secreto, timestamp + "." + cuerpo)
 * Reintentos con espera creciente: 1, 2, 5, 10, 30 min, 1, 2, 4, 8, 12, 24 h (12 intentos en total).
 */
export const BACKOFF_MIN = [1, 2, 5, 10, 30, 60, 120, 240, 480, 720, 1440];

export function signWebhook(secret: string, timestamp: number, body: string): string {
  return "v1=" + createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");
}

export function nextAttempt(attempts: number, now = Date.now()): string {
  const m = BACKOFF_MIN[Math.min(attempts, BACKOFF_MIN.length - 1)];
  return new Date(now + m * 60_000).toISOString();
}

/** Solo URLs https públicas (evita que una empresa use el servidor para llegar a redes internas). */
export function safeWebhookUrl(raw: string): boolean {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return false;
  }
  if (u.protocol !== "https:" || u.username || u.password) return false;
  const h = u.hostname.toLowerCase();
  if (h === "localhost" || h.endsWith(".local") || h.endsWith(".internal") || /^\[?::1\]?$/.test(h)) return false;
  if (/^(10\.|127\.|169\.254\.|192\.168\.|0\.|172\.(1[6-9]|2\d|3[01])\.)/.test(h)) return false;
  if (/^\d+$/.test(h)) return false;
  return true;
}
