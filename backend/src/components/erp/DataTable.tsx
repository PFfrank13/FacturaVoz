"use client";
import { useState } from "react";
export default function DataTable({ rows, fields }: { rows: Record<string, unknown>[]; fields: readonly (readonly [string, string])[] }) {
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const identity = (row: Record<string, unknown>, i: number) => String(row.id ?? row.user_id ?? i);
  const selected = rows.find((row, i) => identity(row, i) === selectedId);
  const [sort, setSort] = useState<{ key: string; ascending: boolean } | null>(null);
  const text = (value: unknown) => value == null ? "—" : value === true ? "Sí" : value === false ? "No" : String(value);
  const visible = rows.filter(row => fields.some(([key]) => text(row[key]).toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))));
  if (sort) visible.sort((a, b) => (typeof a[sort.key] === "number" && typeof b[sort.key] === "number" ? Number(a[sort.key]) - Number(b[sort.key]) : text(a[sort.key]).localeCompare(text(b[sort.key]), "es", { numeric: true })) * (sort.ascending ? 1 : -1));
  return <section className="fv-data">
    <label className="fv-search">Buscar en esta página<input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Escribe para filtrar…" /></label>
    <p className="fv-caption" aria-live="polite">{visible.length} registros en esta página</p>
    <div className="fv-table-scroll" tabIndex={0} role="region" aria-label="Tabla de registros"><table><thead><tr>{fields.map(([key, label]) => <th key={key} scope="col" aria-sort={sort?.key === key ? sort.ascending ? "ascending" : "descending" : "none"}><button onClick={() => setSort({ key, ascending: sort?.key === key ? !sort.ascending : true })}>{label} <span aria-hidden="true">↕</span></button></th>)}<th scope="col">Detalle</th></tr></thead><tbody>{visible.map(row => <tr key={identity(row, rows.indexOf(row))}>{fields.map(([key]) => <td key={key}>{text(row[key])}</td>)}<td><button className="fv-button secondary" aria-expanded={selectedId === identity(row, rows.indexOf(row))} onClick={() => setSelectedId(identity(row, rows.indexOf(row)))}>Ver detalle</button></td></tr>)}</tbody></table></div>
    {selected && <section className="sr-record-detail" aria-label="Detalle del registro">
      <div className="sr-record-heading"><h2>Detalle del registro</h2><button className="fv-button secondary" onClick={() => setSelectedId(null)}>Cerrar detalle</button></div>
      <dl>{fields.map(([key, label]) => <div key={key}><dt>{label}</dt><dd>{text(selected[key])}</dd></div>)}</dl>
      <p className="fv-caption">Datos de la consulta actual. Usa Actualizar para recuperar los últimos cambios del servidor.</p>
    </section>}
    {!visible.length && <div className="fv-empty"><h2>{query ? "Sin coincidencias" : "Todavía no hay registros"}</h2><p>{query ? "Prueba con otro término de búsqueda." : "Los registros de tu empresa aparecerán aquí, también los creados desde el móvil."}</p></div>}
  </section>;
}
