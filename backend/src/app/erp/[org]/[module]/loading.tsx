/** Shown instantly inside the workspace while a module loads, so a click always answers at once. */
export default function ModuleLoading() {
  return <section className="fv-module-loading" role="status" aria-label="Cargando">
    <div className="fv-skeleton"><i /><i /></div>
    <div className="fv-module-loading-cards"><span /><span /><span /></div>
    <div className="fv-skeleton"><i /><i /><i /><i /></div>
  </section>;
}
