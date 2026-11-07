"use client";
import Brand from "@/components/retail/Brand";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [msg, setMsg] = useState("");
  const [pending, setPending] = useState(false);
  async function send() {
    if (pending) return;
    setPending(true); setMsg("");
    try {
      const { error } = await createClient().auth.signInWithOtp({ email: email.trim(), options: { emailRedirectTo: `${location.origin}/auth/callback`, shouldCreateUser: false } });
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
      router.replace("/"); router.refresh();
    } catch { setMsg("No pudimos verificar el código. Inténtalo de nuevo."); }
    finally { setPending(false); }
  }
  return <main className="fv-welcome fv-login">
    <section className="sr-login-story"><Brand /><p className="fv-eyebrow">EL CONTROL EMPIEZA AQUÍ</p><h1>Una tienda.<br /><span>Mil cosas menos<br />en la cabeza.</span></h1><p>Organiza el catálogo, consulta tus ventas y encuentra el siguiente paso de tu jornada.</p>
      <div className="sr-principles"><span>01 / Productos claros</span><span>02 / Operaciones trazables</span><span>03 / Acceso por permisos</span></div>
      <p className="fv-caption">Solvex Software Labs</p></section>
    <section className="fv-login-panel" aria-labelledby="login-title"><p className="fv-eyebrow">FACTURAVOZ</p><h2 id="login-title">Tu negocio te espera</h2><p>Entra con el correo de tu cuenta. Conservas tu empresa y tus permisos.</p>
      <form className="fv-form" onSubmit={e => { e.preventDefault(); void send(); }}><label>Correo electrónico<input type="email" autoComplete="email" required maxLength={200} value={email} onChange={e => { setEmail(e.target.value); setSent(false); setCode(""); }} placeholder="tu@empresa.com" /></label><button className="fv-button" disabled={pending}>{pending ? "Un momento…" : sent ? "Reenviar acceso" : "Recibir acceso seguro"}</button></form>
      {sent && <form className="fv-form" onSubmit={e => { e.preventDefault(); void verify(); }}><label>Código de acceso<input inputMode="numeric" autoComplete="one-time-code" required minLength={6} maxLength={12} pattern="[0-9]+" value={code} onChange={e => setCode(e.target.value)} /></label><button className="fv-button secondary" disabled={pending}>Verificar código</button></form>}
      {msg && <p role="status" aria-live="polite">{msg}</p>}
      <p className="fv-caption">Tu administrador gestiona el acceso a la empresa. Nunca compartas tu código de acceso.</p>
    </section>
  </main>;
}
