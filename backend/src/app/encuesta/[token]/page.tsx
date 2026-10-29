import type { Metadata } from "next";
import { NotFoundCard, PublicShell } from "@/components/public/Shell";
import SurveyForm from "@/components/public/SurveyForm";
import { isPortalToken } from "@/lib/publicdocs";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "¿Cómo te atendimos?", robots: { index: false, follow: false } };

export default async function SurveyPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!isPortalToken(token) || !process.env.SUPABASE_SERVICE_ROLE_KEY) return <NotFoundCard text="Esta encuesta no existe." />;
  const admin = createAdminClient();
  const { data: s } = await admin.from("surveys").select("org_id, answered_at").eq("token", token).maybeSingle();
  if (!s) return <NotFoundCard text="Esta encuesta no existe." />;
  const { data: org } = await admin.from("organizations").select("name, trade_name").eq("id", s.org_id).maybeSingle();
  const business = String(org?.trade_name || org?.name || "el negocio");
  return (
    <PublicShell eyebrow={business} title="¿Cómo te atendimos?" subtitle="Toma 10 segundos">
      {s.answered_at ? <p className="py-6 text-center text-[15px]">Ya respondiste esta encuesta. ¡Gracias! 💜</p> : <SurveyForm token={token} business={business} />}
    </PublicShell>
  );
}
