"use client";
import type React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

/** Stroke icons (24 px grid) for each workspace section: recognizable at a glance, same weight everywhere. */
const icons: Record<string, string> = {
  inicio: "M3 11.5 12 4l9 7.5M5.5 10v9.5h13V10M10 19.5v-5h4v5",
  vender: "M4 5v14M7 5v14M10 5v14M13.5 5v14M16 5v14M20 5v14",
  fiados: "M5 4h11a2 2 0 0 1 2 2v14H7a2 2 0 0 1-2-2zM5 18a2 2 0 0 1 2-2h11M9 8h5M9 11h5",
  avisos: "M6 9a6 6 0 1 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9M10 20a2 2 0 0 0 4 0",
  gastos: "M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6M9 16h3",
  alertas: "M12 3l9 16H3zM12 10v4M12 17v.01",
  bitacora: "M12 8v4l3 2M3.5 12a8.5 8.5 0 1 0 2.5-6M3 4v4h4",
  papelera: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6",
  cuaderno: "M4 7h3l2-3h6l2 3h3v12H4zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
  recurrentes: "M4 12a8 8 0 0 1 14-5.3L20 9M20 4v5h-5M20 12a8 8 0 0 1-14 5.3L4 15M4 20v-5h5",
  tienda: "M4 9l1.5-5h13L20 9M4 9h16v11H4zM4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0M10 20v-5h4v5",
  encuestas: "M12 3.5l2.6 5.3 5.9.8-4.3 4.1 1 5.8L12 16.8l-5.2 2.7 1-5.8L3.5 9.6l5.9-.8z",
  conciliacion: "M3 10l9-6 9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18",
  impuestos: "M6 3h12v18H6zM9 7h6M9 11h6M9 15h2M14 15h1",
  comisiones: "M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4",
  importar: "M12 3v12M7 10l5 5 5-5M4 17v3h16v-3",
  cobranza: "M12 3v18M16.5 7H10a2.5 2.5 0 0 0 0 5h4a2.5 2.5 0 0 1 0 5H7",
  credito: "M3.5 6h17v12h-17zM3.5 10h17M7 14.5h4M15 14.5h2",
  clientes360: "M12 21a9 9 0 1 1 9-9M12 12V3M12 12l6.4 6.4M15 21h6v-6",
  negocio: "M3 17l6-6 4 4 8-8M15 7h6v6",
  api: "M8 7l-5 5 5 5M16 7l5 5-5 5M13.5 4l-3 16",
  carta: "M6 3v8a2 2 0 0 0 4 0V3M8 11v10M16 3c-1.7 0-3 2-3 5s1.3 4 3 4v9",
  platos: "M12 20a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
  placas: "M3 8h18v8H3zM6.5 12h2M10.5 12h3M15.5 12h2",
  recordatorios: "M12 21a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM12 9v4l2.5 1.5M4 4 2 6M20 4l2 2",
  paquetes: "M3 9h18v4H3zM5 13v8h14v-8M12 9v12M12 9c-2-4-6-4-6-1.5S10 9 12 9zM12 9c2-4 6-4 6-1.5S14 9 12 9z",
  historial: "M6 3h9l3 3v15H6zM9 13h6M12 10v6",
  corte: "M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01M3 3l18 18",
  morosidad: "M2 9l10-5 10 5-10 5zM6 11v5c3 2.5 9 2.5 12 0v-5",
  margen_obra: "M2 20h20M5 20V9l7-5 7 5v11M9 20v-6h6v6",
  escanear: "M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3M7 12h10",
  pin: "M6 10V8a6 6 0 0 1 12 0v2M5 10h14v10H5zM9 15h.01M12 15h.01M15 15h.01",
  agente: "M12 3v3M7 8h10a3 3 0 0 1 3 3v5a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3v-5a3 3 0 0 1 3-3zM9.5 13v1M14.5 13v1M2 13h2M20 13h2",
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

/** Sections grouped the way a shopkeeper thinks about the day, each with its own color (same as the mobile menu). */
const groups: { title: string; color: string; ids: string[] }[] = [
  { title: "Vender", color: "#0e8c74", ids: ["vender", "carta", "platos", "comprobantes", "cotizaciones", "cuaderno", "recurrentes", "tienda"] },
  { title: "Mercadería", color: "#2f6fdc", ids: ["productos", "inventario", "compras", "sucursales"] },
  { title: "Caja y cobros", color: "#c77417", ids: ["caja", "fiados", "cobranza", "cobros", "corte", "morosidad", "avisos", "credito", "conciliacion", "gastos", "escanear"] },
  { title: "Clientes y promociones", color: "#c2407e", ids: ["clientes", "clientes360", "promociones", "puntos", "encuestas"] },
  { title: "Servicios", color: "#0b8aa8", ids: ["trabajos", "agenda", "placas", "recordatorios", "paquetes", "historial", "margen_obra"] },
  { title: "Mi negocio", color: "#6a5ae0", ids: ["negocio", "reportes", "impuestos", "comisiones", "agente", "importar"] },
  { title: "Control del dueño", color: "#8a4b2f", ids: ["alertas", "bitacora", "pin", "papelera"] },
  { title: "Configuración", color: "#4f6480", ids: ["equipo", "plan", "configuracion", "api"] },
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
      return ls.length ? <div key={g.title} className="fv-rail-group" role="group" aria-label={g.title} style={{ "--g": g.color } as React.CSSProperties}>
        <p className="fv-rail-title"><i aria-hidden="true" />{g.title}</p>{ls.map(item)}</div> : null;
    })}
    {rest.filter(l => !known.has(l.id)).map(item)}
  </nav>;
}
