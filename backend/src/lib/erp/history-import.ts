/** Old receipts from SUNAT's sales register, Excel or another system (port of app/lib/import_logic.dart). Pure and tested. */

export const maxImportRows = 200_000;

export type ImportRow = { client: string; tax_id: string; description: string; number: string; date: string; currency: "PEN" | "USD"; amount: string };
export type ParsedImport = { rows: ImportRow[]; rejected: number; columns: Record<string, string>; error?: string };

const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");

/** UTF-8, or Latin-1 when the file comes from SUNAT in Windows-1252. */
export function decodeImportBytes(bytes: Uint8Array): string {
  const u = new TextDecoder("utf-8").decode(bytes);
  const bad = (u.match(/�/g) ?? []).length;
  const text = bad > 3 ? new TextDecoder("latin1").decode(bytes) : u;
  return text.startsWith("﻿") ? text.slice(1) : text;
}

export function detectDelimiter(firstLine: string): string {
  let best = ",", count = 0;
  for (const d of [",", ";", "|", "\t"]) {
    const n = firstLine.split(d).length - 1;
    if (n > count) { best = d; count = n; }
  }
  return best;
}

export function parseCsvText(text: string, delimiter: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else quoted = false; }
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === delimiter) { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.some(x => x.trim())) rows.push(row);
      row = [];
    } else cell += c;
  }
  row.push(cell);
  if (row.some(x => x.trim())) rows.push(row);
  return rows;
}

/** "S/ 1,234.56", "1.234,56", "1234,5" → 1234.56. null when it is not a positive amount. */
export function parseImportAmount(raw: string): number | null {
  let s = raw.replace(/[^0-9,.-]/g, "");
  if (!s || s === "-" || s.startsWith("-")) return null;
  const lastComma = s.lastIndexOf(","), lastDot = s.lastIndexOf(".");
  if (lastComma >= 0 && lastDot >= 0) s = lastComma > lastDot ? s.replace(/\./g, "").replace(/,/g, ".") : s.replace(/,/g, "");
  else if (lastComma >= 0) {
    const after = s.length - lastComma - 1;
    s = after === 3 && s.indexOf(",") === lastComma && lastComma > 0 && s.length > 4 ? s.replace(/,/g, "") : s.replace(/,/g, ".");
  } else if (lastDot >= 0 && s.indexOf(".") !== lastDot) s = s.replace(/\./g, "");
  if (!/^\d*\.?\d*$/.test(s)) return null;
  const v = Number(s);
  return Number.isFinite(v) && v > 0 && v <= 99_999_999 ? v : null;
}

/** dd/MM/yyyy, dd-MM-yyyy or yyyy-MM-dd → yyyy-MM-dd ('' when unknown). */
export function parseDateIso(raw: string): string {
  const s = raw.trim();
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(s), dmy = /^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})/.exec(s);
  let y: number, m: number, d: number;
  if (iso) { y = +iso[1]; m = +iso[2]; d = +iso[3]; }
  else if (dmy) { d = +dmy[1]; m = +dmy[2]; y = +dmy[3]; }
  else return "";
  if (y < 1990 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return "";
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCMonth() !== m - 1) return "";
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** Text date or Excel serial number (46025 → 2026-01-04). */
function dateCell(raw: string): string {
  const iso = parseDateIso(raw);
  if (iso) return iso;
  const n = Number(raw.trim());
  if (!raw.trim() || !Number.isFinite(n) || n < 20000 || n > 80000) return "";
  return new Date(Date.UTC(1899, 11, 30) + Math.floor(n) * 86_400_000).toISOString().slice(0, 10);
}

/** Header row among the first 15 (Excel files often have titles or blank rows on top). */
export function headerRowIndex(table: string[][]): number {
  const keys = ["importe", "total", "monto", "cliente", "razonsocial", "fecha", "ruc", "dni", "descripcion", "serie"];
  let best = 0, bestScore = -1;
  for (let k = 0; k < table.length && k < 15; k++) {
    const h = table[k].map(norm);
    const score = keys.filter(key => h.some(x => x.includes(key))).length;
    if (score > bestScore) { best = k; bestScore = score; }
  }
  return best;
}

