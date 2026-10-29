import type { Metadata } from "next";
import BookingForm from "@/components/public/BookingForm";
import { NotFoundCard, PublicShell } from "@/components/public/Shell";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Reserva tu cita" };

export default async function BookPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const s = (slug ?? "").toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/.test(s) || !process.env.SUPABASE_SERVICE_ROLE_KEY) return <NotFoundCard text="Este negocio no recibe reservas en línea." />;
  const admin = createAdminClient();
  const { data: st } = await admin.from("org_store").select("org_id, enabled, booking, booking_services, booking_hours, whatsapp, headline").eq("slug", s).maybeSingle();
  if (!st || !st.enabled || !st.booking) return <NotFoundCard text="Este negocio no recibe reservas en línea." />;
  const { data: org } = await admin.from("organizations").select("name, trade_name").eq("id", st.org_id).maybeSingle();
  const business = String(org?.trade_name || org?.name || "");
  return (
    <PublicShell eyebrow={business} title="Reserva tu cita" subtitle={(st.headline as string | null) ?? "Elige el día y la hora"}>
      <BookingForm slug={s} business={business} services={((st.booking_services as string[] | null) ?? []).slice(0, 30)} hours={(st.booking_hours as string | null) ?? ""} whatsapp={(st.whatsapp as string | null) ?? ""} />
    </PublicShell>
  );
}
