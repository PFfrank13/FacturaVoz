import { inflateRawSync } from "node:zlib";

/**
 * Lector mínimo de .xlsx SIN dependencias (zip + XML de hojas). Devuelve cada hoja como filas de celdas
 * (texto o número). Solo lee: nunca ejecuta fórmulas ni macros. Límite de tamaño para no abusar del servidor.
 */
export type Cell = string | number | null;
export type Sheet = { name: string; rows: Cell[][] };

const MAX_UNZIPPED = 60 * 1024 * 1024; // 60 MB descomprimidos como máximo (protección contra "zip bombs")

function readZip(buf: Buffer): Map<string, Buffer> {
  const out = new Map<string, Buffer>();
  // Fin del directorio central (firma 0x06054b50), buscando desde el final.
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65_557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("El archivo no es un Excel (.xlsx) válido.");
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  let total = 0;
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error("Excel dañado (directorio).");
    const method = buf.readUInt16LE(p + 10);
    const csize = buf.readUInt32LE(p + 20);
    const usize = buf.readUInt32LE(p + 24);
    const nlen = buf.readUInt16LE(p + 28);
    const xlen = buf.readUInt16LE(p + 30);
    const clen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nlen);
    p += 46 + nlen + xlen + clen;
    if (!/^(xl\/(workbook\.xml|sharedStrings\.xml|worksheets\/sheet\d+\.xml|_rels\/workbook\.xml\.rels))$/.test(name)) continue;
    total += usize;
    if (total > MAX_UNZIPPED) throw new Error("El Excel es demasiado grande.");
    const lnlen = buf.readUInt16LE(local + 26);
    const lxlen = buf.readUInt16LE(local + 28);
    const start = local + 30 + lnlen + lxlen;
    const raw = buf.subarray(start, start + csize);
    out.set(name, method === 0 ? Buffer.from(raw) : method === 8 ? inflateRawSync(raw, { maxOutputLength: MAX_UNZIPPED }) : Buffer.alloc(0));
  }
  return out;
}

const ENT: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
function unescapeXml(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g, (_, e: string) =>
    e[0] === "#" ? String.fromCodePoint(e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)) : ENT[e]);
}
function textOf(xml: string): string {
  // Une todos los <t>…</t> (texto enriquecido) e ignora la fonética (<rPh>).
  const clean = xml.replace(/<rPh\b[\s\S]*?<\/rPh>/g, "");
  let s = "";
  for (const m of clean.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>|<t(?:\s[^>]*)?\/>/g)) s += m[1] ?? "";
  return unescapeXml(s);
}
function colIndex(ref: string): number {
  let n = 0;
  for (const ch of ref) {
    const c = ch.charCodeAt(0);
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

export function readXlsx(buf: Buffer, maxRowsPerSheet = 50_000): Sheet[] {
  const files = readZip(buf);
  const wb = files.get("xl/workbook.xml")?.toString("utf8");
  if (!wb) throw new Error("El archivo no es un Excel (.xlsx) válido.");
  const rels = files.get("xl/_rels/workbook.xml.rels")?.toString("utf8") ?? "";
  const relTarget = new Map<string, string>();
  for (const m of rels.matchAll(/<Relationship\b([^>]*)\/?>/g)) {
    const id = /\bId="([^"]+)"/.exec(m[1])?.[1];
    const target = /\bTarget="([^"]+)"/.exec(m[1])?.[1];
    if (id && target) relTarget.set(id, target.replace(/^\/?xl\//, "").replace(/^\//, ""));
  }
  const shared: string[] = [];
  const ss = files.get("xl/sharedStrings.xml")?.toString("utf8");
  if (ss) for (const m of ss.matchAll(/<si>([\s\S]*?)<\/si>/g)) shared.push(textOf(m[1]));

  const sheets: Sheet[] = [];
  let idx = 0;
  for (const m of wb.matchAll(/<sheet\b([^>]*)\/?>/g)) {
    idx++;
    const name = unescapeXml(/\bname="([^"]*)"/.exec(m[1])?.[1] ?? `Hoja${idx}`);
    const rid = /\br:id="([^"]+)"/.exec(m[1])?.[1];
    const target = (rid && relTarget.get(rid)) || `worksheets/sheet${idx}.xml`;
    const xml = files.get(`xl/${target}`)?.toString("utf8");
    if (!xml) continue;
    const rows: Cell[][] = [];
    for (const rm of xml.matchAll(/<row\b([^>]*)>([\s\S]*?)<\/row>|<row\b([^>]*)\/>/g)) {
      if (rows.length >= maxRowsPerSheet) break;
      const rattr = rm[1] ?? rm[3] ?? "";
      const rnum = parseInt(/\br="(\d+)"/.exec(rattr)?.[1] ?? "0", 10);
      const row: Cell[] = [];
      for (const cm of (rm[2] ?? "").matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const attrs = cm[1];
        const body = cm[2] ?? "";
        const ref = /\br="([A-Z]+)\d+"/.exec(attrs)?.[1];
        const t = /\bt="([^"]+)"/.exec(attrs)?.[1] ?? "n";
        const ci = ref ? colIndex(ref) : row.length;
        if (ci < 0 || ci > 300) continue;
        const v = /<v>([\s\S]*?)<\/v>/.exec(body)?.[1];
        let val: Cell = null;
        if (t === "s") val = v != null ? shared[parseInt(v, 10)] ?? "" : null;
        else if (t === "inlineStr") val = textOf(body);
        else if (t === "str" || t === "e") val = v != null ? unescapeXml(v) : null;
        else if (t === "b") val = v === "1" ? "TRUE" : "FALSE";
        else if (v != null && v !== "") { const n = Number(v); val = Number.isFinite(n) ? n : unescapeXml(v); }
        while (row.length < ci) row.push(null);
        row[ci] = val;
      }
      if (rnum > 0) while (rows.length < rnum - 1) rows.push([]); // filas vacías conservan su posición
      rows.push(row);
    }
    sheets.push({ name, rows });
  }
  return sheets;
}
