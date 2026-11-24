/** Yape / Plin / bank payment notices (port of app/lib/logic/notice_parser.dart and finance.dart nameSimilarity). Pure. */

export type ParsedNotice = { app: "yape" | "plin" | "banco" | "otro"; amount: number; payer: string; operation: string; raw: string };

function amountOf(s: string): number | null {
  const m = /(?:S\/\.?|soles?)\s*([0-9][0-9.,]*)/i.exec(s);
  if (!m) return null;
  let v = m[1].replace(/[.,]+$/, "");
  const lastDot = v.lastIndexOf("."), lastComma = v.lastIndexOf(",");
  if (lastDot >= 0 && lastComma >= 0) v = lastComma > lastDot ? v.replace(/\./g, "").replace(/,/g, ".") : v.replace(/,/g, "");
  else if (lastComma >= 0) v = v.length - lastComma - 1 === 3 ? v.replace(/,/g, "") : v.replace(/,/g, ".");
  else if (lastDot >= 0 && v.length - lastDot - 1 === 3 && v.indexOf(".") !== lastDot) v = v.replace(/\./g, "");
  const n = Number(v);
  return Number.isFinite(n) && n > 0 && n <= 10_000_000 ? n : null;
}

/** "¡Yape! JUAN PEREZ te envió un pago por S/ 25.50. El cód. de seguridad es: 123" → yape, 25.50, JUAN PEREZ. */
export function parsePaymentNotice(text: string): ParsedNotice | null {
  const raw = text.trim();
  if (!raw) return null;
  const low = raw.toLowerCase();
  const amount = amountOf(raw);
  if (amount == null) return null;
  const app = low.includes("yape") ? "yape" : low.includes("plin") ? "plin" : /transferencia|bcp|interbank|bbva|scotiabank|abono/.test(low) ? "banco" : "otro";
  const L = "A-Za-zÁÉÍÓÚÑáéíóúñ";
  const p1 = new RegExp(`(?:yape!?|plin!?)\\s*[:\\-]?\\s*([A-ZÁÉÍÓÚÑ][${L}.\\s]{2,60}?)\\s+te\\s+(?:envi[oó]|yape[oó]|pag[oó])`, "i").exec(raw);
  const p2 = new RegExp(`([A-ZÁÉÍÓÚÑ][${L}.\\s]{2,60}?)\\s+te\\s+(?:envi[oó]|yape[oó]|pag[oó])`).exec(raw);
  const p3 = new RegExp(`(?:de|remitente:?)\\s+([A-ZÁÉÍÓÚÑ][${L}.\\s]{2,60}?)(?:\\s+por|\\s*[.,]|$)`, "i").exec(raw);
  const payer = (p1?.[1] ?? p2?.[1] ?? p3?.[1] ?? "").trim();
  const op = /(?:operaci[oó]n|n[°º]\s*de\s*operaci[oó]n|c[oó]d(?:igo)?\.?(?:\s*de\s*seguridad)?)\s*(?:es)?\s*[:#]?\s*([A-Za-z0-9-]{3,20})/i.exec(raw);
  return { app, amount, payer, operation: op?.[1] ?? "", raw: raw.slice(0, 500) };
}

const stop = new Set(["sac", "srl", "eirl", "sa", "saa", "de", "la", "el", "los", "las", "del", "y", "e", "cia", "sociedad", "anonima", "cerrada", "empresa"]);
const tokens = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter(t => t && !stop.has(t));

/** 0..1: how alike two names are. Tolerates Yape abbreviations ("Juan P. Pere*"). */
export function nameSimilarity(a: string, b: string): number {
  const ta = tokens(a), tb = tokens(b);
  if (!ta.length || !tb.length) return 0;
  let hits = 0;
  const used = new Set<number>();
  for (const x of ta) for (let j = 0; j < tb.length; j++) {
    if (used.has(j)) continue;
    const y = tb[j];
    if (x === y || (x.length >= 3 && y.startsWith(x)) || (y.length >= 3 && x.startsWith(y)) || (x.length === 1 && y.startsWith(x))) { hits++; used.add(j); break; }
  }
  return hits / Math.min(ta.length, tb.length);
}

/** Receivables with exactly that balance, the ones whose client looks like the payer first. */
export function noticeMatches<T extends { balance: number; client: string }>(amount: number, open: T[], payer: string): T[] {
  return open.filter(i => Math.abs(i.balance - amount) < 0.01).sort((a, b) => nameSimilarity(payer, b.client) - nameSimilarity(payer, a.client));
}
