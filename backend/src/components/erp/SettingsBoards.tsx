"use client";
import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { cancelInvite, inviteMember, removeMember, saveBranding, saveBusiness, savePaySettings, setMemberRole, type FormResult } from "@/app/erp/actions";

const idle: FormResult = { ok: false, message: "" };
const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;

export type Business = { name: string; trade_name: string; tax_id: string; address: string; ubigeo: string; department: string; province: string; district: string; series_factura: string; series_boleta: string; currency: string; default_tax_rate: number };

/** «Datos del negocio»: the issuer data on every receipt. */
export function BusinessForm({ org, b }: { org: string; b: Business }) {
  const [state, action, pending] = useActionState(saveBusiness.bind(null, org), idle);
  return <form action={action} className="fv-create fv-form fv-settings-card">
    <h3>Datos del negocio</h3>
    <div className="fv-two"><label>Razón social<input name="name" defaultValue={b.name} maxLength={160} required /></label><label>Nombre comercial<input name="trade_name" defaultValue={b.trade_name} maxLength={160} /></label></div>
    <div className="fv-two"><label>RUC<input name="tax_id" inputMode="numeric" maxLength={11} defaultValue={b.tax_id} /></label><label>Dirección fiscal<input name="address" defaultValue={b.address} maxLength={250} /></label></div>
    <div className="fv-three"><label>Distrito<input name="district" defaultValue={b.district} maxLength={60} /></label><label>Provincia<input name="province" defaultValue={b.province} maxLength={60} /></label><label>Departamento<input name="department" defaultValue={b.department} maxLength={60} /></label></div>
    <div className="fv-three"><label>Ubigeo<input name="ubigeo" inputMode="numeric" maxLength={6} defaultValue={b.ubigeo} /></label><label>Serie de facturas<input name="series_factura" maxLength={4} defaultValue={b.series_factura} placeholder="F001" /></label><label>Serie de boletas<input name="series_boleta" maxLength={4} defaultValue={b.series_boleta} placeholder="B001" /></label></div>
    <div className="fv-two"><label>Moneda<select name="currency" defaultValue={b.currency || "PEN"}><option value="PEN">Soles (S/)</option><option value="USD">Dólares (US$)</option></select></label><label>IGV por defecto (%)<input name="default_tax_rate" type="number" min={0} max={100} step="0.01" defaultValue={b.default_tax_rate} /></label></div>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar datos"}</button>
    <Msg m={state} />
  </form>;
}

const templates = [["clasico", "Clásico", "Encabezado editorial y datos claros"], ["moderno", "Moderno", "Contraste y total destacado"], ["minimal", "Minimal", "Sobrio, ideal para imprimir"]] as const;
const colors = ["#1E3A8A", "#6A62E2", "#0F766E", "#B91C1C", "#C2410C", "#111827"];

/** «Logo y comprobantes». */
export function BrandingForm({ org, logoUrl, template, color, width }: { org: string; logoUrl: string | null; template: string; color: string; width: number }) {
  const [state, action, pending] = useActionState(saveBranding.bind(null, org), idle);
  const [preview, setPreview] = useState<string | null>(logoUrl);
  return <form action={action} className="fv-create fv-form fv-settings-card">
    <h3>Logo y comprobantes</h3>
    <div className="fv-logo-row">
      <span className="fv-logo-box">{preview ? <img src={preview} alt="Tu logo" /> : <b>Sin logo</b>}</span>
      <label className="fv-button secondary fv-file">Elegir logo<input type="file" name="logo" hidden accept="image/png,image/jpeg,image/webp" onChange={e => { const f = e.target.files?.[0]; if (f) setPreview(URL.createObjectURL(f)); }} /></label>
    </div>
    <fieldset className="fv-radio-cards"><legend>Diseño del PDF</legend>{templates.map(([k, t, d]) => <label key={k}><input type="radio" name="pdf_template" value={k} defaultChecked={(template || "clasico") === k} /><span><strong>{t}</strong><small>{d}</small></span></label>)}</fieldset>
    <fieldset className="fv-swatches"><legend>Color</legend>{colors.map(c => <label key={c} title={c}><input type="radio" name="brand_color" value={c} defaultChecked={(color || "#1E3A8A").toUpperCase() === c} /><i style={{ background: c }} /></label>)}</fieldset>
    <fieldset className="fv-segment-field"><legend>Ancho del ticket</legend><label><input type="radio" name="ticket_width" value="58" defaultChecked={width === 58} /> 58 mm</label><label><input type="radio" name="ticket_width" value="80" defaultChecked={width !== 58} /> 80 mm</label></fieldset>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar diseño"}</button>
    <Msg m={state} />
  </form>;
}

