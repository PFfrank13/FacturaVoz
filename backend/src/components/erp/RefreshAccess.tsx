"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { coalescedRefresh, retailRefreshTables } from "@/lib/retail/cloud-refresh";

export default function RefreshAccess({ org }: { org: string }) {
  const router = useRouter();
  const [offline, setOffline] = useState(false);
  useEffect(() => {
    const db = createClient();
    const refresh = coalescedRefresh(() => router.refresh(), () => navigator.onLine && document.visibilityState === "visible");
    const connection = () => { setOffline(!navigator.onLine); refresh.request(); };
    connection();
    // Separate channels: an unpublished table cannot disable the other listeners.
    // User session + RLS authorize reads; org filters alone are not authorization.
    const channels = retailRefreshTables.map(table => db.channel(`erp-${org}-${table}`)
      .on("postgres_changes", { event: "*", schema: "public", table, filter: `org_id=eq.${org}` }, refresh.request)
      .subscribe(status => { if (status === "SUBSCRIBED") refresh.request(); }));
    const timer = window.setInterval(refresh.request, 30_000);
    window.addEventListener("focus", refresh.request);
    window.addEventListener("online", connection);
    window.addEventListener("offline", connection);
    document.addEventListener("visibilitychange", refresh.request);
    return () => {
      refresh.stop(); clearInterval(timer);
      window.removeEventListener("focus", refresh.request);
      window.removeEventListener("online", connection);
      window.removeEventListener("offline", connection);
      document.removeEventListener("visibilitychange", refresh.request);
      channels.forEach(channel => { void db.removeChannel(channel); });
    };
  }, [org, router]);
  return <div><button className="fv-button secondary" disabled={offline} onClick={() => router.refresh()}>Actualizar</button>{offline && <p role="status">Sin conexión de red. Los datos pueden estar desactualizados; las ventas necesitan confirmación del servidor.</p>}</div>;
}
