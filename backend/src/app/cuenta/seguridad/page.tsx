"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import "../../erp/erp.css";

type Factor = { id: string; status: string; friendly_name?: string; created_at: string };

/** Two-step verification (TOTP) for the web: turn it on with an authenticator app, or off with a current code. */
export default function Security() {
  const [email, setEmail] = useState<string | null>(null);
  const [factor, setFactor] = useState<Factor | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [enroll, setEnroll] = useState<{ id: string; qr: string; secret: string } | null>(null);
  const [code, setCode] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, setPending] = useState(false);

  const load = useCallback(async () => {
    const db = createClient();
    const [{ data: u }, { data: f }] = await Promise.all([db.auth.getUser(), db.auth.mfa.listFactors()]);
    setEmail(u.user?.email ?? null);
    setFactor((f?.totp?.[0] as Factor | undefined) ?? null);
    setLoaded(true);
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function start() {
    if (pending) return;
    setPending(true); setMsg(null);
    try {
      const db = createClient();
      // A half-finished attempt blocks a new one: clean it first.
      const all = await db.auth.mfa.listFactors();
      for (const f of all.data?.all ?? []) if (f.status !== "verified") await db.auth.mfa.unenroll({ factorId: f.id });
      const { data, error } = await db.auth.mfa.enroll({ factorType: "totp", friendlyName: `FacturaVoz ${new Date().toLocaleDateString("es-PE")}` });
      if (error || !data) { setMsg({ ok: false, text: "No se pudo empezar. Actualiza la página e inténtalo otra vez." }); return; }
      setEnroll({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
      setCode("");
    } finally { setPending(false); }
  }

  async function confirm() {
    if (pending || !enroll) return;
    setPending(true); setMsg(null);
    try {
      const { error } = await createClient().auth.mfa.challengeAndVerify({ factorId: enroll.id, code });
      if (error) { setCode(""); setMsg({ ok: false, text: "Código incorrecto. Escribe el código que muestra ahora tu app." }); return; }
      setEnroll(null); setCode("");
      setMsg({ ok: true, text: "Listo: la verificación en dos pasos está activa. Desde ahora la web te pedirá el código después de la contraseña." });
      await load();
    } finally { setPending(false); }
  }

  async function turnOff() {
    if (pending || !factor) return;
    setPending(true); setMsg(null);
    try {
      const db = createClient();
      // Quitarla exige un código actual: quien solo tenga la contraseña no puede desactivarla.
      const v = await db.auth.mfa.challengeAndVerify({ factorId: factor.id, code });
      if (v.error) { setCode(""); setMsg({ ok: false, text: "Código incorrecto. Para quitar la verificación escribe el código actual de tu app." }); return; }
      const { error } = await db.auth.mfa.unenroll({ factorId: factor.id });
      if (error) { setMsg({ ok: false, text: "No se pudo quitar. Inténtalo otra vez." }); return; }
      setCode("");
      setMsg({ ok: true, text: "Verificación en dos pasos desactivada. Solo se pedirá tu contraseña." });
      await load();
    } finally { setPending(false); }
  }

  const codeInput = <label>Código de 6 dígitos<input inputMode="numeric" autoComplete="one-time-code" required minLength={6} maxLength={6} pattern="[0-9]{6}" value={code} onChange={e => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))} placeholder="000000" /></label>;

  return <main className="fv-workspace fv-door">
    <section className="fv-door-copy">
      <p className="fv-door-brand">Factura <span>Voz</span></p>
      <h1>Verificación en dos pasos.</h1>
      <p>Además de tu contraseña, la web te pedirá un código que cambia cada 30 segundos en tu celular. Aunque alguien sepa tu contraseña, sin tu celular no entra.</p>
      <Link className="fv-button secondary" href="/">Volver a mi empresa</Link>
    </section>
    <section className="fv-door-panel" aria-labelledby="sec-title">
      <h2 id="sec-title">{factor ? "Está activa" : "Actívala en 1 minuto"}</h2>
      {email && <p className="fv-caption">Cuenta: <b>{email}</b></p>}
      {!loaded ? <div className="fv-skeleton" aria-label="Cargando"><i /><i /></div>
        : factor ? <form className="fv-form fv-door-code" onSubmit={e => { e.preventDefault(); void turnOff(); }}>
          <p className="fv-door-msg">Activa desde el {new Date(factor.created_at).toLocaleDateString("es-PE")}. Al entrar a la web se pide el código de tu app.</p>
          {codeInput}
          <button className="fv-button secondary" disabled={pending || code.length !== 6}>{pending ? "Comprobando…" : "Quitar la verificación"}</button>
        </form>
        : enroll ? <form className="fv-form fv-door-code" onSubmit={e => { e.preventDefault(); void confirm(); }}>
          <ol className="fv-door-steps">
            <li>Instala Google Authenticator o Microsoft Authenticator en tu celular.</li>
            <li>En la app toca «+» y escanea este código.</li>
            <li>Escribe aquí el código de 6 dígitos que aparece.</li>
          </ol>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="fv-qr" src={enroll.qr} alt="Código QR para tu app de verificación" width={200} height={200} />
          <p className="fv-caption">¿No puedes escanear? Escribe esta clave en la app: <code className="fv-secret">{enroll.secret}</code></p>
          {codeInput}
          <button className="fv-button" disabled={pending || code.length !== 6}>{pending ? "Comprobando…" : "Activar"}</button>
          <button type="button" className="fv-link fv-door-forgot" onClick={() => { setEnroll(null); setCode(""); }}>Cancelar</button>
        </form>
        : <button className="fv-button" onClick={() => void start()} disabled={pending}>{pending ? "Preparando…" : "Activar verificación en dos pasos"}</button>}
      {msg && <p className={msg.ok ? "fv-door-msg" : "fv-door-msg is-bad"} role={msg.ok ? "status" : "alert"}>{msg.text}</p>}
      <p className="fv-caption">Es por persona: cada miembro del equipo la activa en su cuenta. La app del celular sigue protegida con tu PIN.</p>
    </section>
  </main>;
}
