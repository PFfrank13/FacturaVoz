/** Inventory count (docs/INVESTIGACION_RETAIL.md, row 20): what the shelf has vs. what the system says. Pure, no I/O. */

export type CountItem = { product_id: string; name: string; stock: number; counted: number; unit_cost: number | null };
export type CountLine = CountItem & { diff: number; value: number };

/** Differences of the products actually counted (blank entries are skipped), shortages first. */
export function countLines(items: CountItem[]): CountLine[] {
  return items
    .filter(i => Number.isFinite(i.counted) && i.counted >= 0)
    .map(i => {
      const diff = Math.round((i.counted - i.stock) * 100) / 100;
      return { ...i, diff, value: Math.round(diff * Number(i.unit_cost ?? 0) * 100) / 100 };
    })
    .filter(l => l.diff !== 0)
    .sort((a, b) => a.value - b.value || a.name.localeCompare(b.name, "es"));
}

export function countSummary(lines: CountLine[]) {
  let missing = 0, extra = 0, missingValue = 0, extraValue = 0;
  for (const l of lines) {
    if (l.diff < 0) { missing += -l.diff; missingValue += -l.value; } else { extra += l.diff; extraValue += l.value; }
  }
  const r = (v: number) => Math.round(v * 100) / 100;
  return { products: lines.length, missing: r(missing), extra: r(extra), missingValue: r(missingValue), extraValue: r(extraValue), net: r(extraValue - missingValue) };
}

/** Parses what the person typed in a count box: "", "12", "3,5" → null | number (2 decimals). */
export function parseCount(raw: string): number | null {
  const t = raw.trim().replace(",", ".");
  if (!t) return null;
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return NaN;
  return Number(t);
}
