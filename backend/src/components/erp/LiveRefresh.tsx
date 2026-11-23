"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

/**
 * Re-renders the page when rows of this company change in any client (mobile
 * included). Realtime only signals; data is re-read on the server with RLS.
 */
export default function LiveRefresh({ org, tables }: { org: string; tables: readonly string[] }) {
  const router = useRouter();
  const [pulse, setPulse] = useState(0);
  useEffect(() => {
    const db = createClient();
    let timer: number | undefined;
    const refresh = () => {
      window.clearTimeout(timer);
      // Coalesce bursts (a sale touches several rows) into one refresh.
      timer = window.setTimeout(() => { router.refresh(); setPulse(p => p + 1); }, 350);
    };
    const channel = db.channel(`erp-live-${org}-${tables.join("-")}`);
    for (const table of tables) {
      channel.on("postgres_changes", { event: "*", schema: "public", table, filter: `org_id=eq.${org}` }, refresh);
    }
    channel.subscribe();
    return () => { window.clearTimeout(timer); void db.removeChannel(channel); };
  }, [org, router, tables]);
  return <span className="fv-live" key={pulse} role="status" aria-live="polite">
    <i aria-hidden="true" /> En vivo{pulse > 0 ? " · actualizado" : ""}
  </span>;
}
