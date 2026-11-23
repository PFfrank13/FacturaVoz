"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { safeNext } from "@/lib/safe-next";
import "../erp/erp.css";

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [msg, setMsg] = useState("");
  const [pending, setPending] = useState(false);
  const next = () => safeNext(new URLSearchParams(location.search).get("next"));
  async function send() {
    if (pending) return;
    setPending(true); setMsg("");
    try {
      const { error } = await createClient().auth.signInWithOtp({ email: email.trim(), options: { emailRedirectTo: `${location.origin}/auth/callback${next() ? `?next=${encodeURIComponent(next()!)}` : ""}`, shouldCreateUser: false } });
      if (error) { setMsg("No se pudo enviar el acceso. Comprueba el correo o consulta con tu administrador."); return; }
      setSent(true); setMsg("Revisa tu correo. Abre el enlace en este navegador o introduce el código recibido.");
    } catch { setMsg("No pudimos conectar. Comprueba tu conexión y vuelve a intentarlo."); }
    finally { setPending(false); }
  }
  async function verify() {
    if (pending) return;
    setPending(true); setMsg("");
    try {
      const { error } = await createClient().auth.verifyOtp({ email: email.trim(), token: code.trim(), type: "email" });
      if (error) { setMsg("El código es incorrecto o ha caducado. Solicita uno nuevo."); return; }
      router.replace(next() ?? "/"); router.refresh();
    } catch { setMsg("No pudimos verificar el código. Inténtalo de nuevo."); }
    finally { setPending(false); }
  }
  const step = sent ? 2 : 1;
  return <main className="fv-workspace fv-door">
    <section className="fv-door-copy">
      <p className="fv-door-brand">Factura <span>Voz</span></p>
      <h1>Tu tienda, también desde la computadora.</h1>
      <p>Comprobantes, caja, compras, clientes e inventario: lo mismo que llevas en el móvil, con la misma cuenta y los mismos permisos.</p>
      <a className="fv-button secondary" href="/app">Abrir el punto de venta</a>
    </section>
    <section className="fv-door-panel" aria-labelledby="login-title">
      <h2 id="login-title">Entra a tu empresa</h2>
      <ol className="fv-door-steps" aria-label="Pasos para entrar">
        <li aria-current={step === 1 ? "step" : undefined} className={step > 1 ? "is-done" : ""}>Recibe un código en tu correo</li>
        <li aria-current={step === 2 ? "step" : undefined}>Escríbelo aquí</li>
      </ol>
      <form className="fv-form" onSubmit={e => { e.preventDefault(); void send(); }}>
        <label>Correo de tu cuenta<input type="email" autoComplete="email" required maxLength={200} value={email} onChange={e => { setEmail(e.target.value); setSent(false); setCode(""); }} placeholder="tu@empresa.com" /></label>
        <button className={sent ? "fv-button secondary" : "fv-button"} disabled={pending}>{pending && !sent ? "Enviando…" : sent ? "Reenviar código" : "Recibir código"}</button>
      </form>
      {sent && <form className="fv-form fv-door-code" onSubmit={e => { e.preventDefault(); void verify(); }}>
        <label>Código de acceso<input inputMode="numeric" autoComplete="one-time-code" autoFocus required minLength={6} maxLength={12} pattern="[0-9]+" value={code} onChange={e => setCode(e.target.value.replace(/\D/g, ""))} placeholder="000000" /></label>
        <button className="fv-button" disabled={pending}>{pending ? "Verificando…" : "Entrar"}</button>
      </form>}
      {msg && <p className="fv-door-msg" role="status">{msg}</p>}
      <p className="fv-caption">El dueño de la empresa decide quién entra. Nunca compartas tu código.</p>
    </section>
  </main>;
}
