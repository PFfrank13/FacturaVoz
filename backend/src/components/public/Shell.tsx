import type { ReactNode } from "react";

/** Marco visual común de las páginas públicas (cliente final). Sin scripts de terceros. */
export function PublicShell({ eyebrow, title, subtitle, children }: { eyebrow: string; title: string; subtitle?: string; children: ReactNode }) {
  return (
    <main className="min-h-screen bg-[#f8f6fd] px-4 py-6 text-[#26254b] sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <div className="overflow-hidden rounded-[28px] bg-white shadow-[0_20px_60px_-20px_rgba(106,98,226,0.35)]">
          <header className="bg-gradient-to-br from-[#6a62e2] via-[#8e7cf2] to-[#b58bf5] px-6 pb-7 pt-6 text-white">
            <p className="text-[13px] font-medium opacity-85">{eyebrow}</p>
            <h1 className="mt-1 text-[26px] font-bold leading-tight tracking-tight">{title}</h1>
            {subtitle ? <p className="mt-1 text-sm opacity-85">{subtitle}</p> : null}
          </header>
          <div className="px-6 py-6">{children}</div>
        </div>
        <p className="mt-5 text-center text-xs text-[#8a8cab]">Documento generado con FacturaVoz</p>
      </div>
    </main>
  );
}

export function Lines({ items, fmt }: { items: { description: string; quantity: number; unit_price: number }[]; fmt: (n: number) => string }) {
  return (
    <ul className="divide-y divide-[#ece9f7]">
      {items.map((i, k) => (
        <li key={k} className="flex items-start justify-between gap-4 py-3">
          <div>
            <p className="text-[15px] font-medium">{i.description}</p>
            <p className="text-[13px] text-[#77799b]">
              {Number.isInteger(i.quantity) ? i.quantity : i.quantity.toFixed(2)} × {fmt(i.unit_price)}
            </p>
          </div>
          <p className="whitespace-nowrap text-[15px] font-semibold tabular-nums">{fmt(Math.round(i.quantity * i.unit_price * 100) / 100)}</p>
        </li>
      ))}
    </ul>
  );
}

export function TotalsBox({ rows }: { rows: { label: string; value: string; strong?: boolean; tone?: "bad" | "ok" }[] }) {
  return (
    <div className="mt-4 space-y-2 rounded-2xl bg-[#f3f1fc] px-4 py-4">
      {rows.map((r) => (
        <div key={r.label} className={`flex justify-between ${r.strong ? "text-lg font-bold" : "text-[14.5px]"}`}>
          <span className={r.strong ? "" : "text-[#77799b]"}>{r.label}</span>
          <span className={`tabular-nums ${r.tone === "bad" ? "text-[#d94a5e]" : r.tone === "ok" ? "text-[#23956f]" : ""}`}>{r.value}</span>
        </div>
      ))}
    </div>
  );
}

export function NotFoundCard({ text }: { text: string }) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-[#f8f6fd] p-6 text-[#26254b]">
      <div className="max-w-sm rounded-3xl bg-white p-8 text-center shadow">
        <p className="text-4xl">🔎</p>
        <h1 className="mt-3 text-xl font-bold">Enlace no válido</h1>
        <p className="mt-2 text-sm text-[#77799b]">{text}</p>
      </div>
    </main>
  );
}
