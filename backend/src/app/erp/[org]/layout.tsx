import Link from "next/link";
import { workspaceContext } from "@/lib/erp/context";
import { sectors, visibleModules } from "@/lib/erp/access";
import RefreshAccess from "@/components/erp/RefreshAccess";
import RailNav from "@/components/erp/RailNav";
import "../erp.css";

export const dynamic = "force-dynamic";
export default async function WorkspaceLayout({ children, params }: { children: React.ReactNode; params: Promise<{ org: string }> }) {
  const { org } = await params;
  const c = await workspaceContext(org);
  return <div className="fv-workspace">
    <a className="fv-skip" href="#workspace-content">Saltar al contenido</a>
    <aside className="fv-rail">
      <Link className="fv-wordmark" href="/">Factura<span>Voz</span><i aria-hidden="true">▂▅▃▇</i></Link>
      <p className="fv-eyebrow">{c.sector ? sectors[c.sector].name : "TU EMPRESA"}</p>
      <strong className="fv-org-name">{c.organization.name}</strong>
      <RailNav links={[{ id: "inicio", href: `/erp/${org}`, label: "Inicio" }, ...visibleModules(c.license, c.access, c.sector).map(m => ({ id: m.id, href: `/erp/${org}/${m.id}`, label: m.id === "clientes" && c.sector === "consultorio" ? "Pacientes" : m.id === "clientes" && c.sector === "educacion" ? "Alumnos y contactos" : m.title }))]} />
      <Link className="fv-switch" href="/">⇄ Cambiar empresa</Link>
    </aside>
    <div className="fv-workarea">
      <header className="fv-topbar">
        <span className="fv-user"><b aria-hidden="true">{(c.access.display_name || c.user.email || "?").trim().slice(0, 1).toUpperCase()}</b>
          <span><strong>{c.access.display_name || c.user.email}</strong><small>{c.access.role === "owner" ? "Dueño" : c.access.role === "admin" ? "Administrador" : c.access.role === "finanzas" ? "Finanzas" : c.access.role === "tecnico" ? "Técnico" : "Cajero"} · {c.organization.name}</small></span></span>
        <RefreshAccess org={org} />
      </header>
      <main id="workspace-content" className="fv-content">{children}</main>
    </div>
  </div>;
}
