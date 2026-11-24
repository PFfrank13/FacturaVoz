"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { safeNext } from "@/lib/safe-next";
import "../erp/erp.css";

/** Web access: email and password only (no codes). Forgotten password → link by email to set a new one. */
export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, setPending] = useState(false);
  const next = () => safeNext(new URLSearchParams(location.search).get("next"));

  async function signIn() {
    if (pending) return;
    setPending(true); setMsg(null);
    try {
      const { error } = await createClient().auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
      if (error) {
        setMsg({ ok: false, text: /invalid|credentials/i.test(error.message)
          ? "Correo o contraseña incorrectos. Si nunca creaste una contraseña, usa «¿Olvidaste tu contraseña?»."
          : /rate|too many/i.test(error.message) ? "Demasiados intentos. Espera unos minutos y vuelve a probar."
          : "No se pudo entrar. Inténtalo otra vez." });
        return;
      }
      router.replace(next() ?? "/"); router.refresh();
    } catch { setMsg({ ok: false, text: "No pudimos conectar. Comprueba tu conexión y vuelve a intentarlo." }); }
    finally { setPending(false); }
  }

  async function forgot() {
    if (pending) return;
    const mail = email.trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(mail)) { setMsg({ ok: false, text: "Escribe primero el correo de tu cuenta." }); return; }
    setPending(true); setMsg(null);
    try {
      const { error } = await createClient().auth.resetPasswordForEmail(mail, { redirectTo: `${location.origin}/auth/callback?next=${encodeURIComponent("/login/nueva")}` });
      // Same answer whether or not the account exists: nobody can probe which emails are registered.
      setMsg(error && /rate|too many/i.test(error.message)
        ? { ok: false, text: "Ya te enviamos un enlace hace poco. Espera un minuto y revisa tu correo (también spam)." }
        : { ok: true, text: `Si ${mail} tiene una cuenta, te llegó un enlace para crear tu contraseña. Ábrelo en este navegador.` });
    } catch { setMsg({ ok: false, text: "No pudimos conectar. Comprueba tu conexión y vuelve a intentarlo." }); }
    finally { setPending(false); }
  }

  return <main className="fv-workspace fv-door">
    <section className="fv-door-copy">
      <p className="fv-door-brand">Factura <span>Voz</span></p>
      <h1>Tu tienda, también desde la computadora.</h1>
      <p>Comprobantes, caja, compras, clientes e inventario: lo mismo que llevas en el móvil, con la misma cuenta y los mismos permisos.</p>
      <a className="fv-button secondary" href="/app">Abrir el punto de venta</a>
    </section>
    <section className="fv-door-panel" aria-labelledby="login-title">
      <h2 id="login-title">Entra a tu empresa</h2>
      <form className="fv-form" onSubmit={e => { e.preventDefault(); void signIn(); }}>
        <label>Correo<input type="email" autoComplete="email" required maxLength={200} value={email} onChange={e => setEmail(e.target.value)} placeholder="tu@empresa.com" /></label>
        <label>Contraseña
          <span className="fv-door-pass">
            <input type={show ? "text" : "password"} autoComplete="current-password" required minLength={6} maxLength={200} value={password} onChange={e => setPassword(e.target.value)} />
            <button type="button" className="fv-link" onClick={() => setShow(s => !s)} aria-pressed={show}>{show ? "Ocultar" : "Ver"}</button>
          </span>
        </label>
        <button className="fv-button" disabled={pending}>{pending ? "Entrando…" : "Entrar"}</button>
      </form>
      <button type="button" className="fv-link fv-door-forgot" onClick={() => void forgot()} disabled={pending}>¿Olvidaste tu contraseña o aún no tienes una?</button>
      {msg && <p className={msg.ok ? "fv-door-msg" : "fv-door-msg is-bad"} role={msg.ok ? "status" : "alert"}>{msg.text}</p>}
      <p className="fv-caption">Usa el mismo correo y contraseña de la app. El dueño de la empresa decide quién entra.</p>
    </section>
  </main>;
}
