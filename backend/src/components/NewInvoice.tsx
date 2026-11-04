"use client";
import { useState } from "react";
import VoiceRecorder from "./VoiceRecorder";
import InvoiceDownload from "./InvoiceDownload";
import { createInvoice } from "@/app/actions/invoices";
import { money, totals, type InvoiceInput } from "@/lib/schemas";

type Stage =
  | { name: "idle" }
  | { name: "working" }
  | { name: "review"; inv: InvoiceInput }
  | { name: "saved"; inv: InvoiceInput; number: string };

export default function NewInvoice({ org, currency, voiceAllowed, defaultTaxRate = 18 }: { org: string; currency: string; voiceAllowed: boolean; defaultTaxRate?: number }) {
  const [stage, setStage] = useState<Stage>({ name: "idle" });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  async function onAudio(blob: Blob, filename: string) {
    setError("");
    setStage({ name: "working" });
    try {
    const fd = new FormData();
    fd.append("org_id", org);
    fd.append("audio", blob, filename);
    const res = await fetch("/api/parse", { method: "POST", body: fd });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "Error");
      setStage({ name: "idle" });
      return;
    }
    setStage({ name: "review", inv: json.invoice });
    } catch { setError("No pudimos procesar el audio. Comprueba tu conexión."); setStage({ name: "idle" }); }
  }

  async function save(inv: InvoiceInput) {
    setError("");
    if (saving) return;
    setSaving(true);
    const r = await createInvoice({ ...inv, org_id: org });
    setSaving(false);
    if (!r.success) return setError(r.error);
    setStage({ name: "saved", inv, number: r.data.number });
  }

  if (stage.name === "idle" || stage.name === "working")
    return (
      <div className="py-8">
        {voiceAllowed && <VoiceRecorder onAudio={onAudio} disabled={stage.name === "working"} />}
        <button className="fv-button secondary" disabled={stage.name === "working"} onClick={() => setStage({ name: "review", inv: { client_name: "", tax_rate: defaultTaxRate, items: [{ description: "", quantity: 1, unit_price: 0 }] } })}>Nuevo comprobante manual</button>
        {stage.name === "working" && <p className="mt-4 text-center">Procesando…</p>}
        {error && <p className="mt-4 text-center text-red-600">{error}</p>}
      </div>
    );

  if (stage.name === "review") {
    const inv = stage.inv;
    const set = (p: Partial<InvoiceInput>) => setStage({ name: "review", inv: { ...inv, ...p } });
    const setItem = (k: number, p: Partial<InvoiceInput["items"][number]>) =>
      set({ items: inv.items.map((x, j) => (j === k ? { ...x, ...p } : x)) });
    const t = totals(inv.items, inv.tax_rate);
    return (
      <div className="space-y-4">
        <p className="text-sm text-gray-500">Revisa el borrador. Guardarlo no lo emite ante SUNAT.</p>
        <input
          className="w-full rounded border p-2"
          aria-label="Nombre del cliente"
          maxLength={120}
          value={inv.client_name}
          onChange={(e) => set({ client_name: e.target.value })}
        />
        {inv.items.map((it, k) => (
          <div key={k} className="grid grid-cols-6 gap-2">
            <input
              className="col-span-3 rounded border p-2"
              aria-label={`Descripción del artículo ${k + 1}`}
              maxLength={200}
              value={it.description}
              onChange={(e) => setItem(k, { description: e.target.value })}
            />
            <input
              type="number"
              className="rounded border p-2"
              aria-label={`Cantidad del artículo ${k + 1}`}
              min="0.001" step="0.001"
              value={it.quantity}
              onChange={(e) => setItem(k, { quantity: Number(e.target.value) })}
            />
            <input
              type="number"
              className="col-span-2 rounded border p-2"
              aria-label={`Precio unitario del artículo ${k + 1}`}
              min="0" step="0.01"
              value={it.unit_price}
              onChange={(e) => setItem(k, { unit_price: Number(e.target.value) })}
            />
          </div>
        ))}
        <button className="fv-button secondary" disabled={inv.items.length >= 50 || saving} onClick={() => set({ items: [...inv.items, { description: "", quantity: 1, unit_price: 0 }] })}>Añadir artículo</button>
        <label className="flex items-center gap-2 text-sm">
          Impuesto %
          <input
            type="number"
            className="w-20 rounded border p-1"
            value={inv.tax_rate}
            onChange={(e) => set({ tax_rate: Number(e.target.value) })}
          />
        </label>
        <p className="text-right text-lg font-semibold">Total: {money(t.total, currency)}</p>
        {error && <p className="text-red-600">{error}</p>}
        <div className="flex gap-3">
          <button className="rounded-lg bg-blue-600 px-5 py-3 text-white" disabled={saving} onClick={() => save(inv)}>
            {saving ? "Guardando…" : "Guardar borrador"}
          </button>
          <button className="rounded-lg border px-5 py-3" onClick={() => setStage({ name: "idle" })}>
            Repetir
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4 text-center">
      <p className="text-lg">Borrador {stage.number} guardado</p>
      <InvoiceDownload
        data={{ ...stage.inv, currency, number: stage.number, date: new Date().toLocaleDateString("es-PE") }}
      />
      <div>
        <button className="underline" onClick={() => setStage({ name: "idle" })}>
          Nueva factura
        </button>
      </div>
    </div>
  );
}
