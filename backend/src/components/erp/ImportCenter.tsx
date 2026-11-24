"use client";
import type React from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { undoImport, type FormResult } from "@/app/erp/actions";
import { decodeImportBytes, mergeParsed, parseImportTable, parseImportText, type ParsedImport } from "@/lib/erp/history-import";

const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;
const chunks = <T,>(l: T[], n: number) => Array.from({ length: Math.ceil(l.length / n) }, (_, i) => l.slice(i * n, i * n + n));
const wait = (ms: number) => new Promise(r => setTimeout(r, ms));

type Preview = { counts?: Record<string, number>; totals?: { net?: Record<string, number> }; warnings?: { message?: string }[] };
type Workbook = { preview: Preview; payload: { clients?: unknown[]; products?: unknown[]; docs?: unknown[] }; file: string };
type Job = { id: string; status: string; total: number; processed: number; imported: number; skipped: number; error: string | null };
const jobCols = "id,status,total,processed,imported,skipped,error";
const finished = (s: string) => ["done", "failed", "cancelled"].includes(s);

async function bearer(): Promise<Record<string, string>> {
  const { data } = await createClient().auth.getSession();
  return data.session ? { authorization: `Bearer ${data.session.access_token}` } : {};
}
const isZip = (b: Uint8Array) => b.length > 4 && b[0] === 0x50 && b[1] === 0x4b;
const isOldXls = (b: Uint8Array) => b.length > 4 && b[0] === 0xd0 && b[1] === 0xcf;

/**
 * Same import as the mobile app: an Excel with several sheets (clients, products, receipts) goes through wb_import_*;
 * SUNAT's sales register, a CSV/TXT or a one-sheet Excel (one or many files) becomes an import_jobs batch the database processes.
 */
