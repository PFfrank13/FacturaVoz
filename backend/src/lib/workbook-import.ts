import type { Cell, Sheet } from "./xlsx";

/**
 * Importador relacional de un libro Excel con varias hojas (clientes, comprobantes, detalle y catálogo).
 *
 * 1) Clasifica cada hoja por sus COLUMNAS (no por su nombre). Hojas de leyenda/instrucciones se ignoran.
 * 2) Normaliza: tipo (factura, boleta, nota de crédito), estado (pagada, parcial, pendiente, vencida, anulada),
 *    montos CON IGV tal como vienen (subtotal, descuento, base, IGV, total), fechas, documentos de identidad.
 * 3) Relaciona: clientes por id_cliente, productos por codigo_item, líneas por id_factura.
 * 4) Devuelve una VISTA PREVIA (conteos y totales) y el paquete listo para guardar por bloques.
 *
 * Cálculo del total neto (el mismo que usan Inicio, Reportes, Mi negocio y el Copiloto):
 *   neto = Σ total de facturas y boletas NO anuladas − Σ total de notas de crédito NO anuladas, por moneda.
 */

export type DocKind = "factura" | "boleta" | "nota_credito" | "nota_venta";
export type PayState = "pagada" | "parcial" | "pendiente" | "vencida" | "anulada";

export type WbClient = {
  ref: string; name: string; doc_type: string | null; doc: string | null; address: string | null;
  district: string | null; phone: string | null; email: string | null;
};
export type WbProduct = { code: string; name: string; category: string | null; unit: "NIU" | "ZZ"; price: number; taxed: boolean };
export type WbLine = { code: string | null; description: string; qty: number; price: number; discount: number; total: number };
export type WbDoc = {
  ref: string; kind: DocKind; number: string; issue: string; due: string | null; client_ref: string | null;
  client_name: string; client_doc_type: string | null; client_doc: string | null; client_address: string | null; client_email: string | null;
  currency: string; subtotal: number; discount: number; base: number; tax: number; total: number; state: PayState;
  paid: number; balance: number; method: string | null; voided: boolean; related_number: string | null; lines: WbLine[];
};
export type Warning = { code: string; message: string; count: number; examples: string[] };
export type MoneyByCur = Record<string, number>;
export type Preview = {
  sheets: { name: string; role: Role; rows: number }[];
  counts: { clients: number; products: number; documents: number; facturas: number; boletas: number; credit_notes: number; notas_venta: number; lines: number; voided: number; skipped: number };
  totals: { sales: MoneyByCur; credit_notes: MoneyByCur; net: MoneyByCur; receivable: MoneyByCur; collected: MoneyByCur };
  warnings: Warning[];
};
export type Payload = { clients: WbClient[]; products: WbProduct[]; docs: WbDoc[] };
export type Role = "clientes" | "comprobantes" | "detalle" | "catalogo" | "ignorada";

// ───────────────────────── columnas y sinónimos ─────────────────────────
export function normHeader(s: unknown): string {
  return String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}
