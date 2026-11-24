"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import VoiceRecorder from "./VoiceRecorder";
import InvoiceDownload from "./InvoiceDownload";
import { createInvoice } from "@/app/actions/invoices";
import { createQuote, setQuoteStatus } from "@/app/erp/actions";
import { createClient } from "@/lib/supabase/client";
import { draftProblem, money, totals, type InvoiceInput } from "@/lib/schemas";

type Stage =
  | { name: "idle" }
  | { name: "working" }
  | { name: "review"; inv: InvoiceInput }
  | { name: "saved"; inv: InvoiceInput; number: string; quote?: { id: string; token: string | null } };

const blankLine = () => ({ description: "", quantity: 1, unit_price: 0 });

/**
 * Draft receipts from the web: dictated (voice plan) or typed. Saving creates a draft only; it is issued to SUNAT
 * from the POS or the mobile app, like any other sale.
 */
const inDays = (n: number) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toLocaleDateString("en-CA", { timeZone: "America/Lima" }); };

export default function NewInvoice({ org, currency, voiceAllowed, notebookAllowed = false, defaultTaxRate = 18, mode = "invoice" }: { org: string; currency: string; voiceAllowed: boolean; notebookAllowed?: boolean; defaultTaxRate?: number; mode?: "invoice" | "quote" }) {
  const router = useRouter();
  const quote = mode === "quote";
  const [taxId, setTaxId] = useState("");
  const [validUntil, setValidUntil] = useState(() => inDays(15));
  const [copied, setCopied] = useState(false);
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

  /** «Del cuaderno a la factura»: a photo of the notebook, a note or a WhatsApp screenshot becomes a draft. */
  async function onPhoto(file: File) {
    setError("");
    setStage({ name: "working" });
    try {
      const fd = new FormData();
      fd.append("org_id", org);
      fd.append("image", file, file.name);
      const { data } = await createClient().auth.getSession();
      const res = await fetch("/api/notebook", { method: "POST", body: fd, headers: data.session ? { authorization: `Bearer ${data.session.access_token}` } : {} });
      const json = await res.json().catch(() => ({}));
      if (!res.ok || !json.sale) { setError(json.error ?? "No pude leer la foto. Intenta con más luz y la hoja completa."); setStage({ name: "idle" }); return; }
      const sale = json.sale as { client_name: string; items: { description: string; quantity: number; unit_price: number }[]; prices_include_tax: boolean; notes: string };
      if (!sale.items.length) { setError("No encontré productos en la foto. Prueba con otra más clara."); setStage({ name: "idle" }); return; }
      const net = (p: number) => sale.prices_include_tax && defaultTaxRate > 0 ? Math.round(p / (1 + defaultTaxRate / 100) * 100) / 100 : p;
      setStage({ name: "review", inv: { client_name: sale.client_name, tax_rate: defaultTaxRate, notes: sale.notes || undefined, items: sale.items.map(i => ({ ...i, unit_price: net(i.unit_price) })) } });
    } catch {
      setError("No pudimos procesar la foto. Comprueba tu conexión.");
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
    if (quote) {
      const q = await createQuote(org, { client_name: inv.client_name, client_tax_id: taxId.replace(/\D/g, "") || undefined, tax_rate: inv.tax_rate, notes: inv.notes, valid_until: validUntil || undefined,
        items: inv.items.map(i => ({ description: i.description, quantity: Number(i.quantity), unit_price: Number(i.unit_price) })) }).catch(() => ({ ok: false as const, message: "Sin conexión." }));
      setSaving(false);
      if (!q.ok) return setError(q.message);
      setCopied(false); setTaxId(""); setValidUntil(inDays(15));
      setStage({ name: "saved", inv, number: q.number, quote: { id: q.id, token: q.token } });
      router.refresh();
      return;
    }
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
          <strong>{quote ? "Nueva cotización" : "Nuevo borrador"}</strong>
          <small>{voiceAllowed ? "Dicta cliente, productos e importes, o escríbelos." : "Escribe cliente, productos e importes."} {quote ? "Le mandas el enlace al cliente y la conviertes en venta cuando acepte." : "Se emite a SUNAT desde el punto de venta."}</small>
        </div>
        <div className="fv-draft-actions">
          {voiceAllowed && <VoiceRecorder compact onAudio={onAudio} disabled={stage.name === "working"} />}
          {notebookAllowed && <label className="fv-button secondary fv-file">Foto del cuaderno<input type="file" accept="image/jpeg,image/png,image/webp" className="fv-visually-hidden" disabled={stage.name === "working"} onChange={e => { const f = e.target.files?.[0]; if (f) void onPhoto(f); e.target.value = ""; }} /></label>}
          <button className="fv-button secondary" disabled={stage.name === "working"} onClick={() => setStage({ name: "review", inv: { client_name: "", tax_rate: defaultTaxRate, items: [blankLine()] } })}>{quote ? "Escribir cotización" : "Escribir borrador"}</button>
        </div>
        {stage.name === "working" && <p className="fv-draft-note" aria-live="polite">Leyendo…</p>}
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
          <div><strong>{quote ? "Revisa la cotización" : "Revisa el borrador"}</strong><small>{quote ? "El cliente la ve con un enlace y puede aceptarla desde su celular." : "Guardarlo no lo emite ante SUNAT."}</small></div>
          <button className="fv-icon-button" onClick={() => setStage({ name: "idle" })} aria-label="Cerrar borrador">✕</button>
        </header>
        <label className="fv-search fv-draft-client"><span>Cliente</span>
          <input maxLength={120} value={inv.client_name} placeholder="Cliente varios" onChange={(e) => set({ client_name: e.target.value })} />
        </label>
        {quote && <div className="fv-two">
          <label className="fv-search"><span>RUC o DNI (opcional)</span><input inputMode="numeric" maxLength={11} value={taxId} onChange={e => setTaxId(e.target.value.replace(/\D/g, ""))} /></label>
          <label className="fv-search"><span>Válida hasta</span><input type="date" value={validUntil} onChange={e => setValidUntil(e.target.value)} /></label>
        </div>}
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
          <button className="fv-button" disabled={saving} onClick={() => save(inv)}>{saving ? "Guardando…" : quote ? "Guardar cotización" : "Guardar borrador"}</button>
          <button className="fv-button secondary" onClick={() => setStage({ name: "idle" })}>Descartar</button>
        </div>
      </div>
    );
  }

  if (stage.quote) {
    const url = stage.quote.token ? `${window.location.origin}/cotizacion/${stage.quote.token}` : "";
    const q = stage.quote;
    const sent = () => { void setQuoteStatus(org, q.id, "sent").then(() => router.refresh()); };
    const text = `Hola${stage.inv.client_name && stage.inv.client_name !== "Cliente varios" ? ` ${stage.inv.client_name}` : ""}, te envío la cotización ${stage.number}: ${url}`;
    return (
      <div className="fv-create fv-draft-bar">
        <div><strong>Cotización {stage.number} guardada</strong><small>Envíale el enlace: la ve, la acepta desde su celular y aquí te enteras al instante.</small></div>
        <div className="fv-draft-actions">
          {url && <button className="fv-button" onClick={() => { void navigator.clipboard?.writeText(url).then(() => setCopied(true)); sent(); }}>{copied ? "Enlace copiado" : "Copiar enlace"}</button>}
          {url && <a className="fv-button secondary" href={`https://wa.me/?text=${encodeURIComponent(text)}`} target="_blank" rel="noreferrer" onClick={sent}>Enviar por WhatsApp</a>}
          <InvoiceDownload data={{ ...stage.inv, currency, number: stage.number, date: new Date().toLocaleDateString("es-PE") }} />
          <button className="fv-button secondary" onClick={() => setStage({ name: "idle" })}>Nueva cotización</button>
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
