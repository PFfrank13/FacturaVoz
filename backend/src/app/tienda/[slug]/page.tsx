import type { Metadata } from "next";
import StoreCart from "@/components/public/StoreCart";
import { NotFoundCard } from "@/components/public/Shell";
import { getPublicStore } from "@/lib/publicdata";
import { storeJsonLd } from "@/lib/storeseo";

// ISR: la página se arma en el servidor y se renueva cada 2 minutos (rápida en celulares y buena para Google).
export const revalidate = 120;

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const s = await getPublicStore(slug).catch(() => null);
  return {
    title: s ? `${s.business} · ${s.mode === "carta" ? "Carta digital" : "Pedidos en línea"}` : "Tienda",
    description: s?.headline || "Haz tu pedido en línea",
    openGraph: s ? { title: s.business, description: s.headline || "Haz tu pedido en línea", images: s.logo ? [s.logo] : undefined, type: "website" } : undefined,
    alternates: { canonical: `/tienda/${slug}` },
    manifest: `/tienda/${slug}/manifest.webmanifest`,
    robots: s ? { index: true, follow: true } : { index: false },
  };
}

/** /tienda/<slug> · con ?mesa=4 funciona como carta digital de restaurante (la mesa se lee en el navegador). */
export default async function StorePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const store = await getPublicStore(slug).catch(() => null);
  if (!store) return <NotFoundCard text="Esta tienda no existe o está cerrada por ahora." />;
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: storeJsonLd(store) }} />
      <StoreCart store={store} />
    </>
  );
}