const F = {
  client_ref: ["id_cliente", "codigo_cliente", "cod_cliente", "cliente_id", "cliente_codigo"],
  client_name: ["cliente_nombre_razon_social", "nombre_razon_social", "razon_social", "nombre_cliente", "cliente_nombre", "nombres_razon_social", "nombre", "cliente", "denominacion"],
  client_doc_type: ["tipo_documento", "tipo_doc", "cliente_tipo_doc", "cliente_tipo_documento", "tipo_doc_cliente", "tipo_documento_identidad"],
  client_doc: ["numero_documento", "nro_documento", "num_documento", "documento", "ruc_dni", "dni_ruc", "cliente_ruc_dni", "cliente_documento", "cliente_numero_documento", "ruc", "dni", "doc_identidad", "num_doc"],
  address: ["direccion", "cliente_direccion", "domicilio", "direccion_fiscal"],
  district: ["distrito", "cliente_distrito"],
  phone: ["telefono", "celular", "whatsapp", "cliente_telefono", "movil"],
  email: ["correo", "email", "correo_electronico", "cliente_correo", "cliente_email", "e_mail"],
  doc_ref: ["id_factura", "id_comprobante", "codigo_factura", "id_documento", "id_venta", "factura_id", "comprobante_id"],
  kind: ["tipo_comprobante", "tipo_de_comprobante", "comprobante_tipo", "tipo_documento_venta", "tipo_doc_venta", "tipo_cpe", "tipo"],
  serie: ["serie", "serie_comprobante"],
  numero: ["numero", "correlativo", "nro", "num", "numero_correlativo"],
  full_number: ["numero_comprobante", "comprobante", "serie_numero", "nro_comprobante", "documento_venta"],
  issue: ["fecha_emision", "fecha", "emision", "fecha_de_emision"],
  due: ["fecha_vencimiento", "vencimiento", "fecha_de_vencimiento", "fecha_pago_limite"],
  currency: ["moneda", "divisa", "tipo_moneda"],
  subtotal: ["subtotal", "sub_total", "importe_bruto"],
  discount: ["descuento", "descuentos", "dscto", "descuento_total", "descuento_linea"],
  base: ["base_imponible", "op_gravada", "op_gravadas", "valor_venta", "gravada", "base", "monto_base"],
  tax: ["igv", "impuesto", "monto_igv", "igv_total"],
  total: ["total", "importe_total", "monto_total", "total_comprobante", "precio_total", "total_linea", "importe"],
  state: ["estado", "estado_pago", "situacion", "estado_comprobante"],
  paid: ["pagado", "monto_pagado", "cobrado", "abonado", "total_pagado", "monto_cobrado"],
  balance: ["saldo", "saldo_pendiente", "pendiente", "por_cobrar", "deuda"],
  method: ["metodo_pago", "medio_pago", "forma_pago", "metodo_de_pago"],
  related: ["doc_referencia", "documento_referencia", "referencia", "comprobante_referencia", "doc_modificado", "documento_afectado"],
  line_no: ["linea", "item_linea", "nro_linea", "orden"],
  code: ["codigo_item", "codigo_producto", "cod_producto", "codigo", "sku", "cod_item", "item_codigo"],
  description: ["descripcion", "producto", "detalle", "concepto", "nombre_producto", "descripcion_item", "item"],
  unit: ["unidad", "unidad_medida", "um", "und"],
  qty: ["cantidad", "cant", "qty"],
  price: ["precio_unitario_con_igv", "precio_con_igv", "precio_unitario", "precio", "pu", "precio_venta", "valor_unitario"],
  category: ["categoria", "rubro", "familia", "linea_producto"],
  taxed: ["afecto_igv", "afecto", "gravado", "afectacion_igv"],
} as const;
type Field = keyof typeof F;

type Cols = Partial<Record<Field, number>>;
function mapColumns(header: Cell[], fields: Field[]): Cols {
  const norm = header.map(normHeader);
  const out: Cols = {};
  const used = new Set<number>();
  for (const f of fields) {
    for (const syn of F[f]) {
      const i = norm.findIndex((h, k) => h === syn && !used.has(k));
      if (i >= 0) { out[f] = i; used.add(i); break; }
    }
  }
  return out;
}
const ALL_FIELDS = Object.keys(F) as Field[];

function findHeader(rows: Cell[][]): { at: number; cols: Cols } | null {
  let best: { at: number; cols: Cols; n: number } | null = null;
  for (let r = 0; r < Math.min(rows.length, 15); r++) {
    const cols = mapColumns(rows[r] ?? [], ALL_FIELDS);
    const n = Object.keys(cols).length;
    if (n >= 3 && (!best || n > best.n)) best = { at: r, cols, n };
  }
  return best ? { at: best.at, cols: best.cols } : null;
}

const CLIENT_F: Field[] = ["client_ref", "client_name", "client_doc_type", "client_doc", "address", "district", "phone", "email"];
const DOC_F: Field[] = ["doc_ref", "kind", "serie", "numero", "full_number", "issue", "due", "client_ref", "client_name", "client_doc_type", "client_doc",
  "address", "email", "currency", "subtotal", "discount", "base", "tax", "total", "state", "paid", "balance", "method", "related"];
const LINE_F: Field[] = ["doc_ref", "line_no", "code", "description", "unit", "qty", "price", "discount", "base", "tax", "total"];
const CAT_F: Field[] = ["code", "description", "category", "unit", "price", "taxed"];

