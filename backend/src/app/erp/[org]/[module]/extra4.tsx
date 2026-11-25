import type React from "react";
import Link from "next/link";
import QRCode from "qrcode";
import type { workspaceContext } from "@/lib/erp/context";
import { money } from "@/lib/schemas";
import { limaDate } from "@/lib/erp/receipts";
import { clientKey } from "@/lib/erp/insights";
import { waPhone } from "@/lib/erp/clients";
import { can, hasFeature } from "@/lib/erp/access";
import LiveRefresh from "@/components/erp/LiveRefresh";
import { isoToLimaLocal, jobKinds, jobStatuses, normPlate, noticeText, canCut, obraSignal, statusOf, type JobStatus } from "@/lib/erp/rubros";
import { loadReceivables } from "./extra3";
import {
  Act, AssignExpense, ConsentButton, DeleteJob, DeleteNote, DoneReminder, JobForm, KitchenBoard, MaterialForm, MilestoneForm, NewJob, NoticeAction, NoticeLink, PackageForm, PhotoForm,
  PrivateNoteForm, ReminderForm, SplitBill, StatusPicker, UseSession, VehicleForm, emptyJob, type KitchenOrder, type Opt,
} from "@/components/erp/RubroBoards";
import { BookingForm, PrintButton } from "@/components/erp/BookingSettings";
import { jobAction } from "@/app/erp/actions";

type Ctx = Awaited<ReturnType<typeof workspaceContext>>;
export type Search4 = { job?: string; q?: string; cliente?: string; dias?: string; mesas?: string; desde?: string };
const failed = (what: string) => <div className="fv-empty" role="alert"><h2>No pudimos cargar {what}</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>;
const heading = (eyebrow: string, title: string, text: string, org: string, live?: readonly string[]) =>
  <section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{eyebrow}</p>{live && <LiveRefresh org={org} tables={live} />}</div><h1>{title}</h1><p>{text}</p></section>;
