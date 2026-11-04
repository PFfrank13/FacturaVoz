"use client";
export default function WorkspaceError({ reset }: { reset: () => void }) { return <section className="fv-empty" role="alert"><h1>No pudimos verificar tu acceso</h1><p>Comprueba tu conexión y vuelve a intentarlo.</p><button className="fv-button" onClick={reset}>Reintentar</button></section>; }
