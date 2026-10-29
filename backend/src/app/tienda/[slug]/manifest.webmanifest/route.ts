import { getPublicStore } from "@/lib/publicdata";

export const revalidate = 3600;

/** PWA: el cliente puede "Agregar a la pantalla de inicio" la tienda de este negocio. */
export async function GET(_req: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const s = await getPublicStore(slug).catch(() => null);
  if (!s) return new Response("No encontrado", { status: 404 });
  const body = {
    name: s.business,
    short_name: s.business.slice(0, 12),
    start_url: `/tienda/${s.slug}`,
    scope: `/tienda/${s.slug}`,
    display: "standalone",
    background_color: "#f8f6fd",
    theme_color: s.color,
    lang: "es-PE",
    icons: [{ src: "/favicon.ico", sizes: "48x48", type: "image/x-icon" }],
  };
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/manifest+json", "Cache-Control": "public, max-age=3600" } });
}
