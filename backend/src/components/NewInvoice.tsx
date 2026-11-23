"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import VoiceRecorder from "./VoiceRecorder";
import InvoiceDownload from "./InvoiceDownload";
import { createInvoice } from "@/app/actions/invoices";
import { draftProblem, money, totals, type InvoiceInput } from "@/lib/schemas";

type Stage =
  | { name: "idle" }
  | { name: "working" }
  | { name: "review"; inv: InvoiceInput }
  | { name: "saved"; inv: InvoiceInput; number: string };

const blankLine = () => ({ description: "", quantity: 1, unit_price: 0 });

/**
 * Draft receipts from the web: dictated (voice plan) or typed. Saving creates a draft only; it is issued to SUNAT
 * from the POS or the mobile app, like any other sale.
 */
export default function NewInvoice({ org, currency, voiceAllowed, defaultTaxRate = 18 }: { org: string; currency: string; voiceAllowed: boolean; defaultTaxRate?: number }) {
  const router = useRouter();
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
        setError(json.error ?? "No pudimos entender el dictado. Inténtalo de nuevo.");
        setStage({ name: "idle" });
        return;
      }
      setStage({ name: "review", inv: json.invoice });
    } catch {
      setError("No pudimos procesar el audio. Comprueba tu conexión.");
      setStage({ name: "idle" });
    }
  }

  async function save(draft: InvoiceInput) {
    setError("");
    if (saving) return;
    const inv = { ...draft, client_name: draft.client_name.trim() || "Cliente varios" };
    const problem = draftProblem(inv);
    if (problem) return setError(problem);
    setSaving(true);
    const r = await createInvoice({ ...inv, org_id: org });
    setSaving(false);
    if (!r.success) return setError(r.error);
    setStage({ name: "saved", inv, number: r.data.number });
    router.refresh(); // the list shows the new draft at once, even without realtime
  }

  if (stage.name === "idle" || stage.name === "working")
    return (
      <div className="fv-create fv-draft-bar">
        <div>
          <strong>Nuevo borrador</strong>
          <small>{voiceAllowed ? "Dicta cliente, productos e importes, o escríbelos." : "Escribe cliente, productos e importes."} Se emite a SUNAT desde el punto de venta.</small>
        </div>
        <div className="fv-draft-actions">
          {voiceAllowed && <VoiceRecorder compact onAudio={onAudio} disabled={stage.name === "working"} />}
          <button className="fv-button secondary" disabled={stage.name === "working"} onClick={() => setStage({ name: "review", inv: { client_name: "", tax_rate: defaultTaxRate, items: [blankLine()] } })}>Escribir borrador</button>
        </div>
        {stage.name === "working" && <p className="fv-draft-note" aria-live="polite">Entendiendo el dictado…</p>}
        {error && <p className="fv-draft-note fv-error" role="alert">{error}</p>}
      </div>
    );

  if (stage.name === "review") {
    const inv = stage.inv;
    const set = (p: Partial<InvoiceInput>) => setStage({ name: "review", inv: { ...inv, ...p } });
    const setItem = (k: number, p: Partial<InvoiceInput["items"][number]>) =>
      set({ items: inv.items.map((x, j) => (j === k ? { ...x, ...p } : x)) });
    const t = totals(inv.items, inv.tax_rate);
    return (
      <div className="fv-create fv-draft">
        <header>
          <div><strong>Revisa el borrador</strong><small>Guardarlo no lo emite ante SUNAT.</small></div>
          <button className="fv-icon-button" onClick={() => setStage({ name: "idle" })} aria-label="Cerrar borrador">✕</button>
        </header>
        <label className="fv-search fv-draft-client"><span>Cliente</span>
          <input maxLength={120} value={inv.client_name} placeholder="Cliente varios" onChange={(e) => set({ client_name: e.target.value })} />
        </label>
        <div className="fv-draft-lines" role="group" aria-label="Artículos">
          <div className="fv-draft-head" aria-hidden="true"><span>Descripción</span><span>Cant.</span><span>P. unit.</span><span>Importe</span><span /></div>
          {inv.items.map((it, k) => (
            <div key={k} className="fv-draft-line">
              <input aria-label={`Descripción del artículo ${k + 1}`} maxLength={200} value={it.description} placeholder="Producto o servicio" onChange={(e) => setItem(k, { description: e.target.value })} />
              <input type="number" inputMode="decimal" aria-label={`Cantidad del artículo ${k + 1}`} min="0.001" step="0.001" value={it.quantity} onChange={(e) => setItem(k, { quantity: Number(e.target.value) })} />
              <input type="number" inputMode="decimal" aria-label={`Precio unitario del artículo ${k + 1}`} min="0" step="0.01" value={it.unit_price} onChange={(e) => setItem(k, { unit_price: Number(e.target.value) })} />
              <span className="fv-draft-amount">{money((Number(it.quantity) || 0) * (Number(it.unit_price) || 0), currency)}</span>
              <button className="fv-icon-button" disabled={inv.items.length === 1} aria-label={`Quitar artículo ${k + 1}`} onClick={() => set({ items: inv.items.filter((_, j) => j !== k) })}>−</button>
            </div>
          ))}
        </div>
        <div className="fv-draft-foot">
          <button className="fv-button secondary" disabled={inv.items.length >= 50 || saving} onClick={() => set({ items: [...inv.items, blankLine()] })}>Añadir artículo</button>
          <label className="fv-search fv-narrow"><span>IGV %</span>
            <input type="number" min="0" max="100" value={inv.tax_rate} onChange={(e) => set({ tax_rate: Number(e.target.value) })} />
          </label>
          <dl className="fv-sums">
            <div><dt>Subtotal</dt><dd>{money(t.subtotal, currency)}</dd></div>
            <div><dt>IGV</dt><dd>{money(t.tax, currency)}</dd></div>
            <div className="is-total"><dt>Total</dt><dd>{money(t.total, currency)}</dd></div>
          </dl>
        </div>
        {error && <p className="fv-error" role="alert">{error}</p>}
        <div className="fv-actions">
          <button className="fv-button" disabled={saving} onClick={() => save(inv)}>{saving ? "Guardando…" : "Guardar borrador"}</button>
          <button className="fv-button secondary" onClick={() => setStage({ name: "idle" })}>Descartar</button>
        </div>
      </div>
    );
  }

  return (
    <div className="fv-create fv-draft-bar">
      <div><strong>Borrador {stage.number} guardado</strong><small>Ya aparece en la lista. Emítelo desde el punto de venta cuando cobres.</small></div>
      <div className="fv-draft-actions">
        <InvoiceDownload data={{ ...stage.inv, currency, number: stage.number, date: new Date().toLocaleDateString("es-PE") }} />
        <button className="fv-button secondary" onClick={() => setStage({ name: "idle" })}>Nuevo borrador</button>
      </div>
    </div>
  );
}
