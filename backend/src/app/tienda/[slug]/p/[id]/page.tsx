import type { Metadata } from "next";
import StoreCart from "@/components/public/StoreCart";
import { NotFoundCard } from "@/components/public/Shell";
import { getPublicStore } from "@/lib/publicdata";
import { productJsonLd } from "@/lib/storeseo";

export const revalidate = 120;

type P = { params: Promise<{ slug: string; id: string }> };

/** Página de producto compartible (WhatsApp/Facebook muestran foto, nombre y precio). */
export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { slug, id } = await params;
  const s = await getPublicStore(slug).catch(() => null);
  const p = s?.products.find((x) => x.id === id);
  if (!s || !p) return { title: "Producto" };
  const price = `${s.currency === "USD" ? "US$" : "S/"} ${p.priceWithTax.toFixed(2)}`;
  return {
    title: `${p.name} · ${s.business}`,
    description: `${price} · ${p.description || s.headline || "Pídelo en línea"}`.slice(0, 200),
    openGraph: { title: `${p.name} · ${price}`, description: p.description || s.business, images: p.image ? [p.image] : s.logo ? [s.logo] : undefined },
  };
}

export default async function ProductPage({ params }: P) {
  const { slug, id } = await params;
  const store = await getPublicStore(slug).catch(() => null);
  if (!store) return <NotFoundCard text="Esta tienda no existe o está cerrada por ahora." />;
  const p = store.products.find((x) => x.id === id);
  return (
    <>
      {p ? <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: productJsonLd(store, p) }} /> : null}
      <StoreCart store={store} initialProduct={p ? id : null} />
    </>
  );
}