export type PaySettings = { yape: string; plin: string; bank_name: string; bank_account: string; bank_cci: string; holder: string; note: string; reminders: boolean; offsets: number[]; yape_qr: boolean; plin_qr: boolean };

/** «Medios de cobro». */
export function PaySettingsForm({ org, s }: { org: string; s: PaySettings }) {
  const [state, action, pending] = useActionState(savePaySettings.bind(null, org), idle);
  return <form action={action} className="fv-create fv-form fv-settings-card">
    <h3>Medios de cobro</h3>
    <p className="fv-caption">Salen en tu enlace de pago y en los recordatorios. Tú confirmas cada pago antes de darlo por cobrado.</p>
    <div className="fv-two"><label>Celular de Yape<input name="yape" inputMode="numeric" maxLength={9} defaultValue={s.yape} /></label><label>Celular de Plin<input name="plin" inputMode="numeric" maxLength={9} defaultValue={s.plin} /></label></div>
    <div className="fv-two"><label>QR de Yape {s.yape_qr && <small>(ya tienes uno)</small>}<input type="file" name="yape_qr" accept="image/png,image/jpeg" /></label><label>QR de Plin {s.plin_qr && <small>(ya tienes uno)</small>}<input type="file" name="plin_qr" accept="image/png,image/jpeg" /></label></div>
    <div className="fv-three"><label>Banco<input name="bank_name" maxLength={60} defaultValue={s.bank_name} placeholder="BCP, Interbank…" /></label><label>N.º de cuenta<input name="bank_account" maxLength={40} defaultValue={s.bank_account} /></label><label>CCI<input name="bank_cci" inputMode="numeric" maxLength={23} defaultValue={s.bank_cci} /></label></div>
    <div className="fv-two"><label>Titular<input name="holder" maxLength={120} defaultValue={s.holder} /></label><label>Nota para el cliente<input name="note" maxLength={300} defaultValue={s.note} placeholder="Ej.: envía tu constancia por WhatsApp" /></label></div>
    <label className="fv-check"><input type="checkbox" name="reminders" defaultChecked={s.reminders} /> Recordatorios automáticos de cobro por correo</label>
    <label>Días del recordatorio (negativo = antes del vencimiento)<input name="offsets" defaultValue={s.offsets.join(", ")} placeholder="-3, 0, 3, 7, 15" /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar medios de cobro"}</button>
    <Msg m={state} />
  </form>;
}

/** «SUNAT»: SOL user, digital certificate and environment (same /api/fiscal/setup as the mobile app). The person types their own keys. */
export function SunatForm({ org, connected, env }: { org: string; connected: boolean; env: string | null }) {
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  async function submit(form: HTMLFormElement) {
    setM(null);
    const fd = new FormData(form);
    const file = fd.get("cert");
    if (!(file instanceof File) || !file.size) { setM({ ok: false, message: "Elige tu certificado digital (.pfx, .p12 o .pem)." }); return; }
    if (file.size > 100_000) { setM({ ok: false, message: "El certificado pesa demasiado. Revisa que sea el archivo correcto." }); return; }
    const pem = /\.pem$/i.test(file.name);
    const bytes = new Uint8Array(await file.arrayBuffer());
    let bin = ""; for (const b of bytes) bin += String.fromCharCode(b);
    setBusy(true);
    try {
      const { data } = await createClient().auth.getSession();
      const res = await fetch("/api/fiscal/setup", { method: "POST", headers: { "content-type": "application/json", ...(data.session ? { authorization: `Bearer ${data.session.access_token}` } : {}) },
        body: JSON.stringify({ org_id: org, sol_user: String(fd.get("sol_user") ?? "").trim(), sol_password: String(fd.get("sol_password") ?? ""), certificate_b64: btoa(bin), certificate_format: pem ? "pem" : "pfx",
          certificate_password: String(fd.get("cert_password") ?? ""), env: fd.get("env") === "prod" ? "prod" : "beta" }) });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) { setM({ ok: false, message: j.error ?? "No se pudo conectar con SUNAT." }); return; }
      form.reset();
      setM({ ok: true, message: `SUNAT conectada (${j.env === "prod" ? "producción" : "pruebas"}). Tu certificado vence el ${j.cert_expires}.` });
      router.refresh();
    } catch { setM({ ok: false, message: "Sin conexión." }); }
    finally { setBusy(false); }
  }
  return <form className="fv-create fv-form fv-settings-card" autoComplete="off" onSubmit={e => { e.preventDefault(); void submit(e.currentTarget); }}>
    <h3>SUNAT {connected ? <span className="fv-pill is-ok">Conectada · {env === "prod" ? "producción" : "pruebas"}</span> : <span className="fv-pill is-wait">Sin conectar</span>}</h3>
    <p className="fv-caption">Tu usuario secundario SOL y tu certificado digital. Se guardan cifrados y solo se usan para enviar tus comprobantes. {connected ? "Llénalo solo si quieres cambiarlos." : ""}</p>
    <div className="fv-two"><label>Usuario SOL<input name="sol_user" maxLength={30} required autoComplete="off" /></label><label>Clave SOL<input name="sol_password" type="password" maxLength={80} required autoComplete="new-password" /></label></div>
    <div className="fv-two"><label>Certificado digital (.pfx, .p12, .pem)<input type="file" name="cert" accept=".pfx,.p12,.pem" required /></label><label>Clave del certificado<input name="cert_password" type="password" maxLength={120} autoComplete="new-password" /></label></div>
    <fieldset className="fv-segment-field"><legend>Ambiente</legend><label><input type="radio" name="env" value="beta" defaultChecked={env !== "prod"} /> Pruebas (beta)</label><label><input type="radio" name="env" value="prod" defaultChecked={env === "prod"} /> Producción</label></fieldset>
    <button className="fv-button" disabled={busy}>{busy ? "Verificando con SUNAT…" : connected ? "Actualizar conexión" : "Conectar SUNAT"}</button>
    <Msg m={m} />
  </form>;
}

