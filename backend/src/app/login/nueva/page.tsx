"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import "../../erp/erp.css";

/** Create or change the password after opening the link sent by email (the link already signed the user in). */
export default function NewPassword() {
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);
  const [checked, setChecked] = useState(false);
  const [a, setA] = useState("");
  const [b, setB] = useState("");
  const [msg, setMsg] = useState("");
  const [pending, setPending] = useState(false);

  useEffect(() => {
    createClient().auth.getUser().then(({ data }) => { setEmail(data.user?.email ?? null); setChecked(true); });
  }, []);

  async function save() {
    if (pending) return;
    if (a.length < 8) { setMsg("Usa al menos 8 caracteres."); return; }
    if (a !== b) { setMsg("Las contraseñas no coinciden."); return; }
    setPending(true); setMsg("");
    try {
      const { error } = await createClient().auth.updateUser({ password: a });
      if (error) {
        setMsg(/weak|pwned|leaked/i.test(error.message) ? "Esa contraseña es muy fácil o apareció en filtraciones. Elige otra."
          : /same|different/i.test(error.message) ? "Elige una contraseña distinta a la anterior."
          : "No se pudo guardar. Abre otra vez el enlace del correo.");
        return;
      }
      router.replace("/"); router.refresh();
    } catch { setMsg("No pudimos conectar. Inténtalo otra vez."); }
    finally { setPending(false); }
  }

  return <main className="fv-workspace fv-door">
    <section className="fv-door-copy">
      <p className="fv-door-brand">Factura <span>Voz</span></p>
      <h1>Crea tu contraseña.</h1>
      <p>Te servirá para entrar en la web y también en la app, con tu mismo correo.</p>
    </section>
    <section className="fv-door-panel" aria-labelledby="pass-title">
      <h2 id="pass-title">Nueva contraseña</h2>
      {!checked ? <div className="fv-skeleton" aria-label="Comprobando el enlace"><i /><i /></div>
        : !email ? <><p className="fv-door-msg is-bad" role="alert">El enlace caducó o ya se usó. Pide otro desde la pantalla de acceso.</p>
          <a className="fv-button" href="/login">Volver a entrar</a></>
        : <form className="fv-form" onSubmit={e => { e.preventDefault(); void save(); }}>
          <p className="fv-caption">Cuenta: <b>{email}</b></p>
          <label>Contraseña nueva<input type="password" autoComplete="new-password" required minLength={8} maxLength={200} value={a} onChange={e => setA(e.target.value)} /></label>
          <label>Repítela<input type="password" autoComplete="new-password" required minLength={8} maxLength={200} value={b} onChange={e => setB(e.target.value)} /></label>
          <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar y entrar"}</button>
        </form>}
      {msg && <p className="fv-door-msg is-bad" role="alert">{msg}</p>}
    </section>
  </main>;
}
