import Brand from "@/components/retail/Brand";
import Link from "next/link";
import { workspaceContext } from "@/lib/erp/context";
import { sectors, visibleModules } from "@/lib/erp/access";
import RefreshAccess from "@/components/erp/RefreshAccess";

export const dynamic = "force-dynamic";
export default async function WorkspaceLayout({ children, params }: { children: React.ReactNode; params: Promise<{ org: string }> }) {
  const { org } = await params;
  const c = await workspaceContext(org);
  return <div className="fv-workspace">
    <a className="fv-skip" href="#workspace-content">Saltar al contenido</a>
    <aside className="fv-rail">
      <Link className="fv-wordmark" href="/"><Brand /></Link>
      <p className="fv-eyebrow">{c.sector ? sectors[c.sector].name : "TU EMPRESA"}</p>
      <strong className="fv-org-name">{c.organization.name}</strong>
      <nav aria-label="Navegación de la empresa">
        <Link href={`/erp/${org}`}>Centro de control</Link>
        {visibleModules(c.license, c.access, c.sector).map(m => <Link key={m.id} href={`/erp/${org}/${m.id}`}>{m.id === "clientes" && c.sector === "consultorio" ? "Pacientes" : m.id === "clientes" && c.sector === "educacion" ? "Alumnos y contactos" : m.title}</Link>)}
      </nav>
      <Link className="fv-switch" href="/">⇄ Cambiar empresa</Link>
    </aside>
    <div className="fv-workarea">
      <header className="fv-topbar"><span>{c.access.display_name || c.user.email}</span><RefreshAccess org={org} /></header>
      <main id="workspace-content" className="fv-content">{children}</main>
    </div>
  </div>;
}
