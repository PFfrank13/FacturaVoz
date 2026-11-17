import { notFound, redirect } from "next/navigation";
import { isOrgId } from "@/lib/solvex";

/**
 * Enlace "Ir a FacturaVoz" que construye Solvex Hub para un cliente: /solvex/ir/{tenant_ref}.
 * tenant_ref = organizations.id. No es un enlace de pago: lleva al espacio de trabajo web de ESA empresa.
 * La sesión la exige el middleware (sin sesión → /login?next=/solvex/ir/{org}) y la pertenencia la verifica
 * workspaceContext() en /erp/{org} (si no eres miembro: 404). No se consulta ni se expone nada aquí.
 */
export const dynamic = "force-dynamic";

export default async function SolvexGo({ params }: { params: Promise<{ org: string }> }) {
  const { org } = await params;
  if (!isOrgId(org)) notFound();
  redirect(`/erp/${org.toLowerCase()}`);
}
