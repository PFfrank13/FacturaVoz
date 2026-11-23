import Link from "next/link";
import { notFound } from "next/navigation";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed } from "@/lib/erp/access";
import { withTax } from "@/lib/erp/pricing";
import "./labels.css";

export const dynamic = "force-dynamic";

/**
 * Shelf labels (docs/INVESTIGACION_RETAIL.md, row 21): name, price to the public (with IGV) and barcode digits,
 * 3 columns on A4. Filter by category with ?cat=. Printing hides the ERP shell.
 */
export default async function ShelfLabels({ params, searchParams }: { params: Promise<{ org: string }>; searchParams: Promise<{ cat?: string }> }) {
  const { org } = await params;
  const cat = (await searchParams).cat ?? "";
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "productos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) notFound();
  let q = c.db.from("products").select("id,name,unit_price,unit,category,barcode").eq("org_id", org).eq("active", true).neq("unit", "ZZ").order("category").order("name").limit(600);
  if (cat) q = q.eq("category", cat);
  const [{ data }, cats] = await Promise.all([q, c.db.from("products").select("category").eq("org_id", org).eq("active", true).not("category", "is", null).limit(2000)]);
  const rate = Number(c.organization.default_tax_rate ?? 18);
  const cur = c.organization.currency || "PEN";
  const fmt = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency: cur }).format(v);
  const categories = [...new Set(((cats.data ?? []) as { category: string }[]).map(r => r.category))].sort((a, b) => a.localeCompare(b, "es"));
  const rows = (data ?? []) as { id: string; name: string; unit_price: number | string; unit: string; category: string | null; barcode: string | null }[];
  return <>
    <section className="fv-heading no-print"><p className="fv-eyebrow">PRODUCTOS / {c.organization.name}</p><h1>Etiquetas de góndola</h1>
      <p>Precio de venta al público con IGV. Elige la categoría y pulsa Imprimir (A4, 3 columnas).</p></section>
    <form className="fv-create fv-fiado-form no-print">
      <label><span>Categoría</span><select name="cat" defaultValue={cat}><option value="">Todas</option>{categories.map(x => <option key={x} value={x}>{x}</option>)}</select></label>
      <button className="fv-button secondary">Ver</button>
      <Link className="fv-button secondary" href={`/erp/${org}/productos`}>Volver</Link>
      <span className="fv-muted">{rows.length} {rows.length === 1 ? "etiqueta" : "etiquetas"} · usa Ctrl + P para imprimir</span>
    </form>
    <div className="fv-labels">{rows.map(p => <article key={p.id} className="fv-label">
      <small>{p.category ?? c.organization.name}</small>
      <strong>{p.name}</strong>
      <b>{fmt(withTax(Number(p.unit_price), rate))}{p.unit === "KGM" ? <i> el kilo</i> : null}</b>
      {p.barcode && <code>{p.barcode}</code>}
    </article>)}</div>
  </>;
}