const roles = [["cajero", "Cajero"], ["vendedor", "Vendedor"], ["finanzas", "Finanzas"], ["tecnico", "Técnico"], ["admin", "Administrador"]] as const;

export function InviteForm({ org, left }: { org: string; left: number | null }) {
  const [state, action, pending] = useActionState(inviteMember.bind(null, org), idle);
  return <form action={action} className="fv-create fv-form fv-settings-card" key={state.ok ? state.message : "i"}>
    <h3>Invitar a alguien</h3>
    {left != null && <p className="fv-caption">{left > 0 ? `Te quedan ${left} ${left === 1 ? "usuario" : "usuarios"} en tu plan.` : "Tu plan no tiene usuarios libres. Mejóralo en Solvex Hub para invitar a más personas."}</p>}
    <div className="fv-three"><label>Correo<input type="email" name="email" maxLength={200} required /></label><label>Nombre<input name="name" maxLength={80} /></label>
      <label>Rol<select name="role" defaultValue="cajero">{roles.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label></div>
    <button className="fv-button" disabled={pending || left === 0}>{pending ? "Invitando…" : "Invitar"}</button>
    <Msg m={state} />
  </form>;
}

export function MemberEditor({ org, userId, role, name, commission, goal, isOwner, isMe }: { org: string; userId: string; role: string; name: string; commission: number | null; goal: number | null; isOwner: boolean; isMe: boolean }) {
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState(setMemberRole.bind(null, org, userId), idle);
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  if (!open) return <span className="fv-actions"><button className="fv-link" onClick={() => setOpen(true)}>Editar</button>
    {!isOwner && !isMe && <button className="fv-link fv-neg" onClick={async () => { if (!window.confirm(`¿Quitarle el acceso a ${name}?`)) return; const r = await removeMember(org, userId).catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); if (r.ok) router.refresh(); }}>Quitar</button>}<Msg m={m} /></span>;
  return <form action={action} className="fv-inline-form fv-member-form">
    <label className="fv-search"><span>Nombre</span><input name="name" defaultValue={name} maxLength={80} /></label>
    {isOwner ? <input type="hidden" name="role" value="admin" /> : <label className="fv-search"><span>Rol</span><select name="role" defaultValue={role === "admin" ? "admin" : role}>{roles.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>}
    <label className="fv-search"><span>Comisión %</span><input name="commission" inputMode="decimal" defaultValue={commission ?? ""} /></label>
    <label className="fv-search"><span>Meta del mes</span><input name="goal" inputMode="decimal" defaultValue={goal ?? ""} /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar"}</button>
    <button type="button" className="fv-link" onClick={() => setOpen(false)}>Cerrar</button>
    <Msg m={state} />
  </form>;
}

export function CancelInvite({ org, id }: { org: string; id: string }) {
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  return <span className="fv-inline-action"><button className="fv-link" onClick={async () => { const r = await cancelInvite(org, id).catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); if (r.ok) router.refresh(); }}>Cancelar invitación</button><Msg m={m} /></span>;
}
