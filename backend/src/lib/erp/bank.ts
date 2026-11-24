/** Bank reconciliation (port of app/lib/logic/bank_match.dart): read a statement and suggest which invoice each deposit pays. */

export type BankLine = { date: string; description: string; amount: number; reference: string };
export type Receivable = { invoiceId: string; number: string; client: string; balance: number; issueDate: string };
export type MatchSuggestion = { line: BankLine; invoice: Receivable; score: number; why: string };

const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, " ");
const days = (a: string, b: string) => {
  const da = Date.parse(a), db = Date.parse(b);
  return Number.isNaN(da) || Number.isNaN(db) ? 999 : Math.abs(Math.round((da - db) / 86_400_000));
};

/** Same id as the mobile app, so the same statement never loads twice. */
export function fingerprint(l: BankLine): string {
  const raw = `${l.date}|${l.amount.toFixed(2)}|${l.reference.trim()}|${l.description.trim().toLowerCase()}`;
  const bytes = new TextEncoder().encode(raw);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

/** Best invoice for each deposit (only suggestions with score ≥ 0.5; the person confirms). */
export function suggestMatches(lines: BankLine[], open: Receivable[]): MatchSuggestion[] {
  const out: MatchSuggestion[] = [];
  const used = new Set<string>();
  for (const l of lines.filter(x => x.amount > 0)) {
    let best: MatchSuggestion | null = null;
    for (const r of open) {
      if (used.has(r.invoiceId)) continue;
      let score = 0;
      const why: string[] = [];
      const diff = Math.abs(r.balance - l.amount);
      if (diff < 0.01) { score += 0.6; why.push("monto exacto"); }
      else if (diff <= 1) { score += 0.35; why.push("monto casi igual"); }
      else continue;
      const desc = norm(`${l.description} ${l.reference}`);
      const words = norm(r.client).split(" ").filter(w => w.length >= 4);
      if (words.length && words.filter(w => desc.includes(w)).length >= (words.length >= 2 ? 2 : 1)) { score += 0.3; why.push("nombre del cliente"); }
      const num = r.number.replace(/\D/g, "").replace(/^0+/, "");
      if (num.length >= 3 && desc.includes(num)) { score += 0.2; why.push("número de factura"); }
      if (days(l.date, r.issueDate) <= 45) score += 0.1;
      if (!best || score > best.score) best = { line: l, invoice: r, score: Math.min(1, score), why: why.join(" + ") };
    }
    if (best && best.score >= 0.5) { out.push(best); used.add(best.invoice.invoiceId); }
  }
  return out;
}

/** Splits CSV text (comma, semicolon or tab; quotes allowed) into rows. */
export function parseCsv(text: string): string[][] {
  const first = text.split(/\r?\n/, 1)[0] ?? "";
  const sep = [";", "\t", ","].map(s => [s, first.split(s).length] as const).sort((a, b) => b[1] - a[1])[0][0];
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === sep) { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.some(c => c.trim())) rows.push(row);
      row = [];
    } else cell += ch;
  }
  row.push(cell);
  if (row.some(c => c.trim())) rows.push(row);
  return rows;
}

/** Reads a statement table: finds date, description, amount (or credit/debit) and reference columns. */
export function parseBankTable(table: string[][]): BankLine[] {
  if (table.length < 2) return [];
  const n = (s: string) => norm(s).replace(/ /g, "");
  let hi = 0;
  for (let k = 0; k < table.length && k < 15; k++) {
    const h = table[k].map(n);
    if (h.some(x => x.includes("fecha")) && h.some(x => x.includes("monto") || x.includes("importe") || x.includes("abono") || x.includes("cargo"))) { hi = k; break; }
  }
  const h = table[hi].map(n);
  const col = (keys: string[]) => { for (const k of keys) { const i = h.findIndex(x => x.includes(k)); if (i >= 0) return i; } return null; };
  const di = col(["fechaoperacion", "fecha"]), de = col(["descripcion", "detalle", "concepto", "glosa", "movimiento"]);
  const mo = col(["monto", "importe"]), ab = col(["abono", "ingreso", "credito"]), ca = col(["cargo", "egreso", "debito"]);
  const re = col(["operacion", "referencia", "nrooperacion", "numero"]);
  const amt = (s: string): number | null => {
    let t = s.replace(/[^0-9,.-]/g, "");
    if (!t) return null;
    const neg = t.startsWith("-");
    t = t.replace(/-/g, "");
    if (t.includes(",") && t.includes(".")) t = t.lastIndexOf(",") > t.lastIndexOf(".") ? t.replace(/\./g, "").replace(",", ".") : t.replace(/,/g, "");
    else if (t.includes(",")) t = /,\d{1,2}$/.test(t) ? t.replace(",", ".") : t.replace(/,/g, "");
    const v = Number(t);
    return Number.isFinite(v) ? (neg ? -v : v) : null;
  };
  const date = (s: string) => {
    const t = s.trim();
    const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(t);
    if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;
    const dmy = /^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})/.exec(t);
    if (dmy) { const y = dmy[3].length === 2 ? `20${dmy[3]}` : dmy[3]; return `${y}-${dmy[2].padStart(2, "0")}-${dmy[1].padStart(2, "0")}`; }
    return "";
  };
  const cell = (r: string[], i: number | null) => i == null || i >= r.length ? "" : r[i].trim();
  const out: BankLine[] = [];
  for (const r of table.slice(hi + 1)) {
    const d = date(cell(r, di));
    if (!d) continue;
    let v: number | null = mo != null ? amt(cell(r, mo)) : null;
    if (v == null || v === 0) {
      const a = ab == null ? null : amt(cell(r, ab)), c = ca == null ? null : amt(cell(r, ca));
      if (a != null && a !== 0) v = Math.abs(a);
      else if (c != null && c !== 0) v = -Math.abs(c);
    }
    if (v == null || v === 0) continue;
    out.push({ date: d, description: cell(r, de), amount: v, reference: cell(r, re) });
  }
  return out;
}

/** Next date a monthly template runs (day 29–31 falls on the month's last day). */
export function nextRun(day: number, today: string): string {
  const [y, m, d] = today.split("-").map(Number);
  const last = (yy: number, mm: number) => new Date(Date.UTC(yy, mm, 0)).getUTCDate();
  const pick = (yy: number, mm: number) => `${yy}-${String(mm).padStart(2, "0")}-${String(Math.min(day, last(yy, mm))).padStart(2, "0")}`;
  if (Math.min(day, last(y, m)) >= d) return pick(y, m);
  return m === 12 ? pick(y + 1, 1) : pick(y, m + 1);
}
