/**
 * Reads a supplier's electronic invoice (SUNAT UBL 2.1 XML) to pre-fill a purchase (docs/INVESTIGACION_RETAIL.md,
 * row 9). Pure text parsing so it runs the same in the browser and in tests. Nothing is saved without review.
 */

export type UblLine = { description: string; quantity: number; unit_cost: number; unit: string };
export type UblInvoice = { supplier: string; ruc: string; reference: string; issueDate: string; currency: string; total: number; perception: number; lines: UblLine[] };

const text = (s: string | undefined) => (s ?? "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").trim();
const tag = (xml: string, name: string) => xml.match(new RegExp(`<(?:\\w+:)?${name}\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?${name}>`))?.[1];
const blocks = (xml: string, name: string) => [...xml.matchAll(new RegExp(`<(?:\\w+:)?${name}\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?${name}>`, "g"))].map(m => m[1]);
const num = (s: string | undefined) => { const n = Number(text(s)); return Number.isFinite(n) ? n : 0; };

/** null when the file is not a UBL invoice; otherwise the data, with lines that have quantity and description. */
export function parseUblInvoice(xml: string): UblInvoice | null {
  if (!/<(?:\w+:)?Invoice\b/.test(xml)) return null;
  const head = xml.split(/<(?:\w+:)?InvoiceLine\b/)[0];
  const supplierBlock = tag(xml, "AccountingSupplierParty") ?? "";
  const supplier = text(tag(supplierBlock, "RegistrationName") ?? tag(supplierBlock, "Name"));
  const ruc = text(tag(tag(supplierBlock, "PartyIdentification") ?? supplierBlock, "ID"));
  const reference = text(tag(head.replace(/<(?:\w+:)?UBLExtensions[\s\S]*?<\/(?:\w+:)?UBLExtensions>/, "").replace(/<(?:\w+:)?(UBLVersionID|CustomizationID|ProfileID)[\s\S]*?<\/(?:\w+:)?\1>/g, ""), "ID"));
  const currency = text(tag(head, "DocumentCurrencyCode")) || "PEN";
  const legal = tag(xml, "LegalMonetaryTotal") ?? "";
  const total = num(tag(legal, "PayableAmount"));
  // Percepción del IGV: cargo con código 51, 52 o 53 (catálogo 53 de SUNAT).
  let perception = 0;
  for (const ac of blocks(head, "AllowanceCharge")) {
    if (["51", "52", "53"].includes(text(tag(ac, "AllowanceChargeReasonCode")))) perception += num(tag(ac, "Amount"));
  }
  const lines: UblLine[] = blocks(xml, "InvoiceLine").map(b => {
    const qtyTag = b.match(/<(?:\w+:)?InvoicedQuantity\b([^>]*)>([\s\S]*?)</);
    const unit = qtyTag?.[1].match(/unitCode="([^"]+)"/)?.[1] ?? "NIU";
    const quantity = Number(text(qtyTag?.[2])) || 0;
    const item = tag(b, "Item") ?? "";
    const description = text(tag(item, "Description") ?? tag(item, "Name")).replace(/\s+/g, " ");
    const price = num(tag(tag(b, "Price") ?? "", "PriceAmount"));
    const lineBase = num(tag(b, "LineExtensionAmount"));
    const unit_cost = price > 0 ? price : quantity > 0 ? lineBase / quantity : 0;
    return { description, quantity: Math.round(quantity * 100) / 100, unit_cost: Math.round(unit_cost * 10000) / 10000, unit };
  }).filter(l => l.description && l.quantity > 0);
  return { supplier, ruc, reference, issueDate: text(tag(head, "IssueDate")), currency, total, perception: Math.round(perception * 100) / 100, lines };
}

const norm = (s: string) => s.toLocaleLowerCase("es").normalize("NFD").replace(/\p{Diacritic}/gu, "").replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();

/** Best product of the catalog for an invoice line: same name, or the one sharing the most words (≥ 2). */
export function matchProduct(description: string, products: { id: string; name: string }[]): string | null {
  const d = norm(description);
  const exact = products.find(p => norm(p.name) === d);
  if (exact) return exact.id;
  const words = new Set(d.split(" ").filter(w => w.length > 2));
  let best: { id: string; score: number } | null = null;
  for (const p of products) {
    const pw = norm(p.name).split(" ").filter(w => w.length > 2);
    const score = pw.filter(w => words.has(w)).length / Math.max(pw.length, 1);
    const hits = pw.filter(w => words.has(w)).length;
    if (hits >= 2 && score >= 0.6 && (!best || score > best.score)) best = { id: p.id, score };
  }
  return best?.id ?? null;
}
