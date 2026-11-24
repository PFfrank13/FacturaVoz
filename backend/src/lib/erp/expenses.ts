/** Expense categories: same keys and names as the mobile app (models_pro.dart). */
export const expenseCategories: Record<string, string> = {
  mercaderia: "Mercadería", insumos: "Insumos", servicios: "Servicios (luz, agua, internet)", alquiler: "Alquiler", planilla: "Sueldos",
  transporte: "Transporte", marketing: "Publicidad", impuestos: "Impuestos", equipos: "Equipos", otros: "Otros",
};

export type ExpenseRow = { id: string; spent_on: string; category: string; description: string | null; supplier_name: string | null; doc_number: string | null; total: number | string; source: string | null };

/** Sum by category, largest first. */
export function byCategory(rows: ExpenseRow[]): { category: string; label: string; total: number }[] {
  const m = new Map<string, number>();
  for (const r of rows) m.set(r.category, (m.get(r.category) ?? 0) + Number(r.total));
  return [...m].map(([category, total]) => ({ category, label: expenseCategories[category] ?? category, total: Math.round(total * 100) / 100 })).sort((a, b) => b.total - a.total);
}
