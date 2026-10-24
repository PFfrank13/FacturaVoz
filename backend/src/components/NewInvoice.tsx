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

export default function NewInvoice() {
  const [stage, setStage] = useState<Stage>({ name: "idle" });
  const [error, setError] = useState("");

  async function onAudio(blob: Blob, filename: string) {
    setError("");
    setStage({ name: "working" });
    const fd = new FormData();
    fd.append("audio", blob, filename);
    const res = await fetch("/api/parse", { method: "POST", body: fd });
    const json = await res.json();
    if (!res.ok) {
      setError(json.error ?? "Error");
      setStage({ name: "idle" });
      return;
    }
    setStage({ name: "review", inv: json.invoice });
  }

  async function save(inv: InvoiceInput) {
    setError("");
    const r = await createInvoice(inv);
    if (!r.success) return setError(r.error);
    setStage({ name: "saved", inv, number: r.data.number });
  }

  if (stage.name === "idle" || stage.name === "working")
    return (
      <div className="py-8">
        <VoiceRecorder onAudio={onAudio} disabled={stage.name === "working"} />
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
        <p className="text-sm text-gray-500">Revisa lo que entendí:</p>
        <input
          className="w-full rounded border p-2"
          value={inv.client_name}
          onChange={(e) => set({ client_name: e.target.value })}
        />
        {inv.items.map((it, k) => (
          <div key={k} className="grid grid-cols-6 gap-2">
            <input
              className="col-span-3 rounded border p-2"
              value={it.description}
              onChange={(e) => setItem(k, { description: e.target.value })}
            />
            <input
              type="number"
              className="rounded border p-2"
              value={it.quantity}
              onChange={(e) => setItem(k, { quantity: Number(e.target.value) })}
            />
            <input
              type="number"
              className="col-span-2 rounded border p-2"
              value={it.unit_price}
              onChange={(e) => setItem(k, { unit_price: Number(e.target.value) })}
            />
          </div>
        ))}
        <label className="flex items-center gap-2 text-sm">
          IVA %
          <input
            type="number"
            className="w-20 rounded border p-1"
            value={inv.tax_rate}
            onChange={(e) => set({ tax_rate: Number(e.target.value) })}
          />
        </label>
        <p className="text-right text-lg font-semibold">Total: {money(t.total)}</p>
        {error && <p className="text-red-600">{error}</p>}
        <div className="flex gap-3">
          <button className="rounded-lg bg-blue-600 px-5 py-3 text-white" onClick={() => save(inv)}>
            Guardar factura
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
      <p className="text-lg">Factura {stage.number} guardada ✅</p>
      <InvoiceDownload
        data={{ ...stage.inv, number: stage.number, date: new Date().toLocaleDateString("es-ES") }}
      />
      <div>
        <button className="underline" onClick={() => setStage({ name: "idle" })}>
          Nueva factura
        </button>
      </div>
    </div>
  );
}
