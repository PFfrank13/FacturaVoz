import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) redirect("/login");
  const { data, error } = await db.from("organization_members").select("org_id,organizations(id,name)").eq("user_id", user.id);
  return <main className="fv-welcome">
    <p className="fv-eyebrow">SOLVEX RETAIL CONTROL</p>
    <h1>Tu negocio.<br /><span>Bajo tu control.</span></h1>
    <p>Elige la empresa con la que vas a trabajar. Tus datos y permisos son los mismos que en la aplicación móvil.</p>
    {error ? <p role="alert">No pudimos consultar tus empresas. Actualiza la página para reintentar.</p> :
      <div className="fv-company-list">{data?.map(row => {
        const organization = row.organizations as unknown as { id: string; name: string } | null;
        return organization && <Link key={row.org_id} href={`/erp/${row.org_id}`}><span>{organization.name}</span><span aria-hidden="true">↗</span></Link>;
      })}{!data?.length && <p>Aún no tienes empresas asignadas. Tu administrador puede incorporarte desde Equipo.</p>}</div>}
    <p className="fv-caption">Una empresa · Una licencia · Todos tus dispositivos</p>
  </main>;
}