const tone = (t: string) => ({ "--tone": t }) as React.CSSProperties;
const n = (v: unknown) => (v == null || v === "" ? 0 : Number(v) || 0);
const one = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] : v) ?? null;
const dm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const when = (iso: string | null) => iso ? new Intl.DateTimeFormat("es-PE", { weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso)) : "Sin fecha";
const hour = (iso: string) => new Intl.DateTimeFormat("es-PE", { hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
const liveJobs = ["jobs"] as const;
const liveKitchen = ["quotes"] as const;
const jobCols = "id,client_id,title,kind,status,assigned_to,scheduled_at,duration_min,address,contact_phone,notes,tech_note,amount,invoice_id,done_at,created_at,clients(name,phone)";
type JobRow = { id: string; client_id: string | null; title: string; kind: string; status: string; assigned_to: string | null; scheduled_at: string | null; duration_min: number | null; address: string | null;
  contact_phone: string | null; notes: string | null; tech_note: string | null; amount: number | string | null; invoice_id: string | null; done_at: string | null; created_at: string; clients: unknown };

async function basics(c: Ctx, org: string) {
  const [settings, clients, team] = await Promise.all([
    c.db.from("org_settings").select("job_statuses").eq("org_id", org).maybeSingle(),
    c.db.from("clients").select("id,name,phone,extra").eq("org_id", org).order("name").limit(3000),
    c.db.rpc("team_members", { p_org: org }),
  ]);
  const statuses = jobStatuses(c.sector, (settings.data as { job_statuses?: unknown } | null)?.job_statuses);
  type Cl = { id: string; name: string; phone: string | null; extra: Record<string, unknown> | null };
  const cl = (clients.data ?? []) as Cl[];
  const tm: Opt[] = ((team.data ?? []) as { user_id: string; display_name: string | null; email: string | null }[]).map(t => ({ id: t.user_id, name: t.display_name || (t.email ?? "").split("@")[0] || "Sin nombre" }));
  return { statuses, clients: cl, clientOpts: cl.map(x => ({ id: x.id, name: x.name })) as Opt[], team: tm };
}

/** Web modules of the other industries (v3.11): same tables and rules as the mobile app. */
export async function renderExtra4(id: string, c: Ctx, org: string, title: string, search: Search4) {
  const cur = c.organization.currency || "PEN";
  const fmt = (v: number) => money(v, cur);
  const name = c.organization.name;
  const today = limaDate(new Date());

  if (id === "trabajos") {
    const b = await basics(c, org);
    const teamName = new Map(b.team.map(t => [t.id, t.name] as const));
    if (search.job && /^[0-9a-f-]{36}$/.test(search.job)) {
      const [job, mats, ms, media, events, prods] = await Promise.all([
        c.db.from("jobs").select(jobCols).eq("org_id", org).eq("id", search.job).maybeSingle(),
        c.db.from("job_materials").select("id,description,quantity,unit_price,discounted").eq("job_id", search.job).order("created_at"),
        c.db.from("job_milestones").select("id,title,amount,due_date,status,invoice_id,position").eq("job_id", search.job).order("position"),
        c.db.from("media_files").select("id,path,kind,caption").eq("org_id", org).eq("job_id", search.job).order("created_at", { ascending: false }).limit(40),
        c.db.from("job_events").select("from_status,to_status,created_at").eq("job_id", search.job).order("created_at"),
        c.db.from("products").select("id,name").eq("org_id", org).eq("active", true).order("name").limit(2000),
      ]);
      const j = job.data as JobRow | null;
      if (!j) return <>{heading(`TRABAJOS / ${name}`, title, "", org)}<div className="fv-empty"><h2>No encontramos ese trabajo</h2><p><Link className="fv-link" href={`/erp/${org}/trabajos`}>Volver a trabajos</Link></p></div></>;
      const cl = one(j.clients as { name: string; phone: string | null } | null);
      const paths = ((media.data ?? []) as { path: string }[]).map(m => m.path);
      const signed = paths.length ? await c.db.storage.from("org-media").createSignedUrls(paths, 3600) : { data: [] };
      const urls = new Map((signed.data ?? []).map(s => [s.path, s.signedUrl] as const));
      type Mat = { id: string; description: string; quantity: number | string; unit_price: number | string; discounted: boolean };
      type Ms = { id: string; title: string; amount: number | string; due_date: string | null; status: string; invoice_id: string | null; position: number };
      const materials = (mats.data ?? []) as Mat[], milestones = (ms.data ?? []) as Ms[];
      const matTotal = materials.reduce((s, m) => s + n(m.quantity) * n(m.unit_price), 0);
      const pending = materials.some(m => !m.discounted);
      const st = statusOf(b.statuses, j.status);
      const phone = waPhone(j.contact_phone || cl?.phone);
      return <>{heading(`TRABAJOS / ${name}`, j.title, `${jobKinds[j.kind] ?? j.kind}${cl ? ` · ${cl.name}` : ""} · ${when(j.scheduled_at)}`, org, liveJobs)}
        <div className="fv-actions-row"><Link className="fv-button secondary" href={`/erp/${org}/trabajos`}>‹ Todos los trabajos</Link>
          <span className="fv-pill" style={{ background: st.color, color: "#fff" }}>{st.label}</span><StatusPicker org={org} id={j.id} current={j.status} statuses={b.statuses} />
          {phone && <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${phone}?text=${encodeURIComponent(`Hola${cl ? ` ${cl.name.split(" ")[0]}` : ""}, te escribe ${name} sobre tu ${jobKinds[j.kind]?.toLowerCase() ?? "trabajo"}: ${j.title}. Estado: ${st.label}.`)}`}>Avisar por WhatsApp</a>}
          <DeleteJob org={org} id={j.id} back={`/erp/${org}/trabajos`} /></div>
        <div className="fv-settings-grid">
          <JobForm org={org} title="Datos del trabajo" statuses={b.statuses} clients={b.clientOpts} team={b.team} appointment={false}
            v={{ id: j.id, title: j.title, client_id: j.client_id ?? "", kind: j.kind, status: j.status, assigned_to: j.assigned_to ?? "", scheduled_at: isoToLimaLocal(j.scheduled_at), duration_min: j.duration_min ? String(j.duration_min) : "",
              address: j.address ?? "", contact_phone: j.contact_phone ?? "", notes: j.notes ?? "", tech_note: j.tech_note ?? "", amount: j.amount == null ? "" : String(n(j.amount)) }} />
          <div className="fv-stack">
            <section className="fv-create fv-settings-card"><h3>Materiales y repuestos</h3>
              {materials.length ? <ul className="fv-lines">{materials.map(m => <li key={m.id}><span>{n(m.quantity)} × {m.description}<small> {fmt(n(m.unit_price))} c/u{m.discounted ? " · descontado del inventario" : ""}</small></span>
                <span>{fmt(n(m.quantity) * n(m.unit_price))} {!m.discounted && <Act label="Quitar" link run={jobAction.bind(null, org, "material_del", m.id)} />}</span></li>)}</ul> : <p className="fv-muted">Aún sin materiales.</p>}
              {materials.length > 0 && <p className="fv-caption">Total materiales: <b>{fmt(matTotal)}</b></p>}
              <MaterialForm org={org} jobId={j.id} products={(prods.data ?? []) as Opt[]} />
              {pending && <Act label="Descontar del inventario" run={jobAction.bind(null, org, "consume", j.id)} />}
            </section>
            <section className="fv-create fv-settings-card"><h3>Hitos de cobro</h3>
              {milestones.length ? <ul className="fv-lines">{milestones.map(m => <li key={m.id}><span>{m.title}<small>{m.due_date ? ` · vence ${dm(m.due_date)}` : ""}</small></span>
                <span>{fmt(n(m.amount))} {m.status === "facturado" ? <span className="fv-pill is-ok">Facturado</span> : <>{can(c.access, "sell") && <Act label="Facturar" primary run={jobAction.bind(null, org, "milestone_invoice", m.id)} />}<Act label="Quitar" link run={jobAction.bind(null, org, "milestone_del", m.id)} /></>}</span></li>)}</ul>
                : <p className="fv-muted">Divide el cobro en partes (adelanto, avance, entrega) y factura cada una con un clic.</p>}
              <MilestoneForm org={org} jobId={j.id} position={milestones.length} />
            </section>
            <section className="fv-create fv-settings-card"><h3>Fotos</h3>
              {paths.length > 0 && <div className="fv-gallery">{((media.data ?? []) as { id: string; path: string; kind: string; caption: string | null }[]).map(m => urls.get(m.path) &&
                <figure key={m.id}>{/* eslint-disable-next-line @next/next/no-img-element */}<img src={urls.get(m.path) ?? ""} alt={m.caption ?? m.kind} /><figcaption>{m.kind === "antes" ? "Antes" : m.kind === "despues" ? "Después" : ""}{m.caption ? ` · ${m.caption}` : ""}</figcaption></figure>)}</div>}
              <PhotoForm org={org} jobId={j.id} clientId={j.client_id} />
            </section>
            {(events.data ?? []).length > 0 && <section className="fv-create fv-settings-card"><h3>Historial</h3><ul className="fv-lines">{((events.data ?? []) as { from_status: string | null; to_status: string; created_at: string }[]).map((e, i) =>
              <li key={i}><span>{e.from_status ? `${statusOf(b.statuses, e.from_status).label} → ` : ""}{statusOf(b.statuses, e.to_status).label}</span><small>{when(e.created_at)}</small></li>)}</ul></section>}
          </div>
        </div></>;
    }
    const res = await c.db.from("jobs").select(jobCols).eq("org_id", org).neq("kind", "cita").order("position").order("created_at", { ascending: false }).limit(500);
    const rows = (res.data ?? []) as JobRow[];
    const open = b.statuses.filter(s => !s.done), done = b.statuses.filter(s => s.done);
    const card = (j: JobRow) => { const cl = one(j.clients as { name: string } | null); return <li key={j.id}><Link href={`/erp/${org}/trabajos?job=${j.id}`}>
      <strong>{j.title}</strong><small>{jobKinds[j.kind] ?? j.kind}{cl ? ` · ${cl.name}` : ""}</small><small>{j.scheduled_at ? when(j.scheduled_at) : "Sin programar"}{j.assigned_to ? ` · ${teamName.get(j.assigned_to) ?? "técnico"}` : ""}</small>
      {j.amount != null && <b>{fmt(n(j.amount))}</b>}</Link></li>; };
    return <>{heading(`TRABAJOS / ${name}`, title, "Cada trabajo con su estado, técnico, materiales, fotos y hitos de cobro. Es el mismo tablero del móvil.", org, liveJobs)}
      <div className="fv-actions-row"><NewJob org={org} title="Nuevo trabajo" v={emptyJob("servicio", b.statuses[0]?.key ?? "nuevo")} statuses={b.statuses} clients={b.clientOpts} team={b.team} appointment={false} /></div>
      {res.error ? failed("los trabajos") : !rows.length ? <div className="fv-empty"><h2>Aún no hay trabajos</h2><p>Crea el primero con el botón de arriba.</p></div> : <>
        <div className="fv-kanban">{open.map(s => { const list = rows.filter(r => r.status === s.key); return <section key={s.key} style={{ "--k": s.color } as React.CSSProperties}><h3>{s.label} <span>{list.length}</span></h3><ul>{list.map(card)}</ul></section>; })}</div>
        {done.length > 0 && <details className="fv-create" style={{ padding: 16 }}><summary>Terminados ({rows.filter(r => done.some(d => d.key === r.status)).length})</summary><ul className="fv-kanban-done">{rows.filter(r => done.some(d => d.key === r.status)).slice(0, 60).map(card)}</ul></details>}
        {rows.some(r => !b.statuses.some(s => s.key === r.status)) && <section className="fv-create" style={{ padding: 16 }}><h3>Con otro estado</h3><ul className="fv-kanban-done">{rows.filter(r => !b.statuses.some(s => s.key === r.status)).map(card)}</ul></section>}
      </>}</>;
  }

  if (id === "agenda") {
    const b = await basics(c, org);
    const from = /^\d{4}-\d{2}-\d{2}$/.test(search.desde ?? "") ? search.desde! : today;
    const to = new Date(`${from}T12:00:00Z`); to.setUTCDate(to.getUTCDate() + 14);
    const [res, store] = await Promise.all([
      c.db.from("jobs").select(jobCols).eq("org_id", org).eq("kind", "cita").gte("scheduled_at", `${from}T05:00:00Z`).lt("scheduled_at", `${to.toISOString().slice(0, 10)}T05:00:00Z`).order("scheduled_at").limit(800),
      c.db.from("org_store").select("slug,booking,booking_services,booking_hours").eq("org_id", org).maybeSingle(),
    ]);
    const rows = (res.data ?? []) as JobRow[];
    const byDay = new Map<string, JobRow[]>();
    for (const r of rows) { const d = limaDate(new Date(r.scheduled_at!)); byDay.set(d, [...(byDay.get(d) ?? []), r]); }
    const prev = new Date(`${from}T12:00:00Z`); prev.setUTCDate(prev.getUTCDate() - 14);
    const dayName = (d: string) => new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
    const sr = store.data as { slug: string; booking: boolean | null; booking_services: string[] | null; booking_hours: string | null } | null;
    const pending = rows.filter(r => r.status === "nuevo").length;
    return <>{heading(`AGENDA / ${name}`, title, "Tus citas de las próximas dos semanas. Confírmalas por WhatsApp y márcalas al atender.", org, liveJobs)}
      <div className="fv-kpis"><div style={tone("#3ee6b0")}><span>Hoy</span><strong>{(byDay.get(today) ?? []).length}</strong><small>citas</small></div>
        <div style={tone("#ffb35c")}><span>Por confirmar</span><strong>{pending}</strong><small>en estas dos semanas</small></div>
        <div style={tone("#6fb7ff")}><span>Reservas en línea</span><strong>{sr?.booking ? "Activas" : "Apagadas"}</strong><small>{sr?.slug ? `/reservar/${sr.slug}` : "crea tu dirección en Tienda en línea"}</small></div></div>
      <div className="fv-actions-row"><NewJob org={org} title="Nueva cita" v={emptyJob("cita", b.statuses[0]?.key ?? "nuevo", `${today}T09:00`)} statuses={b.statuses} clients={b.clientOpts} team={b.team} appointment />
        {from > today && <Link className="fv-button secondary" href={`/erp/${org}/agenda?desde=${prev.toISOString().slice(0, 10) < today ? today : prev.toISOString().slice(0, 10)}`}>‹ Anteriores</Link>}
        <Link className="fv-button secondary" href={`/erp/${org}/agenda?desde=${to.toISOString().slice(0, 10)}`}>Siguientes 2 semanas ›</Link></div>
      {res.error ? failed("tu agenda") : !rows.length ? <div className="fv-empty"><h2>Sin citas en estas dos semanas</h2><p>Agenda una arriba o activa las reservas en línea para que tus clientes reserven solos.</p></div>
        : <div className="fv-agenda">{[...byDay.entries()].map(([d, list]) => <section key={d}><h3>{d === today ? "Hoy · " : ""}{dayName(d)}</h3><ul>{list.map(r => {
          const cl = one(r.clients as { name: string; phone: string | null } | null); const st = statusOf(b.statuses, r.status); const ph = waPhone(r.contact_phone || cl?.phone);
          return <li key={r.id} style={{ "--k": st.color } as React.CSSProperties}><b>{hour(r.scheduled_at!)}</b><span><strong>{r.title}</strong><small>{cl?.name ?? "Sin cliente"}{r.duration_min ? ` · ${r.duration_min} min` : ""}{r.assigned_to ? ` · ${b.team.find(t => t.id === r.assigned_to)?.name ?? ""}` : ""}</small></span>
            <span className="fv-actions"><StatusPicker org={org} id={r.id} current={r.status} statuses={b.statuses} />
              {ph && <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${ph}?text=${encodeURIComponent(`Hola${cl ? ` ${cl.name.split(" ")[0]}` : ""}, te escribe ${name}: te confirmamos tu cita (${r.title}) el ${dayName(d)} a las ${hour(r.scheduled_at!)}. ¿Nos confirmas?`)}`}>Confirmar por WhatsApp</a>}</span></li>; })}</ul></section>)}</div>}
      {can(c.access, "settings") && <BookingForm org={org} slug={sr?.slug ?? null} enabled={!!sr?.booking} services={sr?.booking_services ?? []} hours={sr?.booking_hours ?? ""} />}
    </>;
  }

  if (id === "placas") {
    const b = await basics(c, org);
    const q = normPlate(search.q ?? "");
    let hits: { id: string; client_id: string; name: string; model: string | null; serial: string | null; client: { name: string; phone: string | null } | null }[] = [];
    let jobs: JobRow[] = [];
    if (q.length >= 2) {
      const pattern = q.length > 3 ? `%${q.slice(0, 3)}%${q.slice(3)}%` : `%${q}%`;
      const r = await c.db.from("client_assets").select("id,client_id,name,model,serial,clients(name,phone)").eq("org_id", org).ilike("serial", pattern).limit(30);
      hits = ((r.data ?? []) as { id: string; client_id: string; name: string; model: string | null; serial: string | null; clients: unknown }[]).map(h => ({ ...h, client: one(h.clients as { name: string; phone: string | null } | null) }))
        .filter(h => normPlate(h.serial ?? "").includes(q));
      const ids = [...new Set(hits.map(h => h.client_id))];
      if (ids.length) jobs = ((await c.db.from("jobs").select(jobCols).eq("org_id", org).in("client_id", ids).order("created_at", { ascending: false }).limit(30)).data ?? []) as JobRow[];
    }
    return <>{heading(`TALLER / ${name}`, title, "Escribe la placa y ves el carro, su dueño y todo lo que le hiciste.", org)}
      <form className="fv-create fv-inline-form" style={{ padding: 16 }}><label className="fv-search"><span>Placa</span><input name="q" defaultValue={search.q ?? ""} placeholder="ABC-123" autoFocus maxLength={12} /></label><button className="fv-button">Buscar</button></form>
      {q.length >= 2 && (hits.length ? <ul className="fv-collect">{hits.map(h => { const ph = waPhone(h.client?.phone); const hj = jobs.filter(j => j.client_id === h.client_id);
        return <li key={h.id}><div className="fv-collect-main"><strong className="fv-plate">{h.serial}</strong><small>{h.name}{h.model ? ` · ${h.model}` : ""}</small><small>Dueño: {h.client?.name ?? "—"}{h.client?.phone ? ` · ${h.client.phone}` : ""}</small></div>
          <div className="fv-actions">{ph && <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${ph}`}>WhatsApp</a>}</div>
          {hj.length > 0 && <ul className="fv-lines fv-span">{hj.map(j => <li key={j.id}><Link className="fv-link" href={`/erp/${org}/trabajos?job=${j.id}`}>{j.title}</Link><small>{statusOf(b.statuses, j.status).label} · {when(j.scheduled_at ?? j.created_at)}</small></li>)}</ul>}</li>; })}</ul>
        : <><div className="fv-empty"><h2>No encontramos la placa {q}</h2><p>Si es un carro nuevo, regístralo con su dueño.</p></div>{q.length >= 5 && <VehicleForm org={org} clients={b.clientOpts} plate={q} />}</>)}
    </>;
  }

  if (id === "recordatorios") {
    const b = await basics(c, org);
    const lim = new Date(`${today}T12:00:00Z`); lim.setUTCDate(lim.getUTCDate() + 30);
    const res = await c.db.from("service_reminders").select("id,client_id,due_on,title,note,clients(name,phone),client_assets(name)").eq("org_id", org).is("done_at", null).lte("due_on", lim.toISOString().slice(0, 10)).order("due_on").limit(300);
    type R = { id: string; client_id: string; due_on: string; title: string; note: string | null; clients: unknown; client_assets: unknown };
    const rows = (res.data ?? []) as R[];
    return <>{heading(`CLIENTES / ${name}`, title, "Mantenimientos, controles y retoques: a quién le toca volver en los próximos 30 días.", org)}
      {res.error ? failed("los recordatorios") : !rows.length ? <div className="fv-empty"><h2>A nadie le toca volver pronto</h2><p>Crea un recordatorio abajo cuando atiendas a un cliente.</p></div>
        : <ul className="fv-collect">{rows.map(r => { const cl = one(r.clients as { name: string; phone: string | null } | null); const asset = one(r.client_assets as { name: string } | null); const ph = waPhone(cl?.phone); const late = r.due_on < today;
          return <li key={r.id} className={late ? "is-late" : ""}><div className="fv-collect-main"><strong>{cl?.name ?? "—"} · {r.title}</strong><small>{late ? "Atrasado desde" : "Toca el"} {dm(r.due_on)}{asset ? ` · ${asset.name}` : ""}{r.note ? ` · ${r.note}` : ""}</small></div>
            <div className="fv-actions">{ph && <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${ph}?text=${encodeURIComponent(`Hola ${(cl?.name ?? "").split(" ")[0]}, te escribe ${name}: ya te toca ${r.title.toLowerCase()}. ¿Te reservo un horario?`)}`}>Escribirle</a>}<DoneReminder org={org} id={r.id} /></div></li>; })}</ul>}
      <ReminderForm org={org} clients={b.clientOpts} />
    </>;
  }

  if (id === "paquetes") {
    const b = await basics(c, org);
    const since = new Date(); since.setDate(since.getDate() - 90);
    const [res, ns] = await Promise.all([
      c.db.from("service_packages").select("id,client_id,name,sessions_total,sessions_used,price,expires_on,clients(name)").eq("org_id", org).order("created_at", { ascending: false }).limit(300),
      c.db.from("jobs").select("client_id,clients(name)").eq("org_id", org).eq("status", "no_vino").gte("scheduled_at", since.toISOString()).limit(1000),
    ]);
    type P = { id: string; name: string; sessions_total: number; sessions_used: number; price: number | string | null; expires_on: string | null; clients: unknown };
    const all = (res.data ?? []) as P[];
    const active = all.filter(p => p.sessions_total - p.sessions_used > 0 && !(p.expires_on && p.expires_on < today));
    const noShow = new Map<string, number>();
    for (const j of (ns.data ?? []) as { clients: unknown }[]) { const nm = one(j.clients as { name: string } | null)?.name ?? "Sin nombre"; noShow.set(nm, (noShow.get(nm) ?? 0) + 1); }
    return <>{heading(`CLIENTES / ${name}`, title, "Sesiones prepagadas: cuántas le quedan a cada cliente. Y quién falta a sus citas.", org)}
      <div className="fv-cash-grid">
        <section className="fv-create fv-cash-card"><h3>Paquetes activos ({active.length})</h3>
          {!active.length ? <p className="fv-muted">Nadie tiene sesiones pendientes.</p> : <ul className="fv-lines">{active.map(p => <li key={p.id}><span><strong>{one(p.clients as { name: string } | null)?.name ?? "—"} · {p.name}</strong>
            <small>Usó {p.sessions_used} de {p.sessions_total}{p.expires_on ? ` · vence ${dm(p.expires_on)}` : ""}</small><span className="fv-bar"><i style={{ width: `${(p.sessions_used / p.sessions_total) * 100}%` }} /></span></span><UseSession org={org} id={p.id} /></li>)}</ul>}
        </section>
        <section className="fv-create fv-cash-card"><h3>No vinieron (últimos 90 días)</h3>
          {!noShow.size ? <p className="fv-muted">Nadie marcado como «No vino». Márcalo en la Agenda cuando pase.</p> : <><ul className="fv-lines">{[...noShow.entries()].sort((a, b2) => b2[1] - a[1]).map(([k, v]) => <li key={k}><span>{k}</span><b className={v >= 2 ? "fv-neg" : ""}>{v} {v === 1 ? "vez" : "veces"}</b></li>)}</ul>
            <p className="fv-caption">Idea: a quien faltó 2 veces o más, pídele un adelanto (Yape) para reservar.</p></>}
        </section>
      </div>
      <PackageForm org={org} clients={b.clientOpts} />
    </>;
  }

  if (id === "historial") {
    const b = await basics(c, org);
    const sel = b.clients.find(x => x.id === search.cliente) ?? null;
    const notes = sel ? await c.db.from("private_notes").select("id,body,created_at,author_id").eq("client_id", sel.id).order("created_at", { ascending: false }).limit(200) : { data: [] };
    const consent = sel?.extra?.consentimiento_salud as string | undefined;
    return <>{heading(`PACIENTES / ${name}`, title, "Notas por paciente que solo ven el profesional, el dueño y el administrador. No las lee el Copiloto ni salen en reportes.", org)}
      <form className="fv-create fv-inline-form" style={{ padding: 16 }}><label className="fv-search"><span>Paciente</span><select name="cliente" defaultValue={sel?.id ?? ""}><option value="" disabled>Elige…</option>{b.clientOpts.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select></label><button className="fv-button">Abrir</button></form>
      {sel && <section className="fv-create fv-settings-card">
        <h3>{sel.name} {consent ? <span className="fv-pill is-ok">Consentimiento del {dm(consent)}</span> : <span className="fv-pill is-wait">Sin consentimiento</span>}</h3>
        {!consent ? <><p className="fv-caption">Los datos de salud son sensibles (Ley 29733). Antes de guardar notas necesitas el consentimiento por escrito del paciente y guardarlo en tu archivo.</p><ConsentButton org={org} clientId={sel.id} /></>
          : <PrivateNoteForm org={org} clientId={sel.id} />}
        {((notes.data ?? []) as { id: string; body: string; created_at: string; author_id: string }[]).map(x => <article key={x.id} className="fv-note"><small>{when(x.created_at)}{x.author_id !== c.user.id ? " · de otro profesional" : ""}</small><p>{x.body}</p>{x.author_id === c.user.id && <DeleteNote org={org} id={x.id} />}</article>)}
      </section>}
    </>;
  }

  if (id === "corte" || id === "morosidad") {
    const b = await basics(c, org);
    const rec = await loadReceivables(c, org);
    const byName = new Map(b.clients.map(x => [clientKey(x.name), x] as const));
    type D = { name: string; balance: number; count: number; maxDays: number };
    const debt = new Map<string, D>();
    for (const r of rec.rows.filter(r => r.currency === cur)) {
      const late = r.due_date ? Math.round((Date.parse(`${today}T12:00:00Z`) - Date.parse(`${r.due_date}T12:00:00Z`)) / 86_400_000) : 0;
      const d = debt.get(r.client) ?? { name: r.client, balance: 0, count: 0, maxDays: 0 };
      d.balance = Math.round((d.balance + r.balance) * 100) / 100; d.count++; d.maxDays = Math.max(d.maxDays, late); debt.set(r.client, d);
    }
    if (id === "corte") {
      const min = [1, 5, 15, 30].includes(Number(search.dias)) ? Number(search.dias) : 1;
      const rows = [...debt.values()].filter(d => d.maxDays >= min).sort((a, b2) => b2.maxDays - a.maxDays);
      return <>{heading(`COBRANZA / ${name}`, title, "Abonados atrasados. Primero se avisa por WhatsApp; el corte se habilita desde el día siguiente al aviso. Registra cada corte y reconexión.", org)}
        <nav className="fv-chips">{[1, 5, 15, 30].map(d => <Link key={d} className="fv-chip" aria-pressed={min === d} href={`/erp/${org}/corte?dias=${d}`}>Atrasados {d}+ días</Link>)}</nav>
        {rec.error ? failed("los atrasos") : !rows.length ? <div className="fv-empty"><h2>Nadie está atrasado {min}+ días</h2><p>Bien: todos tus abonados están al día.</p></div>
          : <ul className="fv-collect">{rows.map(d => { const cl = byName.get(clientKey(d.name)); const ex = cl?.extra ?? {}; const cut = ex.servicio === "cortado"; const ph = waPhone(cl?.phone);
            return <li key={d.name} className={cut ? "is-late" : ""}><div className="fv-collect-main"><strong>{d.name} {cut && <span className="fv-pill is-off">Cortado</span>}</strong>
              <small>Debe {fmt(d.balance)} · {d.count} {d.count === 1 ? "recibo" : "recibos"} · {d.maxDays} días de atraso</small>{cl && !cut && <small>{noticeText(ex, "aviso_corte_fecha", today, "Sin aviso previo")}</small>}</div>
              <div className="fv-actions">{cl ? <>{ph && !cut && <NoticeLink org={org} mod="corte" clientId={cl.id} label="Aviso previo" phone={ph}
                text={`Hola ${d.name.split(" ")[0]}, te escribe ${name}. Tienes ${fmt(d.balance)} pendiente de tu servicio. Para evitar la suspensión, por favor regulariza tu pago. Si ya pagaste, envíanos tu constancia. ¡Gracias!`} />}
                {!cut ? (canCut(ex, today) ? <NoticeAction org={org} mod="corte" clientId={cl.id} action="cortado" label="Registrar corte" /> : <small className="fv-muted">El corte se habilita un día después del aviso</small>)
                  : <NoticeAction org={org} mod="corte" clientId={cl.id} action="activo" label="Registrar reconexión" />}</> : <small className="fv-muted">Sin ficha de cliente con ese nombre</small>}</div></li>; })}</ul>}
      </>;
    }
    const groups = new Map<string, D[]>();
    for (const d of debt.values()) { const g = String(byName.get(clientKey(d.name))?.extra?.grupo ?? "").trim() || "Sin grupo"; groups.set(g, [...(groups.get(g) ?? []), d]); }
    return <>{heading(`COBRANZA / ${name}`, title, "Pensiones vencidas por grupo u horario, con aviso amable al apoderado.", org)}
      {rec.error ? failed("las pensiones") : !groups.size ? <div className="fv-empty"><h2>Nadie debe pensiones</h2><p>Cuando una pensión venza sin pagarse aparecerá aquí, agrupada por grupo u horario.</p></div>
        : [...groups.entries()].sort((a, b2) => a[0].localeCompare(b2[0])).map(([g, list]) => <section key={g} className="fv-create fv-cash-card" style={{ marginBottom: 12 }}>
          <h3>{g} · {fmt(list.reduce((s, x) => s + x.balance, 0))}</h3><ul className="fv-lines">{list.sort((a, b2) => b2.maxDays - a.maxDays).map(d => { const cl = byName.get(clientKey(d.name)); const ex = cl?.extra ?? {}; const ph = waPhone(cl?.phone); const alumno = String(ex.alumno ?? "");
            return <li key={d.name}><span><strong>{d.name}</strong><small>{alumno ? `Alumno: ${alumno} · ` : ""}{fmt(d.balance)} · {d.maxDays} días{noticeText(ex, "aviso_pension_fecha", today) ? ` · ${noticeText(ex, "aviso_pension_fecha", today)}` : ""}</small></span>
              {cl && ph ? <NoticeLink org={org} mod="morosidad" clientId={cl.id} label="Avisar" phone={ph} text={`Hola, le escribe ${name}. Tiene una pensión pendiente de ${fmt(d.balance)}${alumno ? ` de ${alumno}` : ""}. ¿Le ayudamos con el pago? Gracias.`} /> : <small className="fv-muted">Sin celular</small>}</li>; })}</ul></section>)}
    </>;
  }

  if (id === "margen_obra") {
    const since = new Date(); since.setDate(since.getDate() - 120);
    const [jobs, ms, exp, free] = await Promise.all([
      c.db.from("jobs").select("id,title,status,clients(name)").eq("org_id", org).neq("kind", "cita").order("created_at", { ascending: false }).limit(500),
      c.db.from("job_milestones").select("job_id,amount,status").eq("org_id", org).limit(5000),
      c.db.from("expenses").select("job_id,total").eq("org_id", org).not("job_id", "is", null).limit(5000),
      c.db.from("expenses").select("id,spent_on,description,supplier_name,total").eq("org_id", org).is("job_id", null).gte("spent_on", since.toISOString().slice(0, 10)).order("spent_on", { ascending: false }).limit(100),
    ]);
    type O = { id: string; title: string; client: string; agreed: number; invoiced: number; spent: number };
    const by = new Map<string, O>(((jobs.data ?? []) as { id: string; title: string; clients: unknown }[]).map(j => [j.id, { id: j.id, title: j.title, client: one(j.clients as { name: string } | null)?.name ?? "", agreed: 0, invoiced: 0, spent: 0 }]));
    for (const m of (ms.data ?? []) as { job_id: string; amount: number | string; status: string }[]) { const o = by.get(m.job_id); if (!o) continue; o.agreed += n(m.amount); if (m.status === "facturado") o.invoiced += n(m.amount); }
    for (const e of (exp.data ?? []) as { job_id: string; total: number | string }[]) { const o = by.get(e.job_id); if (o) o.spent += n(e.total); }
    const rows = [...by.values()].filter(o => o.agreed > 0 || o.spent > 0).map(o => ({ ...o, margin: o.invoiced > 0 ? (o.invoiced - o.spent) / o.invoiced : null, sig: obraSignal(o.agreed, o.invoiced, o.spent) }))
      .sort((a, b2) => (a.margin ?? 9) - (b2.margin ?? 9));
    return <>{heading(`OBRAS / ${name}`, title, "Cobrado, gastado y lo que te queda en cada obra. Asigna tus gastos y subcontratistas a la obra que corresponde.", org)}
      <p className="fv-caption">Facturado = hitos ya facturados. Gastado = gastos y subcontratistas asignados a la obra (con IGV). Es una señal para revisar, no un cálculo contable.</p>
      {jobs.error ? failed("tus obras") : !rows.length ? <div className="fv-empty"><h2>Aún no hay obras con contrato o gastos</h2><p>Agrega hitos de cobro en cada trabajo y asígnale sus gastos abajo.</p></div>
        : <ul className="fv-collect">{rows.map(o => <li key={o.id} className={o.sig.alert === "over" ? "is-late" : ""}><div className="fv-collect-main"><strong><Link className="fv-link" href={`/erp/${org}/trabajos?job=${o.id}`}>{o.title}</Link></strong>
          <small>{o.client ? `${o.client} · ` : ""}Contrato {fmt(o.agreed)} · facturado {fmt(o.invoiced)} · gastado {fmt(o.spent)}</small>
          {o.sig.alert !== "none" && <small className="fv-neg">{o.sig.alert === "over" ? "Ya gastaste todo el contrato o más." : `Gastas más rápido de lo que facturas (${Math.round(o.sig.spentShare * 100)} % gastado vs ${Math.round(o.sig.invoicedShare * 100)} % facturado).`}</small>}</div>
          <div className="fv-collect-amount"><b className={o.margin != null && o.margin < 0.1 ? "fv-neg" : ""}>{o.margin == null ? "—" : `${Math.round(o.margin * 100)} %`}</b><small>margen</small></div></li>)}</ul>}
      <section className="fv-create fv-cash-card"><h3>Gastos sin obra (últimos 120 días)</h3>
        <AssignExpense org={org} jobs={[...by.values()].map(o => ({ id: o.id, name: o.title }))} expenses={((free.data ?? []) as { id: string; spent_on: string; description: string | null; supplier_name: string | null; total: number | string }[]).map(e => ({ id: e.id, label: `${dm(e.spent_on)} · ${e.supplier_name || e.description || "Gasto"} · ${fmt(n(e.total))}` }))} />
      </section>
    </>;
  }

  if (id === "carta") {
    const mesas = Math.min(60, Math.max(0, Number(search.mesas) || 0));
    const [res, prods, store] = await Promise.all([
      c.db.from("quotes").select("id,number,table_label,fulfillment,kitchen_status,notes,created_at,clients(name),quote_items(description,quantity,kitchen_note,position)").eq("org_id", org).in("kitchen_status", ["nuevo", "preparando", "listo"]).order("created_at").limit(100),
      c.db.from("products").select("id,name,unit_price").eq("org_id", org).eq("active", true).order("name").limit(2000),
      c.db.from("org_store").select("slug,enabled").eq("org_id", org).maybeSingle(),
    ]);
    type Q = { id: string; number: string; table_label: string | null; fulfillment: string | null; kitchen_status: string; notes: string | null; created_at: string; clients: unknown; quote_items: { description: string; quantity: number | string; kitchen_note: string | null; position: number }[] | null };
    const orders: KitchenOrder[] = ((res.data ?? []) as Q[]).map(q => ({ id: q.id, number: q.number, table: q.table_label, fulfillment: q.fulfillment, status: q.kitchen_status, notes: q.notes ?? "", created_at: q.created_at,
      client: one(q.clients as { name: string } | null)?.name ?? "", items: [...(q.quote_items ?? [])].sort((a, b2) => a.position - b2.position).map(i => ({ description: i.description, quantity: n(i.quantity), note: i.kitchen_note ?? "" })) }));
    const slug = (store.data as { slug: string } | null)?.slug ?? null;
    const site = (process.env.NEXT_PUBLIC_SITE_URL ?? process.env.APP_URL ?? "https://factura-voz-two.vercel.app").replace(/\/$/, "");
    const qrs = slug && mesas ? await Promise.all(Array.from({ length: mesas }, (_, i) => QRCode.toString(`${site}/tienda/${slug}?mesa=${i + 1}`, { type: "svg", margin: 1, width: 160 }))) : [];
    return <>{heading(`RESTAURANTE / ${name}`, title, "Pedidos de las mesas (QR), de la tienda y los que tomes aquí, en vivo. Pásalos de Nuevos a Preparando y a Listos.", org, liveKitchen)}
      {res.error ? failed("las comandas") : <KitchenBoard org={org} orders={orders} products={((prods.data ?? []) as { id: string; name: string; unit_price: number | string }[]).map(p => ({ id: p.id, name: p.name, price: n(p.unit_price) }))} />}
      <section className="fv-create fv-cash-card fv-qr-tables"><h3>QR para las mesas</h3>
        {!slug ? <p className="fv-muted">Primero crea tu carta en Tienda en línea{hasFeature(c.license, "tienda") ? <> (<Link className="fv-link" href={`/erp/${org}/tienda`}>abrir</Link>)</> : ""}: cada QR abre tu carta con el número de mesa y el pedido llega aquí.</p> : <>
          <form className="fv-inline-form"><label className="fv-search"><span>¿Cuántas mesas?</span><input name="mesas" type="number" min={1} max={60} defaultValue={mesas || 10} /></label><button className="fv-button secondary">Generar QR</button>
            {qrs.length > 0 && <PrintButton />}</form>
          {qrs.length > 0 && <div className="fv-qr-grid">{qrs.map((svg, i) => <figure key={i}><span dangerouslySetInnerHTML={{ __html: svg }} /><figcaption><b>MESA {i + 1}</b><small>Escanea, mira la carta y pide</small></figcaption></figure>)}</div>}
        </>}
      </section>
    </>;
  }

  if (id === "platos") {
    const res = await c.db.from("products").select("id,name,unit_price,unit_cost").eq("org_id", org).eq("active", true).order("name").limit(2000);
    const all = (res.data ?? []) as { id: string; name: string; unit_price: number | string; unit_cost: number | string | null }[];
    const dishes = all.filter(p => p.unit_cost != null && n(p.unit_price) > 0).map(p => ({ ...p, margin: (n(p.unit_price) - n(p.unit_cost)) / n(p.unit_price) })).sort((a, b2) => a.margin - b2.margin);
    return <>{heading(`RESTAURANTE / ${name}`, title, "Divide la cuenta con o sin propina, y mira cuánto te deja cada plato.", org)}
      <div className="fv-settings-grid">
        <SplitBill currency={cur} business={name} />
        <section className="fv-create fv-cash-card"><h3>Costo por plato</h3><p className="fv-caption">De menor a mayor margen (precio sin IGV menos costo).</p>
          {!dishes.length ? <p className="fv-muted">Registra el costo de tus platos en Productos para ver su margen.</p>
            : <ul className="fv-lines">{dishes.map(p => <li key={p.id}><span>{p.name}<small> precio {fmt(n(p.unit_price))} · costo {fmt(n(p.unit_cost))}</small></span><b className={p.margin < 0.3 ? "fv-neg" : p.margin < 0.5 ? "fv-warn" : "fv-up"}>{Math.round(p.margin * 100)} %</b></li>)}</ul>}
          {all.length > dishes.length && <p className="fv-caption">{all.length - dishes.length} platos sin costo registrado no aparecen aquí.</p>}
        </section>
      </div>
    </>;
  }

  return null;
}

export type { JobStatus };
