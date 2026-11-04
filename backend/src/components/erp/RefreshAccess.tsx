"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function RefreshAccess({ org }: { org: string }) {
  const router = useRouter();
  useEffect(() => {
    const db = createClient();
    const refresh = () => router.refresh();
    const onVisible = () => { if (document.visibilityState === "visible") refresh(); };
    const channel = db.channel(`erp-license-${org}`).on("postgres_changes", { event: "*", schema: "public", table: "org_licenses", filter: `org_id=eq.${org}` }, refresh).subscribe();
    const timer = window.setInterval(onVisible, 60_000);
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", onVisible);
    return () => { clearInterval(timer); window.removeEventListener("focus", refresh); document.removeEventListener("visibilitychange", onVisible); void db.removeChannel(channel); };
  }, [org, router]);
  return <button className="fv-button secondary" onClick={() => router.refresh()}>Actualizar</button>;
}
