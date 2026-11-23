/**
 * Sales and purchase registers for the accountant (docs/INVESTIGACION_RETAIL.md, row 17: SIRE is mandatory).
 * CSV with the columns the accountant needs to reconcile against the SIRE proposal. Pure, no I/O.
 */

export type SaleReg = {
  issue_date: string; doc_kind: string | null; voided_at: string | null; currency: string; amt_base: number | string | null; amt_tax: number | string | null; amt_total: number | string | null; number: string | null;
  client: { name: string | null; tax_id: string | null; doc_type: string | number | null } | null;
  fiscal: { doc_type: string | null; series: string | null; correlative: number | string | null; status: string | null; totals: { icbper?: number } | null } | null;
};
export type PurchaseReg = { spent_on: string; supplier_name: string | null; supplier_tax_id: string | null; doc_number: string | null; total: number | string; tax: number | string; currency: string; category: string | null };

/** CSV cell: quoted when needed, and neutralized if it could be read as a spreadsheet formula. */
export function csvCell(v: unknown): string {
  let s = v == null ? "" : String(v);
  if (/^[=+\-@\t\r]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = `'${s}`;
  return /[",;\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
export const toCsv = (rows: unknown[][]) => "﻿" + rows.map(r => r.map(csvCell).join(",")).join("\r\n") + "\r\n";

const n2 = (v: unknown) => (Math.round(Number(v ?? 0) * 100) / 100).toFixed(2);
const docTypeOf = (v: unknown) => (String(v ?? "") === "6" ? "6" : String(v ?? "") === "1" ? "1" : "0");

export function salesRegister(rows: SaleReg[]): unknown[][] {
  const head = ["Fecha", "Tipo comprobante", "Serie", "Número", "Tipo doc. cliente", "Doc. cliente", "Cliente", "Base imponible", "IGV", "ICBPER", "Total", "Moneda", "Estado"];
  const body = rows.map(r => {
    const f = r.fiscal;
    const kind = f?.doc_type ?? (r.doc_kind === "nota_credito" ? "07" : "");
    const sign = kind === "07" ? -1 : 1;
    const icbper = Number(f?.totals?.icbper ?? 0);
    return [
      r.issue_date, kind || "Sin comprobante", f?.series ?? "", f?.correlative ?? r.number ?? "",
      docTypeOf(r.client?.doc_type), r.client?.tax_id ?? "", r.client?.name ?? "Clientes varios",
      n2(sign * Number(r.amt_base ?? 0)), n2(sign * Number(r.amt_tax ?? 0)), n2(sign * icbper), n2(sign * Number(r.amt_total ?? 0)),
      r.currency, r.voided_at ? "Anulado" : f?.status === "accepted" ? "Aceptado" : f?.status ?? "Interno",
    ];
  });
  return [head, ...body];
}

export function purchasesRegister(rows: PurchaseReg[]): unknown[][] {
  const head = ["Fecha", "Proveedor", "RUC proveedor", "Comprobante", "Base imponible", "IGV", "Total", "Moneda", "Categoría"];
  return [head, ...rows.map(r => {
    const total = Number(r.total ?? 0), tax = Number(r.tax ?? 0);
    return [r.spent_on, r.supplier_name ?? "", r.supplier_tax_id ?? "", r.doc_number ?? "", n2(total - tax), n2(tax), n2(total), r.currency, r.category ?? ""];
  })];
}
