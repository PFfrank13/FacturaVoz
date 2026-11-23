/** Pure helpers for the ERP home: the day's rhythm, best sellers and what needs attention (no I/O). */

export const OPEN_HOURS = Array.from({ length: 18 }, (_, i) => i + 6); // 6 a. m. – 11 p. m., a bodega's day

const limaHour = (iso: string) => Number(new Intl.DateTimeFormat("en-US", { hour: "numeric", hourCycle: "h23", timeZone: "America/Lima" }).format(new Date(iso)));

/** Sales per hour of the day (Lima time). Sales outside opening hours fall into the first or last bar. */
export function hourlyRhythm(sales: { created_at: string; amt_total: number | string | null }[]) {
  const buckets = new Map(OPEN_HOURS.map(h => [h, { hour: h, total: 0, count: 0 }]));
  for (const s of sales) {
    const h = Math.min(23, Math.max(6, limaHour(s.created_at)));
    const b = buckets.get(h)!;
    b.total += Number(s.amt_total ?? 0);
    b.count++;
  }
  const rows = [...buckets.values()].map(b => ({ ...b, total: Math.round(b.total * 100) / 100 }));
  const max = Math.max(0, ...rows.map(r => r.total));
  const peak = max > 0 ? rows.find(r => r.total === max)!.hour : null;
  return { rows: rows.map(r => ({ ...r, height: max ? r.total / max : 0 })), peak };
}

export const hourLabel = (h: number) => (h === 12 ? "12 m." : h < 12 ? `${h} a. m.` : `${h - 12} p. m.`);

/** Best sellers by revenue, grouped by line description (as printed on the receipt). */
export function topProducts(items: { description: string; quantity: number | string; unit_price: number | string }[], limit = 5) {
  const by = new Map<string, { name: string; units: number; revenue: number }>();
  for (const it of items) {
    const key = it.description.trim().toLocaleLowerCase("es");
    if (!key) continue;
    const row = by.get(key) ?? { name: it.description.trim(), units: 0, revenue: 0 };
    row.units += Number(it.quantity);
    row.revenue += Number(it.quantity) * Number(it.unit_price);
    by.set(key, row);
  }
  return [...by.values()].map(r => ({ ...r, units: Math.round(r.units * 100) / 100, revenue: Math.round(r.revenue * 100) / 100 }))
    .sort((a, b) => b.revenue - a.revenue || a.name.localeCompare(b.name, "es")).slice(0, limit);
}

/** Change against the previous month, as a whole percentage, or null when there is nothing to compare. */
export function monthChange(current: number, previous: number): number | null {
  if (!(previous > 0)) return null;
  return Math.round(((current - previous) / previous) * 100);
}

export type Attention = { id: string; tone: "bad" | "wait"; text: string; action: string; href: string };

/** The day's to-do list, most urgent first, only with what the person may open. */
export function attentionList(o: {
  base: string;
  lowStock?: { name: string }[] | null;
  overdueFiado?: { count: number; amount: string } | null;
  sunatProblems?: number | null;
  payables?: { count: number; amount: string } | null;
  till?: "sin_apertura" | "abierta" | "cerrada" | null;
  afterHours?: boolean;
  expiry?: { expired: number; week: number; weekValue: string } | null;
}): Attention[] {
  const out: Attention[] = [];
  if (o.expiry?.expired) out.push({ id: "vencidos", tone: "bad", text: o.expiry.expired === 1 ? "Un lote vencido sigue en el anaquel." : `${o.expiry.expired} lotes vencidos siguen en el anaquel.`, action: "Retirar como merma", href: `${o.base}/inventario` });
  if (o.sunatProblems) out.push({ id: "sunat", tone: "bad", text: o.sunatProblems === 1 ? "Un comprobante no llegó bien a SUNAT." : `${o.sunatProblems} comprobantes no llegaron bien a SUNAT.`, action: "Revisar comprobantes", href: `${o.base}/comprobantes` });
  if (o.lowStock?.length) {
    const names = o.lowStock.slice(0, 3).map(p => p.name).join(", ");
    out.push({ id: "stock", tone: "bad", text: o.lowStock.length === 1 ? `Se está acabando ${names}.` : `${o.lowStock.length} productos bajo su mínimo: ${names}${o.lowStock.length > 3 ? " y más" : ""}.`, action: "Registrar compra", href: `${o.base}/compras` });
  }
  if (o.expiry?.week) out.push({ id: "por-vencer", tone: "wait", text: `${o.expiry.week === 1 ? "Un lote vence" : `${o.expiry.week} lotes vencen`} esta semana (${o.expiry.weekValue}): ponlos adelante o rebájalos.`, action: "Ver vencimientos", href: `${o.base}/inventario` });
  if (o.overdueFiado?.count) out.push({ id: "fiado", tone: "wait", text: `${o.overdueFiado.count === 1 ? "Un cliente tiene" : `${o.overdueFiado.count} clientes tienen`} fiado vencido o sobre su límite (${o.overdueFiado.amount}).`, action: "Ver clientes", href: `${o.base}/clientes` });
  if (o.payables?.count) out.push({ id: "pagar", tone: "wait", text: `Debes ${o.payables.amount} a proveedores en ${o.payables.count === 1 ? "una compra" : `${o.payables.count} compras`}.`, action: "Ver compras", href: `${o.base}/compras` });
  if (o.till === "sin_apertura") out.push({ id: "caja", tone: "wait", text: "La caja de hoy aún no se abre.", action: "Abrir caja", href: `${o.base}/caja` });
  if (o.till === "abierta" && o.afterHours) out.push({ id: "caja", tone: "wait", text: "La caja de hoy sigue abierta.", action: "Cerrar caja", href: `${o.base}/caja` });
  return out;
}
