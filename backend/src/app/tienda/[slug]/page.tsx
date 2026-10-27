import type { Metadata } from "next";
import StoreCart from "@/components/public/StoreCart";
import { NotFoundCard } from "@/components/public/Shell";
import { getPublicStore } from "@/lib/publicdata";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const s = await getPublicStore(slug).catch(() => null);
  return { title: s ? `${s.business} · Pedidos en línea` : "Tienda", description: s?.headline || "Haz tu pedido en línea" };
}

export default async function StorePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const store = await getPublicStore(slug).catch(() => null);
  if (!store) return <NotFoundCard text="Esta tienda no existe o está cerrada por ahora." />;
  return <StoreCart store={store} />;
}
