"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { safeNext } from "@/lib/safe-next";

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
  return <main className="fv-welcome fv-login">
    <section><p className="fv-eyebrow">FACTURAVOZ / TU ESPACIO DE TRABAJO</p><h1>Menos pasos.<br /><span>Más negocio.</span></h1><p>Las personas, los productos y el trabajo de cada día. Con la misma empresa y los mismos permisos que en tu móvil.</p><p className="fv-caption">FacturaVoz · Solvex Software Labs</p></section>
    <section className="fv-login-panel" aria-labelledby="login-title"><p className="fv-eyebrow">BIENVENIDO DE NUEVO</p><h2 id="login-title">Entra a tu empresa</h2><p>Usa el correo de tu cuenta de FacturaVoz.</p>
      <form className="fv-form" onSubmit={e => { e.preventDefault(); void send(); }}><label>Correo electrónico<input type="email" autoComplete="email" required maxLength={200} value={email} onChange={e => { setEmail(e.target.value); setSent(false); setCode(""); }} placeholder="tu@empresa.com" /></label><button className="fv-button" disabled={pending}>{pending ? "Un momento…" : sent ? "Reenviar acceso" : "Recibir acceso seguro"}</button></form>
      {sent && <form className="fv-form" onSubmit={e => { e.preventDefault(); void verify(); }}><label>Código de acceso<input inputMode="numeric" autoComplete="one-time-code" required minLength={6} maxLength={12} pattern="[0-9]+" value={code} onChange={e => setCode(e.target.value)} /></label><button className="fv-button secondary" disabled={pending}>Verificar código</button></form>}
      {msg && <p role="status" aria-live="polite">{msg}</p>}
      <p className="fv-caption">Tu administrador gestiona el acceso a la empresa. Nunca compartas tu código de acceso.</p>
    </section>
  </main>;
}
