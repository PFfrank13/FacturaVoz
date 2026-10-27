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