export function parseImportTable(source: string[][]): ParsedImport {
  const table = source.slice(headerRowIndex(source));
  if (table.length < 2) return { rows: [], rejected: 0, columns: {}, error: "No encontramos filas con datos." };
  const raw = table[0].map(h => String(h ?? "").trim());
  const h = raw.map(norm);
  const taken = new Set<number>();
  const pick = (exact: string[], contains: string[]): number | null => {
    for (const e of exact) { const i = h.indexOf(e); if (i >= 0 && !taken.has(i)) { taken.add(i); return i; } }
    for (const c of contains) for (let i = 0; i < h.length; i++) if (!taken.has(i) && h[i].includes(c)) { taken.add(i); return i; }
    return null;
  };
  const amountI = pick(["importetotal", "totalcp", "montototal", "total", "importe", "monto"], ["importetotal", "total", "importe", "monto"]);
  const clientI = pick(["cliente", "razonsocial", "denominacion", "nombre", "nombrecliente"], ["razonsocial", "cliente", "denominacion", "nombre"]);
  const taxI = pick(["ruc", "dni", "nrodocidentidad", "numerodocumentoidentidad", "nrodocumentoidentidad", "docidentidad"], ["docidentidad", "ruc", "dni"]);
  const descI = pick(["servicio", "descripcion", "concepto", "detalle", "glosa", "producto"], ["servicio", "descripcion", "concepto", "glosa"]);
  const dateI = pick(["fechaemision", "fechadeemision", "femision", "fecha"], ["fechaemision", "fecha"]);
  const curI = pick(["moneda", "mon"], ["moneda"]);
  const serieI = pick(["serie", "seriecp", "seriedecomprobante"], []);
  const numI = pick(["numerodecomprobante", "nrocomprobante", "nrocp", "numerocp", "numero", "correlativo", "nrodocumento", "comprobante"], ["numerocp", "nrocp", "comprobante"]);
  if (amountI == null) return { rows: [], rejected: 0, columns: {}, error: "No encontramos la columna del importe (por ejemplo «Importe total» o «Total»)." };
  if (clientI == null && descI == null) return { rows: [], rejected: 0, columns: {}, error: "No encontramos la columna del cliente ni la del servicio." };
  const cell = (r: string[], i: number | null) => (i == null || i >= r.length ? "" : String(r[i] ?? "").trim());
  const rows: ImportRow[] = [];
  let rejected = 0;
  for (let k = 1; k < table.length; k++) {
    if (rows.length >= maxImportRows) { rejected += table.length - k; break; }
    const r = table[k];
    const amount = parseImportAmount(cell(r, amountI));
    if (amount == null) { rejected++; continue; }
    let number = cell(r, numI);
    const serie = cell(r, serieI);
    if (serie && number && !number.includes("-")) number = `${serie}-${number}`;
    const cur = cell(r, curI).toUpperCase();
    rows.push({ client: cell(r, clientI), tax_id: cell(r, taxI), description: cell(r, descI), number, date: dateCell(cell(r, dateI)),
      currency: cur === "USD" || cur === "DOLARES" || cur === "US$" ? "USD" : "PEN", amount: amount.toFixed(2) });
  }
  const name = (i: number | null) => (i == null ? "" : raw[i]);
  return { rows, rejected, columns: { Cliente: name(clientI), Servicio: name(descI), Importe: name(amountI), Fecha: name(dateI),
    "Número": numI == null ? "" : serieI == null ? name(numI) : `${name(serieI)} + ${name(numI)}` } };
}

export function parseImportText(text: string): ParsedImport {
  const lines = text.split(/\r?\n/).filter(l => l.trim()).slice(0, 15);
  if (!lines.length) return { rows: [], rejected: 0, columns: {}, error: "El archivo está vacío." };
  // The busiest of the first lines decides the separator (SUNAT files often start with a title line).
  const count = (l: string) => l.split(detectDelimiter(l)).length;
  const busiest = lines.reduce((a, l) => (count(l) > count(a) ? l : a));
  return parseImportTable(parseCsvText(text, detectDelimiter(busiest)));
}

/** Joins several parsed files (by month, by year…) into one import. */
export function mergeParsed(parts: ParsedImport[]): ParsedImport {
  const ok = parts.filter(p => !p.error);
  if (!ok.length) return parts[0] ?? { rows: [], rejected: 0, columns: {}, error: "No elegiste archivos." };
  return { rows: ok.flatMap(p => p.rows).slice(0, maxImportRows), rejected: ok.reduce((a, p) => a + p.rejected, 0), columns: ok[0].columns };
}
