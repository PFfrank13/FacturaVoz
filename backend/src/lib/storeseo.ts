import type { PublicStore, StoreProduct } from "./publicdata";

/** Datos estructurados (schema.org) para que Google muestre el negocio y los productos con precio. */
const safe = (o: unknown) => JSON.stringify(o).replace(/</g, "\\u003c");
const base = () => (process.env.NEXT_PUBLIC_SITE_URL ?? process.env.APP_URL ?? "").replace(/\/$/, "");

export function storeJsonLd(s: PublicStore): string {
  return safe({
    "@context": "https://schema.org",
    "@type": s.mode === "carta" ? "Restaurant" : "Store",
    name: s.business,
    description: s.headline || s.about || undefined,
    image: s.logo ?? undefined,
    url: `${base()}/tienda/${s.slug}`,
    hasOfferCatalog: {
      "@type": "OfferCatalog",
      name: s.mode === "carta" ? "Carta" : "Catálogo",
      itemListElement: s.products.slice(0, 50).map((p) => ({
        "@type": "Offer",
        price: p.priceWithTax.toFixed(2),
        priceCurrency: s.currency,
        itemOffered: { "@type": p.service ? "Service" : "Product", name: p.name },
      })),
    },
  });
}

export function productJsonLd(s: PublicStore, p: StoreProduct): string {
  return safe({
    "@context": "https://schema.org",
    "@type": "Product",
    name: p.name,
    description: p.description || undefined,
    image: p.image ?? undefined,
    brand: { "@type": "Brand", name: s.business },
    offers: {
      "@type": "Offer",
      price: p.priceWithTax.toFixed(2),
      priceCurrency: s.currency,
      availability: p.stock == null || p.stock > 0 ? "https://schema.org/InStock" : "https://schema.org/OutOfStock",
      url: `${base()}/tienda/${s.slug}/p/${p.id}`,
    },
  });
}
