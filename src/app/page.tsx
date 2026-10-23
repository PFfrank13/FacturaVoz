import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import NewInvoice from "@/components/NewInvoice";

export default async function Home() {
  const supabase = await createClient();
  // Defensa en profundidad: no depender solo del middleware
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: invoices } = await supabase
    .from("invoices")
    .select("id, number, issue_date, status, clients(name)")
    .order("created_at", { ascending: false })
    .limit(20);

  return (
    <main className="mx-auto max-w-xl space-y-10 p-6">
      <h1 className="text-2xl font-bold">FacturaVoz</h1>
      <NewInvoice />
      <section>
        <h2 className="mb-2 font-semibold">Últimas facturas</h2>
        <ul className="divide-y">
          {(invoices ?? []).map((i) => (
            <li key={i.id} className="flex justify-between py-2 text-sm">
              <span>
                {i.number} · {(i.clients as unknown as { name: string } | null)?.name ?? "—"}
              </span>
              <span className="text-gray-500">
                {i.issue_date} · {i.status}
              </span>
            </li>
          ))}
          {!invoices?.length && <li className="py-2 text-sm text-gray-500">Aún no hay facturas.</li>}
        </ul>
      </section>
    </main>
  );
}