export function classify(sheet: Sheet): { role: Role; at: number; cols: Cols } {
  const h = findHeader(sheet.rows);
  if (!h) return { role: "ignorada", at: -1, cols: {} };
  const header = sheet.rows[h.at];
  const has = (c: Cols, ...f: Field[]) => f.every((x) => c[x] !== undefined);
  const line = mapColumns(header, LINE_F);
  if (has(line, "doc_ref", "qty") && (line.price !== undefined || line.total !== undefined)) return { role: "detalle", at: h.at, cols: line };
  const doc = mapColumns(header, DOC_F);
  if ((doc.doc_ref !== undefined || has(doc, "serie", "numero") || doc.full_number !== undefined) && doc.total !== undefined
      && (doc.kind !== undefined || doc.serie !== undefined || doc.state !== undefined || doc.issue !== undefined)) return { role: "comprobantes", at: h.at, cols: doc };
  const cat = mapColumns(header, CAT_F);
  if (has(cat, "code", "description", "price") && line.qty === undefined) return { role: "catalogo", at: h.at, cols: cat };
  const cli = mapColumns(header, CLIENT_F);
  if (cli.client_name !== undefined && (cli.client_ref !== undefined || cli.client_doc !== undefined) && doc.total === undefined) return { role: "clientes", at: h.at, cols: cli };
  return { role: "ignorada", at: h.at, cols: {} };
}

// ───────────────────────── valores ─────────────────────────
const str = (v: Cell | undefined): string => (v == null ? "" : String(v)).replace(/\s+/g, " ").trim();
export function num(v: Cell | undefined): number | null {
  if (v == null || v === "") return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  let s = String(v).replace(/[^\d,.\-]/g, "");
  if (!s || s === "-") return null;
  const lc = s.lastIndexOf(","), ld = s.lastIndexOf(".");
  if (lc > ld) s = s.replace(/\./g, "").replace(",", "."); // 1.234,50
  else s = s.replace(/,/g, ""); // 1,234.50
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}
const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
export function isoDate(v: Cell | undefined): string | null {
  if (v == null || v === "") return null;
  if (typeof v === "number") {
    if (v < 20000 || v > 80000) return null; // número de serie de Excel (1954–2119)
    const d = new Date(Date.UTC(1899, 11, 30) + Math.floor(v) * 864e5);
    return d.toISOString().slice(0, 10);
  }
  const s = String(v).trim();
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(s);
  if (m) return valid(+m[1], +m[2], +m[3]);
  m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})/.exec(s);
  if (m) return valid(m[3].length === 2 ? 2000 + +m[3] : +m[3], +m[2], +m[1]);
  return null;
  function valid(y: number, mo: number, d: number) {
    const dt = new Date(Date.UTC(y, mo - 1, d));
    return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d ? dt.toISOString().slice(0, 10) : null;
  }
}
export function rucValid(ruc: string): boolean {
  if (!/^(10|15|16|17|20)\d{9}$/.test(ruc)) return false;
  const w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const s = w.reduce((a, x, i) => a + x * +ruc[i], 0);
  const r = 11 - (s % 11);
  return (r === 10 ? 0 : r === 11 ? 1 : r) === +ruc[10];
}
/** Documento del cliente: '6' RUC, '1' DNI, '4' carné de extranjería, '7' pasaporte. Inválido → null ("sin documento"). */
export function normDoc(typeRaw: string, docRaw: string): { type: string | null; doc: string | null; invalid: boolean } {
  const t = normHeader(typeRaw);
  const raw = docRaw.replace(/\s+/g, "").toUpperCase();
  if (!raw || /^[-0]+$/.test(raw) || raw === "SD" || raw === "S_D") return { type: null, doc: null, invalid: false };
  const digits = raw.replace(/\D/g, "");
  if (t.includes("ruc") || t === "6" || (!t && digits.length === 11 && digits === raw)) {
    return rucValid(digits) && digits === raw ? { type: "6", doc: digits, invalid: false } : { type: null, doc: null, invalid: true };
  }
  if (t.includes("dni") || t === "1" || (!t && digits.length === 8)) {
    return /^\d{8}$/.test(raw) ? { type: "1", doc: raw, invalid: false } : { type: null, doc: null, invalid: true };
  }
  if (t.includes("extranj") || t === "ce" || t === "4") return /^[A-Z0-9]{6,12}$/.test(raw) ? { type: "4", doc: raw, invalid: false } : { type: null, doc: null, invalid: true };
  if (t.includes("pasaporte") || t === "7") return /^[A-Z0-9]{5,15}$/.test(raw) ? { type: "7", doc: raw, invalid: false } : { type: null, doc: null, invalid: true };
  return { type: null, doc: null, invalid: true };
}
export function normKind(raw: string, serie: string): DocKind | null {
  const k = normHeader(raw);
  if (/credito|^nc$|^07$|^7$/.test(k)) return "nota_credito";
  if (/debito|^nd$|^08$/.test(k)) return null; // notas de débito: no soportadas aún
  if (/boleta|^bv$|^03$|^3$/.test(k)) return "boleta";
  if (/factura|^fa$|^01$|^1$/.test(k)) return "factura";
  if (/nota_de_venta|nota_venta|ticket|recibo/.test(k)) return "nota_venta";
  if (!k) {
    const s = serie.toUpperCase();
    if (/^[FB]C/.test(s)) return "nota_credito";
    if (s.startsWith("F")) return "factura";
    if (s.startsWith("B")) return "boleta";
  }
  return null;
}
export function normState(raw: string): PayState | null {
  const s = normHeader(raw);
  if (!s) return null;
  if (/anulad|baja|rechazad|cancelada_por_nc|extornad/.test(s)) return "anulada";
  if (/parcial|a_cuenta|adelanto/.test(s)) return "parcial";
  if (/vencid|moros/.test(s)) return "vencida";
  if (/pagad|cobrad|cancelad|liquidad/.test(s)) return "pagada";
  if (/pendient|por_cobrar|emitid|aceptad|credito|aplicad/.test(s)) return "pendiente";
  return null;
}
function normCurrency(raw: string): string {
  const s = normHeader(raw);
  if (!s || /^(pen|s|soles?|sol|nuevos_soles)$/.test(s)) return "PEN";
  if (/^(usd|us|dolar|dolares|us_dolares|\$)$/.test(s) || s.includes("dolar")) return "USD";
  if (/^eur|euro/.test(s)) return "EUR";
  return /^[a-z]{3}$/.test(s) ? s.toUpperCase() : "PEN";
}
function docNumber(serie: string, numero: string, full: string): string | null {
  let s = serie.toUpperCase().replace(/\s+/g, "");
  let n = numero.replace(/\s+/g, "");
  if ((!s || !n) && full) {
    const m = /^([A-Z0-9]{1,4})\s*-\s*(\d{1,10})$/i.exec(full.trim());
    if (m) { s = m[1].toUpperCase(); n = m[2]; } else return full.trim().slice(0, 60) || null;
  }
  if (!s && !n) return null;
  if (/^\d+(\.0+)?$/.test(n)) n = String(parseInt(n, 10)).padStart(8, "0");
  return (s ? `${s}-${n}` : n).slice(0, 60);
}
const looksLikeId = (name: string, ref: string) => !!name && (name === ref || /^(cli|cl|c|id)[-_ ]?\d+$/i.test(name) || /^\d{1,6}$/.test(name));
function unitOf(raw: string, fallbackService: boolean): "NIU" | "ZZ" {
  const u = normHeader(raw);
  if (/^(zz|serv|servicio|servicios|hora|horas|hr|mes|sesion)/.test(u)) return "ZZ";
  if (u) return "NIU";
  return fallbackService ? "ZZ" : "NIU";
}

