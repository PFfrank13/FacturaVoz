import type { Metadata } from "next";
import StoreCart from "@/components/public/StoreCart";
import { NotFoundCard } from "@/components/public/Shell";
import { getPublicStore } from "@/lib/publicdata";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const s = await getPublicStore(slug).catch(() => null);
  return {
    title: s ? `${s.business} · ${s.mode === "carta" ? "Carta digital" : "Pedidos en línea"}` : "Tienda",
    description: s?.headline || "Haz tu pedido en línea",
    openGraph: s ? { title: s.business, description: s.headline || "Haz tu pedido en línea", images: s.logo ? [s.logo] : undefined } : undefined,
  };
}

/** /tienda/<slug> · con ?mesa=4 funciona como carta digital de restaurante (el pedido llega a comandas). */
export default async function StorePage({ params, searchParams }: { params: Promise<{ slug: string }>; searchParams: Promise<{ mesa?: string }> }) {
  const { slug } = await params;
  const sp = await searchParams;
  const store = await getPublicStore(slug).catch(() => null);
  if (!store) return <NotFoundCard text="Esta tienda no existe o está cerrada por ahora." />;
  const table = typeof sp.mesa === "string" && /^[0-9A-Za-z \-]{1,12}$/.test(sp.mesa) ? sp.mesa : "";
  return <StoreCart store={store} table={table} />;
}