export default function ImportCenter({ org, taxRate }: { org: string; taxRate: number }) {
  const [busy, setBusy] = useState("");
  const [m, setM] = useState<FormResult | null>(null);
  const [wb, setWb] = useState<Workbook | null>(null);
  const [hist, setHist] = useState<(ParsedImport & { file: string }) | null>(null);
  const [withTax, setWithTax] = useState(true);
  const [job, setJob] = useState<Job | null>(null);
  const stop = useRef(false);
  const router = useRouter();

  const follow = useCallback(async (id: string) => {
    const db = createClient();
    stop.current = false;
    for (let i = 0; i < 20000 && !stop.current; i++) {
      const { data } = await db.from("import_jobs").select(jobCols).eq("id", id).maybeSingle();
      if (!data) return;
      const j = data as Job;
      setJob(j);
      if (finished(j.status)) { router.refresh(); return; }
      // Moves one batch while the page is open (the database worker does it too if the page closes).
      const r = await db.rpc("import_step", { p_job: id, p_batch: 500 });
      if (r.error) await wait(2500);
    }
  }, [router]);

  useEffect(() => {
    // Picks up an import still running (for example, started on the phone or before closing this page).
    let alive = true;
    void createClient().from("import_jobs").select(jobCols).eq("org_id", org).in("status", ["queued", "processing"]).order("created_at", { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => { if (alive && data) { setJob(data as Job); void follow((data as Job).id); } });
    return () => { alive = false; stop.current = true; };
  }, [org, follow]);

  async function pick(files: File[]) {
    setM(null); setWb(null); setHist(null); setJob(null);
    if (!files.length) return;
    setBusy("Leyendo…");
    try {
      const parts: ParsedImport[] = [];
      for (const f of files) {
        const bytes = new Uint8Array(await f.arrayBuffer());
        if (isOldXls(bytes)) { parts.push({ rows: [], rejected: 0, columns: {}, error: `«${f.name}» es un Excel antiguo (.xls). Ábrelo en Excel y guárdalo como .xlsx o .csv.` }); continue; }
        if (!isZip(bytes)) { parts.push(parseImportText(decodeImportBytes(bytes))); continue; }
        if (bytes.length > 4 * 1024 * 1024) { parts.push({ rows: [], rejected: 0, columns: {}, error: `«${f.name}» pesa más de 4 MB. Divídelo (por ejemplo, por año).` }); continue; }
        const res = await fetch(`/api/import/workbook?mode=auto&rate=${taxRate}`, { method: "POST", headers: { "content-type": "application/octet-stream", ...(await bearer()) }, body: bytes });
        const j = await res.json().catch(() => ({}));
        if (!res.ok) { parts.push({ rows: [], rejected: 0, columns: {}, error: j.error ?? `No pude leer «${f.name}».` }); continue; }
        if (j.kind === "table") { parts.push(parseImportTable(j.rows as string[][])); continue; }
        if (files.length > 1) { parts.push({ rows: [], rejected: 0, columns: {}, error: `«${f.name}» es un libro con varias hojas: súbelo solo.` }); continue; }
        setWb({ preview: j.preview, payload: j.payload, file: f.name });
        return;
      }
      const merged = mergeParsed(parts);
      const firstError = parts.find(p => p.error)?.error;
      if (merged.error || !merged.rows.length) { setM({ ok: false, message: merged.error ?? firstError ?? "No encontramos comprobantes con importe." }); return; }
      if (firstError) setM({ ok: false, message: `${firstError} El resto sí se leyó.` });
      setHist({ ...merged, file: files.length === 1 ? files[0].name : `${files.length} archivos` });
    } catch { setM({ ok: false, message: "No se pudieron leer los archivos. Guárdalos como Excel (.xlsx) o CSV e inténtalo de nuevo." }); }
    finally { setBusy(""); }
  }

  async function runWorkbook() {
    if (!wb) return;
    const db = createClient();
    try {
      setBusy("Preparando…");
      const counts = wb.preview.counts ?? {};
      const { data: id, error } = await db.rpc("wb_import_begin", { p_org: org, p_file: wb.file.slice(0, 200), p_expected: { ...counts, net: wb.preview.totals?.net ?? {} }, p_warnings: wb.preview.warnings ?? [] });
      if (error || !id) throw new Error(error?.message);
      const steps: [string, string, string, unknown[], number][] = [
        ["Clientes", "wb_import_clients", "p_rows", wb.payload.clients ?? [], 1000],
        ["Productos", "wb_import_products", "p_rows", wb.payload.products ?? [], 500],
        ["Comprobantes", "wb_import_docs", "p_docs", wb.payload.docs ?? [], 200],
      ];
      for (const [label, fn, arg, rows, size] of steps) {
        let done = 0;
        for (const c of chunks(rows, size)) {
          const r = await db.rpc(fn, { p_job: id, [arg]: c });
          if (r.error) throw new Error(r.error.message);
          done += c.length; setBusy(`${label} ${done} de ${rows.length}`);
        }
      }
      const fin = await db.rpc("wb_import_finish", { p_job: id });
      if (fin.error) throw new Error(fin.error.message);
      setWb(null); setM({ ok: true, message: "Importación terminada. Si algo no te convence, la deshaces abajo en «Importaciones anteriores»." }); router.refresh();
    } catch { setM({ ok: false, message: "La importación se detuvo. Revisa tu conexión y vuelve a intentarlo: lo ya importado no se duplica y lo puedes deshacer abajo." }); router.refresh(); }
    finally { setBusy(""); }
  }

  async function runHistory() {
    if (!hist) return;
    const db = createClient();
    try {
      setBusy("Preparando…");
      const { data: s } = await db.auth.getSession();
      const uid = s.session?.user.id;
      if (!uid) { setM({ ok: false, message: "Tu sesión caducó. Vuelve a entrar." }); return; }
      const { data, error } = await db.from("import_jobs").insert({ org_id: org, user_id: uid, file_name: hist.file.slice(0, 200) }).select("id").single();
      if (error || !data) throw new Error(error?.message);
      const id = (data as { id: string }).id;
      let sent = 0;
      for (const c of chunks(hist.rows, 500)) {
        for (let attempt = 0; ; attempt++) {
          const r = await db.rpc("import_add_rows", { p_job: id, p_rows: c });
          if (!r.error) break;
          if (attempt >= 3) throw new Error(r.error.message);
          await wait(500 * (attempt + 1));
        }
        sent += c.length; setBusy(`Subiendo ${sent} de ${hist.rows.length}. Mantén esta página abierta unos segundos.`);
      }
      const st = await db.rpc("import_start", { p_job: id, p_tax_rate: withTax ? taxRate : 0 });
      if (st.error) throw new Error(st.error.message);
      setHist(null); setBusy("");
      await follow(id);
    } catch { setM({ ok: false, message: "No se pudo subir. Revisa tu conexión y vuelve a intentarlo: los comprobantes ya importados no se duplican." }); }
    finally { setBusy(""); }
  }

  async function cancel() {
    if (!job || !window.confirm("¿Cancelar la importación? Lo ya importado se queda; lo pendiente no se procesa.")) return;
    stop.current = true;
    await createClient().rpc("import_cancel", { p_job: job.id });
    const { data } = await createClient().from("import_jobs").select(jobCols).eq("id", job.id).maybeSingle();
    if (data) setJob(data as Job);
    router.refresh();
  }

  const c = wb?.preview.counts ?? {};
  const pct = job && job.total > 0 ? Math.min(100, Math.floor((job.processed / job.total) * 100)) : 0;
  return <div className="fv-create fv-import" style={{ padding: 18 }}>
    <h3>Trae tu información</h3>
    <ol className="fv-import-steps">
      <li><strong>Descarga tu registro</strong><span>Del portal de SUNAT (SOL → Registro de ventas) o de tu sistema anterior, en Excel (.xlsx), CSV o TXT.</span></li>
      <li><strong>Súbelo aquí</strong><span>Uno o varios archivos a la vez (por meses, por años…). Detectamos las columnas solas.</span></li>
      <li><strong>Revisa y confirma</strong><span>Nada se guarda hasta que confirmas, y si importas el mismo archivo dos veces no se duplica.</span></li>
    </ol>
    <label className="fv-button fv-file">{busy && !job ? busy : "Elegir archivos"}
      <input type="file" hidden multiple accept=".xlsx,.xls,.csv,.txt,text/csv,text/plain" disabled={!!busy || (!!job && !finished(job.status))}
        onChange={e => { const fs = Array.from(e.target.files ?? []); e.target.value = ""; void pick(fs); }} /></label>

    {wb && <>
      <p className="fv-caption">Libro con varias hojas: «{wb.file}»</p>
      <div className="fv-kpis" style={{ marginTop: 10 }}>
        <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Clientes</span><strong>{c.clients ?? 0}</strong></div>
        <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Productos</span><strong>{c.products ?? 0}</strong></div>
        <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Comprobantes</span><strong>{c.documents ?? 0}</strong></div>
      </div>
      {wb.preview.warnings?.slice(0, 5).map((w, i) => <p key={i} className="fv-note-box">{w.message}</p>)}
      <div className="fv-actions-row"><button className="fv-button" disabled={!!busy} onClick={() => void runWorkbook()}>Importar ahora</button><button className="fv-button secondary" disabled={!!busy} onClick={() => setWb(null)}>Elegir otro archivo</button></div>
    </>}

    {hist && <>
      <p className="fv-caption">{hist.file}: <strong>{hist.rows.length.toLocaleString("es-PE")}</strong> comprobantes listos{hist.rejected ? ` · ${hist.rejected.toLocaleString("es-PE")} filas sin importe válido se omiten` : ""}.</p>
      <dl className="fv-details">{Object.entries(hist.columns).map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v || "No encontrada"}</dd></div>)}</dl>
      <label className="fv-check"><input type="checkbox" checked={withTax} onChange={e => setWithTax(e.target.checked)} /> Los importes incluyen IGV ({taxRate} %). Actívalo si el archivo trae el total con impuesto, como el registro de SUNAT.</label>
      <div className="fv-table-scroll" tabIndex={0} role="region" aria-label="Vista previa"><table><thead><tr><th>Fecha</th><th>Número</th><th>Cliente</th><th>Detalle</th><th>Importe</th></tr></thead>
        <tbody>{hist.rows.slice(0, 8).map((r, i) => <tr key={i}><td>{r.date || "—"}</td><td>{r.number || "—"}</td><td>{r.client || "—"}</td><td>{r.description || "—"}</td><td>{r.currency === "USD" ? "US$" : "S/"} {r.amount}</td></tr>)}</tbody></table></div>
      <div className="fv-actions-row"><button className="fv-button" disabled={!!busy} onClick={() => void runHistory()}>Importar {hist.rows.length.toLocaleString("es-PE")} comprobantes</button><button className="fv-button secondary" disabled={!!busy} onClick={() => setHist(null)}>Elegir otros archivos</button></div>
    </>}

    {busy && (wb || hist) && <p className="fv-caption" aria-live="polite">{busy}</p>}

    {job && <div className="fv-import-job" aria-live="polite">
      <p><strong>{job.status === "done" ? "¡Listo!" : job.status === "failed" ? "No se pudo terminar" : job.status === "cancelled" ? "Importación cancelada" : "Importando comprobantes…"}</strong></p>
      <span className="fv-bar"><i style={{ width: `${job.status === "done" ? 100 : pct}%` }} /></span>
      <small>{job.processed.toLocaleString("es-PE")} de {job.total.toLocaleString("es-PE")} revisados · {job.imported.toLocaleString("es-PE")} importados{job.skipped ? ` · ${job.skipped.toLocaleString("es-PE")} ya estaban o se omitieron` : ""}</small>
      {job.error && <p className="fv-error">{job.error}</p>}
      {!finished(job.status) && <><p className="fv-caption">Puedes seguir usando la web: la base de datos lo termina aunque cierres esta página.</p><button className="fv-button secondary" onClick={() => void cancel()}>Cancelar importación</button></>}
    </div>}
    <Msg m={m} />
  </div>;
}

/** «Deshacer» of an earlier Excel import (owner or admin). */
export function UndoImport({ org, job }: { org: string; job: string }) {
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  return <span className="fv-inline-action">
    <button className="fv-button secondary" disabled={busy} onClick={async () => {
      if (!window.confirm("¿Deshacer esta importación? Se quitan los comprobantes que trajo y los clientes y productos que creó (los clientes que ya usaste en otras ventas o cotizaciones se conservan).")) return;
      setBusy(true); const r = await undoImport(org, job).catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false); if (r.ok) router.refresh();
    }}>{busy ? "Deshaciendo…" : "Deshacer"}</button>
    <Msg m={m} />
  </span>;
}
