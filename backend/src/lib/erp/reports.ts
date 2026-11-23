/** Pure helpers for the web Reportes module (no I/O). */

/** Sales per calendar day between two dates (inclusive), with zero days filled in, for the bars. */
export function dailySeries(rows: { issue_date: string; amt_total: number | string | null }[], from: string, to: string) {
  const byDay = new Map<string, { total: number; count: number }>();
  for (const r of rows) {
    const d = byDay.get(r.issue_date) ?? { total: 0, count: 0 };
    d.total += Number(r.amt_total ?? 0); d.count++;
    byDay.set(r.issue_date, d);
  }
  const out: { day: string; total: number; count: number }[] = [];
  const cur = new Date(`${from}T12:00:00Z`);
  const end = new Date(`${to}T12:00:00Z`);
  for (let i = 0; cur <= end && i < 400; i++) {
    const day = cur.toISOString().slice(0, 10);
    const d = byDay.get(day) ?? { total: 0, count: 0 };
    out.push({ day, total: Math.round(d.total * 100) / 100, count: d.count });
    cur.setUTCDate(cur.getUTCDate() + 1);
  }
  const max = Math.max(0, ...out.map(d => d.total));
  const best = max > 0 ? out.find(d => d.total === max)! : null;
  return { days: out.map(d => ({ ...d, height: max ? d.total / max : 0 })), best };
}

/** Collected money per payment method, largest first, with its share. */
export function byMethod(rows: { method: string; amount: number | string }[]) {
  const m = new Map<string, number>();
  for (const r of rows) m.set(r.method, (m.get(r.method) ?? 0) + Number(r.amount ?? 0));
  const total = [...m.values()].reduce((a, b) => a + b, 0);
  return [...m.entries()].map(([method, value]) => ({ method, value: Math.round(value * 100) / 100, share: total ? Math.round((value / total) * 100) : 0 }))
    .sort((a, b) => b.value - a.value);
}

/** Estimated gross margin of what was sold: revenue minus quantity × current unit cost (only lines with a cost). */
export function grossMargin(items: { quantity: number | string; unit_price: number | string; unit_cost: number | string | null }[]) {
  let revenue = 0, cost = 0, covered = 0, all = 0;
  for (const it of items) {
    const rev = Number(it.quantity) * Number(it.unit_price);
    all += rev;
    if (it.unit_cost == null) continue;
    revenue += rev; cost += Number(it.quantity) * Number(it.unit_cost); covered += rev;
  }
  const margin = revenue > 0 ? Math.round(((revenue - cost) / revenue) * 1000) / 10 : null;
  return { margin, profit: Math.round((revenue - cost) * 100) / 100, coverage: all > 0 ? Math.round((covered / all) * 100) : 0 };
}