// ───────────────────────── análisis ─────────────────────────
class Warnings {
  private m = new Map<string, Warning>();
  add(code: string, message: string, example: string) {
    const w = this.m.get(code) ?? { code, message, count: 0, examples: [] };
    w.count++;
    if (w.examples.length < 5 && example) w.examples.push(example);
    this.m.set(code, w);
  }
  list() { return [...this.m.values()]; }
}
const addCur = (o: MoneyByCur, cur: string, v: number) => { o[cur] = r2((o[cur] ?? 0) + v); };

export function analyzeWorkbook(sheets: Sheet[], defaultRate = 18): { preview: Preview; payload: Payload } {
  const warn = new Warnings();
  const roles = sheets.map((s) => ({ s, ...classify(s) }));
  const cell = (row: Cell[], cols: Cols, f: Field) => (cols[f] === undefined ? undefined : row[cols[f]!]);
  const dataRows = (x: { s: Sheet; at: number }) => x.s.rows.slice(x.at + 1).filter((r) => r.some((c) => c != null && String(c).trim() !== ""));

  // Clientes
  const clients = new Map<string, WbClient>();
  for (const x of roles.filter((r) => r.role === "clientes")) {
    for (const row of dataRows(x)) {
      const ref = str(cell(row, x.cols, "client_ref"));
      let name = str(cell(row, x.cols, "client_name")).slice(0, 120);
      const d = normDoc(str(cell(row, x.cols, "client_doc_type")), str(cell(row, x.cols, "client_doc")));
      if (d.invalid) warn.add("doc_invalido", "Documento de identidad no válido: se guardó \"sin documento\"", `${ref || name}: ${str(cell(row, x.cols, "client_doc"))}`);
      if (looksLikeId(name, ref)) name = "";
      if (!name) { warn.add("cliente_sin_nombre", "Cliente sin nombre en el archivo", ref); name = "Cliente sin nombre"; }
      const key = ref || `doc:${d.doc ?? ""}|${name.toLowerCase()}`;
      if (clients.has(key)) { warn.add("cliente_repetido", "Cliente repetido en el archivo (se usa el primero)", ref || name); continue; }
      clients.set(key, {
        ref: key, name, doc_type: d.doc ? d.type : "0", doc: d.doc,
        address: str(cell(row, x.cols, "address")).slice(0, 300) || null, district: str(cell(row, x.cols, "district")).slice(0, 80) || null,
        phone: str(cell(row, x.cols, "phone")).replace(/[^\d+ ]/g, "").slice(0, 30) || null,
        email: (() => { const e = str(cell(row, x.cols, "email")).toLowerCase(); return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e.slice(0, 200) : null; })(),
      });
    }
  }

  // Catálogo
  const products = new Map<string, WbProduct>();
  for (const x of roles.filter((r) => r.role === "catalogo")) {
    for (const row of dataRows(x)) {
      const code = str(cell(row, x.cols, "code")).slice(0, 40);
      const name = str(cell(row, x.cols, "description")).slice(0, 200);
      if (!code || !name) { warn.add("producto_incompleto", "Producto sin código o sin descripción (no se importó)", code || name); continue; }
      const taxedRaw = normHeader(str(cell(row, x.cols, "taxed")));
      const taxed = !/^(no|n|0|exonerado|inafecto|false)$/.test(taxedRaw);
      const price = num(cell(row, x.cols, "price")) ?? 0;
      if (products.has(code)) { warn.add("producto_repetido", "Código de producto repetido (se usa el primero)", code); continue; }
      products.set(code, { code, name, category: str(cell(row, x.cols, "category")).slice(0, 60) || null,
        unit: unitOf(str(cell(row, x.cols, "unit")), false), price: r2(Math.max(0, price)), taxed });
    }
  }

  // Detalle (agrupado por id_factura)
  const linesBy = new Map<string, WbLine[]>();
  for (const x of roles.filter((r) => r.role === "detalle")) {
    for (const row of dataRows(x)) {
      const ref = str(cell(row, x.cols, "doc_ref"));
      if (!ref) { warn.add("linea_sin_comprobante", "Línea de detalle sin id de comprobante (no se importó)", ""); continue; }
      const code = str(cell(row, x.cols, "code")).slice(0, 40) || null;
      const qty = Math.abs(num(cell(row, x.cols, "qty")) ?? 1) || 1;
      const price = Math.abs(num(cell(row, x.cols, "price")) ?? 0);
      const discount = Math.abs(num(cell(row, x.cols, "discount")) ?? 0);
      const totalRaw = num(cell(row, x.cols, "total"));
      const total = r2(totalRaw != null ? Math.abs(totalRaw) : qty * price - discount);
      let description = str(cell(row, x.cols, "description")).slice(0, 200);
      if (!description && code && products.has(code)) description = products.get(code)!.name;
      if (!description) description = code ?? "Ítem importado";
      if (code && !products.has(code)) {
        products.set(code, { code, name: description, category: null, unit: unitOf(str(cell(row, x.cols, "unit")), false), price: r2(price), taxed: true });
        warn.add("producto_solo_en_detalle", "Producto que solo aparecía en el detalle: se agregó al catálogo", code);
      }
      const arr = linesBy.get(ref) ?? [];
      arr.push({ code, description, qty: r2(qty), price: r2(price), discount: r2(discount), total });
      linesBy.set(ref, arr);
    }
  }

  // Comprobantes
  const docs: WbDoc[] = [];
  const seenKeys = new Set<string>();
  const usedRefs = new Set<string>();
  let skipped = 0;
  const today = new Date().toISOString().slice(0, 10);
  for (const x of roles.filter((r) => r.role === "comprobantes")) {
    for (const row of dataRows(x)) {
      const ref = str(cell(row, x.cols, "doc_ref"));
      const serie = str(cell(row, x.cols, "serie"));
      const number = docNumber(serie, str(cell(row, x.cols, "numero")), str(cell(row, x.cols, "full_number")));
      const label = number ?? ref;
      const kind = normKind(str(cell(row, x.cols, "kind")), number ?? serie);
      if (!kind) { skipped++; warn.add("tipo_desconocido", "Tipo de comprobante no reconocido o no soportado (no se importó)", `${label}: ${str(cell(row, x.cols, "kind"))}`); continue; }
      if (!number) { skipped++; warn.add("sin_numero", "Comprobante sin serie/número (no se importó)", ref); continue; }
      const issue = isoDate(cell(row, x.cols, "issue"));
      if (!issue) { skipped++; warn.add("sin_fecha", "Comprobante sin fecha de emisión válida (no se importó)", label); continue; }
      const key = `${kind}|${number}`;
      if (seenKeys.has(key)) { skipped++; warn.add("comprobante_repetido", "Comprobante repetido en el archivo (se usa el primero)", label); continue; }
      seenKeys.add(key);
      let due = isoDate(cell(row, x.cols, "due"));
      if (due && due < issue) due = null;

      // Cliente: por id_cliente; si la fila trae nombre/documento propios, se respetan.
      const cref = str(cell(row, x.cols, "client_ref"));
      const fromSheet = cref ? clients.get(cref) : undefined;
      let cname = str(cell(row, x.cols, "client_name")).slice(0, 120);
      if (looksLikeId(cname, cref)) cname = "";
      const d = normDoc(str(cell(row, x.cols, "client_doc_type")), str(cell(row, x.cols, "client_doc")));
      if (d.invalid && !fromSheet) warn.add("doc_invalido", "Documento de identidad no válido: se guardó \"sin documento\"", `${label}: ${str(cell(row, x.cols, "client_doc"))}`);
      if (!cname) cname = fromSheet?.name ?? "";
      if (!cname) { warn.add("comprobante_sin_cliente", "Comprobante sin nombre de cliente: quedó como \"Cliente sin nombre\"", label); cname = "Cliente sin nombre"; }
      if (cref && !fromSheet && clients.size > 0) warn.add("cliente_no_encontrado", "id_cliente que no está en la hoja de clientes (se creó con los datos del comprobante)", `${label}: ${cref}`);

      // Montos (CON IGV, tal como vienen). Las notas de crédito se guardan en positivo y RESTAN en los totales.
      const lines = linesBy.get(ref) ?? [];
      if (ref) usedRefs.add(ref);
      const tFile = num(cell(row, x.cols, "total"));
      const linesTotal = r2(lines.reduce((a, l) => a + l.total, 0));
      const total = r2(Math.abs(tFile ?? linesTotal));
      if (tFile == null && !lines.length) { skipped++; warn.add("sin_total", "Comprobante sin total ni detalle (no se importó)", label); seenKeys.delete(key); continue; }
      const discount = r2(Math.abs(num(cell(row, x.cols, "discount")) ?? 0));
      const taxFile = num(cell(row, x.cols, "tax"));
      const baseFile = num(cell(row, x.cols, "base"));
      const base = r2(Math.abs(baseFile ?? (taxFile != null ? total - Math.abs(taxFile) : total / (1 + defaultRate / 100))));
      const tax = r2(Math.abs(taxFile ?? total - base));
      const subtotal = r2(Math.abs(num(cell(row, x.cols, "subtotal")) ?? total + discount));
      if (Math.abs(base + tax - total) > 0.05) warn.add("no_cuadra", "Base + IGV no suma el total (se respetaron los montos del archivo)", `${label}: ${base} + ${tax} ≠ ${total}`);
      if (lines.length && Math.abs(linesTotal - total) > 0.05) warn.add("detalle_no_cuadra", "La suma del detalle no coincide con el total (se respetó el total del comprobante)", `${label}: ${linesTotal} ≠ ${total}`);

      // Estado y cobros
      const stRaw = str(cell(row, x.cols, "state"));
      let state = normState(stRaw);
      const paidFile = num(cell(row, x.cols, "paid"));
      const balFile = num(cell(row, x.cols, "balance"));
      if (!state) {
        if (stRaw) warn.add("estado_desconocido", "Estado no reconocido (se dedujo de pagado/saldo)", `${label}: ${stRaw}`);
        state = paidFile != null && paidFile >= total - 0.004 ? "pagada" : paidFile && paidFile > 0 ? "parcial" : balFile === 0 ? "pagada" : "pendiente";
      }
      const voided = state === "anulada";
      let paid = 0;
      if (kind !== "nota_credito" && !voided) {
        paid = state === "pagada" ? (paidFile ?? total) : Math.abs(paidFile ?? (balFile != null ? total - Math.abs(balFile) : 0));
        if (paid > total + 0.004) { warn.add("pagado_mayor", "Pagado mayor que el total (se tomó el total)", label); paid = total; }
        paid = r2(Math.max(0, paid));
        if (state === "pendiente" && paid > 0 && paid < total - 0.004) state = "parcial";
        if (state === "pagada" && paid < total - 0.004) warn.add("pagada_con_saldo", "Marcada como pagada pero con saldo (se registró solo lo pagado)", label);
      }
      const balance = kind === "nota_credito" || voided ? 0 : r2(Math.max(0, total - paid));
      if (state === "vencida" && (!due || due >= today)) {
        warn.add("vencida_sin_fecha", "Marcada como vencida sin fecha de vencimiento pasada (se usó la fecha de emisión)", label);
        due = issue;
      }

      const related = str(cell(row, x.cols, "related"));
      docs.push({
        ref: ref || key, kind, number, issue, due, client_ref: cref || null, client_name: cname,
        client_doc_type: d.doc ? d.type : null, client_doc: d.doc,
        client_address: str(cell(row, x.cols, "address")).slice(0, 300) || null,
        client_email: (() => { const e = str(cell(row, x.cols, "email")).toLowerCase(); return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e.slice(0, 200) : null; })(),
        currency: normCurrency(str(cell(row, x.cols, "currency"))), subtotal, discount, base, tax, total, state, paid, balance,
        method: str(cell(row, x.cols, "method")).slice(0, 40) || null, voided,
        related_number: related ? docNumber("", "", related) : null,
        lines: lines.length ? lines : [{ code: null, description: kind === "nota_credito" ? "Nota de crédito importada" : "Importe según comprobante", qty: 1, price: total, discount: 0, total }],
      });
      if (!lines.length) warn.add("sin_detalle", "Comprobante sin líneas de detalle (se guardó una línea con el total)", label);
    }
  }
  for (const ref of linesBy.keys()) if (!usedRefs.has(ref)) warn.add("detalle_huerfano", "Líneas de detalle de un comprobante que no está en el archivo (no se importaron)", ref);

  // Clientes que solo aparecen en comprobantes
  for (const d of docs) {
    const k = d.client_ref ?? `doc:${d.client_doc ?? ""}|${d.client_name.toLowerCase()}`;
    if (!clients.has(k)) {
      clients.set(k, { ref: k, name: d.client_name, doc_type: d.client_doc ? d.client_doc_type : "0", doc: d.client_doc, address: d.client_address, district: null, phone: null, email: d.client_email });
    }
    d.client_ref = k;
  }

  const totals = { sales: {} as MoneyByCur, credit_notes: {} as MoneyByCur, net: {} as MoneyByCur, receivable: {} as MoneyByCur, collected: {} as MoneyByCur };
  for (const d of docs) {
    if (d.voided) continue;
    if (d.kind === "nota_credito") { addCur(totals.credit_notes, d.currency, d.total); addCur(totals.net, d.currency, -d.total); continue; }
    addCur(totals.sales, d.currency, d.total); addCur(totals.net, d.currency, d.total);
    addCur(totals.receivable, d.currency, d.balance); addCur(totals.collected, d.currency, d.paid);
  }
  const preview: Preview = {
    sheets: roles.map((r) => ({ name: r.s.name, role: r.role, rows: r.role === "ignorada" ? 0 : dataRows(r).length })),
    counts: {
      clients: clients.size, products: products.size, documents: docs.length,
      facturas: docs.filter((d) => d.kind === "factura").length, boletas: docs.filter((d) => d.kind === "boleta").length,
      credit_notes: docs.filter((d) => d.kind === "nota_credito").length, notas_venta: docs.filter((d) => d.kind === "nota_venta").length,
      lines: docs.reduce((a, d) => a + (linesBy.has(d.ref) ? d.lines.length : 0), 0), voided: docs.filter((d) => d.voided).length, skipped,
    },
    totals,
    warnings: warn.list(),
  };
  return { preview, payload: { clients: [...clients.values()], products: [...products.values()], docs } };
}
