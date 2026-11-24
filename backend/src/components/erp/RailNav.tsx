"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

/** Stroke icons (24 px grid) for each workspace section: recognizable at a glance, same weight everywhere. */
const icons: Record<string, string> = {
  inicio: "M3 11.5 12 4l9 7.5M5.5 10v9.5h13V10M10 19.5v-5h4v5",
  comprobantes: "M7 3h7l4 4v14H7zM14 3v4h4M9.5 12h6M9.5 15.5h6M9.5 8.5h2.5",
  caja: "M3.5 9h17v10.5h-17zM6 9V6.5h12V9M8 13.5h3M15.5 14.5a1 1 0 1 0 0-.01",
  cobros: "M4 7h16v11H4zM4 10.5h16M7.5 14.5h3",
  clientes: "M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20c.6-3.3 3.2-5.5 6.5-5.5s5.9 2.2 6.5 5.5M16 4.5a3.3 3.3 0 0 1 0 6.5M18.5 14.5c1.7.8 2.8 2.5 3 5.5",
  puntos: "M12 3.5l2.6 5.3 5.9.8-4.3 4.1 1 5.8L12 16.8l-5.2 2.7 1-5.8L3.5 9.6l5.9-.8z",
  promociones: "M3.5 12.5 11.5 4.5h8v8l-8 8zM15.5 8.5a.5.5 0 1 0 0-.01",
  inventario: "M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5zM3.5 7.5 12 12l8.5-4.5M12 12v9",
  productos: "M4 5h7v7H4zM13 5h7v7h-7zM4 14h7v6H4zM13 14h7v6h-7z",
  compras: "M3 5h11v10H3zM14 9h4l3 3v3h-7M7 18.5a1.5 1.5 0 1 0 0-.01M17 18.5a1.5 1.5 0 1 0 0-.01",
  sucursales: "M3.5 20.5h17M5 20.5V9l7-4.5L19 9v11.5M9.5 20.5v-6h5v6",
  trabajos: "M14.5 5.5a4 4 0 0 0-5 5L4 16l4 4 5.5-5.5a4 4 0 0 0 5-5l-2.5 2.5-2.5-.5-.5-2.5z",
  agenda: "M4 6h16v14H4zM4 10h16M8.5 3.5v4M15.5 3.5v4",
  cotizaciones: "M6 3h9l3 3v15H6zM9 9h6M9 12.5h6M9 16h3.5",
  reportes: "M4 20V10M10 20V4M16 20v-7M21.5 20.5h-19",
  equipo: "M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.5 21c.8-4 3.8-6.5 7.5-6.5s6.7 2.5 7.5 6.5",
  plan: "M12 3l7.5 3v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6zM9 12l2.2 2.2L15.5 10",
  configuracion: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 13.5l1.6 1.2-1.8 3.1-1.9-.6a7 7 0 0 1-2 1.1L15 20.5h-3.6l-.4-2.2a7 7 0 0 1-2-1.1l-1.9.6-1.8-3.1 1.6-1.2a7 7 0 0 1 0-2.3L5.3 10l1.8-3.1 1.9.6a7 7 0 0 1 2-1.1l.4-2.2H15l.4 2.2a7 7 0 0 1 2 1.1l1.9-.6 1.8 3.1-1.6 1.2a7 7 0 0 1 0 2.3z",
};

/** Sections grouped the way a shopkeeper thinks about the day. */
const groups: { title: string; ids: string[] }[] = [
  { title: "Vender y cobrar", ids: ["comprobantes", "caja", "cobros", "clientes", "puntos", "promociones", "cotizaciones"] },
  { title: "Mercadería", ids: ["inventario", "productos", "compras", "sucursales"] },
  { title: "Servicios", ids: ["trabajos", "agenda"] },
  { title: "Tu negocio", ids: ["reportes", "equipo", "plan", "configuracion"] },
];

export const RailIcon = ({ id }: { id: string }) => <svg className="fv-rail-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
  <path d={icons[id] ?? icons.productos} fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
</svg>;

/** Rail links with icons and groups, the current section marked for sighted and screen reader users. */
export default function RailNav({ links }: { links: readonly { id: string; href: string; label: string }[] }) {
  const path = usePathname();
  const isCurrent = (l: { id: string; href: string }) => l.id === "inicio" ? path === l.href : path === l.href || path.startsWith(`${l.href}/`);
  const item = (l: { id: string; href: string; label: string }) => <Link key={l.href} href={l.href} aria-current={isCurrent(l) ? "page" : undefined}>
    <RailIcon id={l.id} /><span>{l.label}</span>
  </Link>;
  const home = links.find(l => l.id === "inicio");
  const rest = links.filter(l => l.id !== "inicio");
  const known = new Set(groups.flatMap(g => g.ids));
  return <nav aria-label="Navegación de la empresa">
    {home && item(home)}
    {groups.map(g => {
      const ls = g.ids.map(id => rest.find(l => l.id === id)).filter((l): l is NonNullable<typeof l> => !!l);
      return ls.length ? <div key={g.title} className="fv-rail-group" role="group" aria-label={g.title}><p className="fv-rail-title">{g.title}</p>{ls.map(item)}</div> : null;
    })}
    {rest.filter(l => !known.has(l.id)).map(item)}
  </nav>;
}
