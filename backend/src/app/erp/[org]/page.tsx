import Link from "next/link";
import { workspaceContext } from "@/lib/erp/context";
import { licenseReady, sectors, visibleModules } from "@/lib/erp/access";

export default async function Dashboard({ params }: { params: Promise<{ org: string }> }) {
  const { org } = await params;
  const c = await workspaceContext(org);
  const sector = c.sector ? sectors[c.sector] : null;
  const available = visibleModules(c.license, c.access, c.sector);
  const work = available.filter(m => m.table).slice(0, 4);
  const counts = await Promise.all(work.map(async m => {
    let query = c.db.from(m.table!).select("id", { count: "exact", head: true }).eq("org_id", org);
    if (m.id === "agenda") query = query.eq("kind", "cita");
    if (m.id === "trabajos") query = query.neq("kind", "cita");
    const result = await query;
    return { ...m, count: result.error ? null : result.count };
  }));
  return <>
    <section className="fv-heading"><p className="fv-eyebrow">CENTRO DE TRABAJO</p><h1>{sector?.title ?? "Tu empresa, en un mismo lugar"}</h1><p>{sector?.detail ?? "Selecciona una tarea para continuar."}</p></section>
    {!licenseReady(c.license) ? <section className="fv-empty"><h2>Verifica el acceso de tu empresa</h2><p>{c.license.message || "La licencia no permite operar en este momento. Consulta con el administrador de tu empresa."}</p>{available.some(m => m.id === "plan") && <Link className="fv-button" href={`/erp/${org}/plan`}>Consultar mi plan</Link>}</section> : <>
      <section className={`fv-pulse fv-sector-${c.sector ?? "general"}`} aria-label="Registros de la empresa">{counts.map((m, i) => <Link key={m.id} href={`/erp/${org}/${m.id}`}><span className="fv-eyebrow">0{i + 1} / {m.title}</span><strong>{m.count === null ? "—" : new Intl.NumberFormat("es-PE").format(m.count)}</strong><span>{m.count === null ? "No disponible; abre el módulo para reintentar" : "Registros accesibles"} ↗</span></Link>)}</section>
      <section className="fv-next"><div><p className="fv-eyebrow">SIGUIENTE PASO</p><h2>Continúa tu jornada</h2><p>Accesos según tu rubro y tus permisos actuales.</p></div><div className="fv-task-list">{work.map(m => <Link key={m.id} href={`/erp/${org}/${m.id}`}><span>{m.title}</span><span aria-hidden="true">→</span></Link>)}{!work.length && <p>No hay módulos operativos habilitados para tu usuario.</p>}</div></section>
    </>}
  </>;
}
