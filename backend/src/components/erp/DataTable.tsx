"use client";
import { useState } from "react";
export default function DataTable({ rows, fields }: { rows: Record<string, unknown>[]; fields: readonly (readonly [string, string])[] }) {
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<{ key: string; ascending: boolean } | null>(null);
  const text = (value: unknown) => value == null ? "—" : value === true ? "Sí" : value === false ? "No" : String(value);
  // Dates and statuses in the owner's words instead of raw database values.
  const statusLabel: Record<string, string> = { draft: "Borrador", sent: "Enviada", accepted: "Aceptada", rejected: "Rechazada", expired: "Vencida", issued: "Emitida", paid: "Pagada",
    pendiente: "Pendiente", programado: "Programado", en_curso: "En curso", terminado: "Terminado", cancelado: "Cancelado", completado: "Completado", cita: "Cita", visita: "Visita" };
  const tone: Record<string, string> = { accepted: "is-ok", paid: "is-ok", terminado: "is-ok", completado: "is-ok", rejected: "is-bad", cancelado: "is-off", expired: "is-off", draft: "is-off" };
  const pretty = (key: string, value: unknown): React.ReactNode => {
    if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}(T|$)/.test(value)) {
      const d = new Date(value.length === 10 ? `${value}T12:00:00Z` : value);
      return new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "short", year: "numeric", ...(value.length > 10 ? { hour: "2-digit", minute: "2-digit" } : {}), timeZone: value.length === 10 ? "UTC" : "America/Lima" }).format(d);
    }
    if ((key === "status" || key === "kind") && typeof value === "string") return <span className={`fv-pill ${tone[value] ?? "is-wait"}`}>{statusLabel[value] ?? value.replace(/_/g, " ")}</span>;
    return text(value);
  };
  const visible = rows.filter(row => fields.some(([key]) => text(row[key]).toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))));
  if (sort) visible.sort((a, b) => (typeof a[sort.key] === "number" && typeof b[sort.key] === "number" ? Number(a[sort.key]) - Number(b[sort.key]) : text(a[sort.key]).localeCompare(text(b[sort.key]), "es", { numeric: true })) * (sort.ascending ? 1 : -1));
  return <section className="fv-data">
    <label className="fv-search">Buscar en esta página<input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Escribe para filtrar…" /></label>
    <p className="fv-caption" aria-live="polite">{visible.length} registros en esta página</p>
    <div className="fv-table-scroll" tabIndex={0} role="region" aria-label="Tabla de registros"><table><thead><tr>{fields.map(([key, label]) => <th key={key} scope="col" aria-sort={sort?.key === key ? sort.ascending ? "ascending" : "descending" : "none"}><button onClick={() => setSort({ key, ascending: sort?.key === key ? !sort.ascending : true })}>{label} <span aria-hidden="true">↕</span></button></th>)}</tr></thead><tbody>{visible.map((row, i) => <tr key={String(row.id ?? row.user_id ?? i)}>{fields.map(([key]) => <td key={key}>{pretty(key, row[key])}</td>)}</tr>)}</tbody></table></div>
    {!visible.length && <div className="fv-empty"><h2>{query ? "Sin coincidencias" : "Todavía no hay registros"}</h2><p>{query ? "Prueba con otro término de búsqueda." : "Los registros de tu empresa aparecerán aquí, también los creados desde el móvil."}</p></div>}
  </section>;
}
