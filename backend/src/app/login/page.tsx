"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const [msg, setMsg] = useState("");

  async function send() {
    setMsg("");
    const { error } = await createClient().auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${location.origin}/auth/callback` },
    });
    if (error) return setMsg("No se pudo enviar el correo. Espera un minuto e inténtalo de nuevo.");
    setSent(true);
    setMsg("Revisa tu correo. Abre el enlace en ESTE mismo navegador, o escribe aquí el código si el correo lo trae.");
  }

  async function verify() {
    setMsg("");
    const { error } = await createClient().auth.verifyOtp({ email, token: code.trim(), type: "email" });
    if (error) return setMsg("Código incorrecto o caducado");
    router.replace("/");
    router.refresh();
  }

  return (
    <main className="mx-auto flex max-w-sm flex-col gap-3 p-6 pt-24">
      <h1 className="text-2xl font-bold">Entrar a FacturaVoz</h1>
      <input type="email" className="rounded border p-2" placeholder="tu@correo.com"
        value={email} onChange={(e) => setEmail(e.target.value)} />
      <button className="rounded bg-blue-600 p-2 text-white" onClick={send}>
        {sent ? "Reenviar correo" : "Enviar correo de acceso"}
      </button>
      {sent && (
        <>
          <input inputMode="numeric" className="rounded border p-2 text-center tracking-widest"
            placeholder="Código (si lo recibiste)" value={code} onChange={(e) => setCode(e.target.value)} />
          <button className="rounded border p-2" onClick={verify}>Entrar con código</button>
        </>
      )}
      {msg && <p className="text-sm">{msg}</p>}
    </main>
  );
}