/* Solvex Hub · panel — utilidades comunes.
 * Seguridad en el navegador:
 *  - Todo texto que viene del servidor se ESCAPA al pintarlo (plantilla html``). No hay innerHTML con datos crudos.
 *  - La cookie de sesión es HttpOnly (JavaScript no la puede leer). Cada escritura lleva el token CSRF.
 *  - Nada sensible se guarda en localStorage (solo el tema claro/oscuro).
 */

/* ---------------- HTML seguro ---------------- */
class Safe { constructor(s) { this.s = s; } toString() { return this.s; } }
const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' };
export const esc = (v) => String(v == null ? '' : v).replace(/[&<>"'`]/g, (c) => ESC[c]);
const part = (v) => (v instanceof Safe ? v.s : Array.isArray(v) ? v.map(part).join('') : v === false || v == null ? '' : esc(v));
export function html(strings, ...vals) { let out = strings[0]; vals.forEach((v, i) => { out += part(v) + strings[i + 1]; }); return new Safe(out); }
export const raw = (s) => new Safe(String(s)); // SOLO para marcado generado por nosotros (íconos, SVG del servidor)
export const $ = (s, el = document) => el.querySelector(s);
export const $$ = (s, el = document) => [...el.querySelectorAll(s)];

/* ---------------- estado ---------------- */
export const S = { me: null, csrf: null, lookups: null, kpis: null, tz: 'America/Lima', sudoUntil: null };

/* ---------------- API ---------------- */
export class ApiError extends Error { constructor(status, body) { super((body && body.message) || 'Error ' + status); this.status = status; this.body = body || {}; this.field = this.body.field; } }
let onAuthLost = () => {};
export function setAuthLost(fn) { onAuthLost = fn; }

export async function api(method, path, body, { retry = true } = {}) {
  const opts = { method, credentials: 'same-origin', headers: { Accept: 'application/json' } };
  if (body !== undefined) { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
  if (method !== 'GET' && S.csrf) opts.headers['X-CSRF-Token'] = S.csrf;
  let res;
  try { res = await fetch('/api/admin' + path, opts); } catch (_) { throw new ApiError(0, { message: 'Sin conexión con el servidor.' }); }
  let data = null; try { data = await res.json(); } catch (_) { data = null; }
  if (data && data.csrf) S.csrf = data.csrf;
  if (res.status === 401 && !path.startsWith('/auth/')) { onAuthLost(data); throw new ApiError(401, data); }
  if (res.status === 403 && data && data.needSudo && retry) {
    const ok = await sudoPrompt();
    if (ok) return api(method, path, body, { retry: false });
  }
  if (!res.ok) throw new ApiError(res.status, data);
  return data;
}
export const get = (p) => api('GET', p);
export const post = (p, b = {}) => api('POST', p, b);
export const put = (p, b = {}) => api('PUT', p, b);
export const del = (p) => api('DELETE', p);

/* ---------------- formatos ---------------- */
const SYMBOL = { PEN: 'S/ ', USD: 'US$ ', EUR: '€ ', GBP: '£ ' };
export const money = (c, cur = 'PEN') => (SYMBOL[cur] || (cur || 'PEN') + ' ') + (Number(c || 0) / 100).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
/** Desglose corto de un cobro: "S/ 127.12 + IGV 18 % S/ 22.88", "Exportación (0 % IGV)"… */
export const taxLine = (i) => {
  if (!i || i.tax_treatment == null) return '';
  if (i.tax_treatment === 'mor') return i.tax_cents ? `incluye ${money(i.tax_cents, i.currency)} de impuesto (MoR)` : 'cobrado por MoR';
  if (i.tax_treatment === 'exportacion') return 'Exportación · 0 % IGV';
  if (i.tax_treatment === 'no_sujeto') return 'Sin IGV (Nuevo RUS)';
  return `${money(i.subtotal_cents, i.currency)} + ${i.tax_label || 'impuesto'} ${money(i.tax_cents, i.currency)}`;
};
export const COUNTRIES = [['PE', 'Perú'], ['AR', 'Argentina'], ['BO', 'Bolivia'], ['BR', 'Brasil'], ['CA', 'Canadá'], ['CL', 'Chile'], ['CO', 'Colombia'], ['CR', 'Costa Rica'], ['EC', 'Ecuador'], ['SV', 'El Salvador'],
  ['ES', 'España'], ['US', 'Estados Unidos'], ['GT', 'Guatemala'], ['HN', 'Honduras'], ['MX', 'México'], ['NI', 'Nicaragua'], ['PA', 'Panamá'], ['PY', 'Paraguay'], ['DO', 'República Dominicana'],
  ['UY', 'Uruguay'], ['VE', 'Venezuela'], ['DE', 'Alemania'], ['FR', 'Francia'], ['IT', 'Italia'], ['GB', 'Reino Unido'], ['PT', 'Portugal']];
export const countryName = (c) => (COUNTRIES.find((x) => x[0] === c) || [c, c])[1];
export const CPE = { pendiente: ['warn', 'Por enviar'], enviado: ['info', 'Esperando a SUNAT'], aceptado: ['ok', 'Aceptado'], rechazado: ['bad', 'Rechazado'], error: ['bad', 'Con error'], anulado: ['mute', 'Anulado'] };
export const FISCAL = { factura: 'Factura', boleta: 'Boleta', ninguno: 'Sin comprobante (MoR)' };
export const PROVIDER = { hub: 'Solvex Hub (Culqi, Yape, transferencia)', paddle: 'Paddle (Merchant of Record)', lemonsqueezy: 'Lemon Squeezy (Merchant of Record)', stripe: 'Stripe (Merchant of Record)' };
export const soles = (c) => (Number(c || 0) / 100).toFixed(2);
export const phoneFmt = (p) => { const d = String(p || '').replace(/\D/g, ''); return /^51\d{9}$/.test(d) ? '+51 ' + d.slice(2, 5) + ' ' + d.slice(5, 8) + ' ' + d.slice(8) : (d ? '+' + d : ''); };
const dfCache = {};
const df = (opts) => { const k = JSON.stringify(opts) + S.tz; return dfCache[k] || (dfCache[k] = new Intl.DateTimeFormat('es-PE', Object.assign({ timeZone: S.tz }, opts))); };
export function fdate(iso) { if (!iso) return '—'; const d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(iso + 'T12:00:00Z') : new Date(iso); return /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(d) : df({ day: 'numeric', month: 'short', year: 'numeric' }).format(d); }
export function fdatetime(iso) { if (!iso) return '—'; return df({ day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(iso)); }
export function ago(iso) {
  if (!iso) return '—'; const s = (Date.now() - Date.parse(iso)) / 1000;
  if (s < 60) return 'hace un momento'; if (s < 3600) return `hace ${Math.floor(s / 60)} min`; if (s < 86400) return `hace ${Math.floor(s / 3600)} h`;
  if (s < 86400 * 30) return `hace ${Math.floor(s / 86400)} d`; return fdate(iso);
}
export const daysLabel = (n) => n == null ? '' : n === 0 ? 'vence hoy' : n > 0 ? `faltan ${n} día${n === 1 ? '' : 's'}` : `venció hace ${-n} día${n === -1 ? '' : 's'}`;
export const UNIT = { day: ['día', 'días'], month: ['mes', 'meses'], year: ['año', 'años'] };
export function cycle(unit, count) {
  if (unit === 'none') return 'pago único';
  if (unit === 'month' && count === 1) return 'mensual'; if (unit === 'month' && count === 3) return 'trimestral'; if (unit === 'month' && count === 6) return 'semestral'; if (unit === 'year' && count === 1) return 'anual';
  return `cada ${count} ${UNIT[unit][count === 1 ? 0 : 1]}`;
}

/* ---------------- etiquetas ---------------- */
export const LIC = { pendiente: ['info', 'Pendiente'], prueba: ['info', 'En prueba'], activa: ['ok', 'Activa'], gracia: ['warn', 'En gracia'], suspendida: ['bad', 'Suspendida'], cancelada: ['mute', 'Cancelada'] };
export const INV = { pendiente: ['warn', 'Pendiente'], parcial: ['warn', 'Pago parcial'], pagada: ['ok', 'Pagado'], anulada: ['mute', 'Anulado'] };
export const PAY = { por_verificar: ['warn', 'Por verificar'], aprobado: ['ok', 'Aprobado'], rechazado: ['bad', 'Rechazado'], reembolsado: ['mute', 'Reembolsado'], anulado: ['mute', 'Anulado'] };
export const VER = { pendiente: ['info', 'Sin verificar'], verificado: ['ok', 'Verificado'], observado: ['warn', 'Observado'], rechazado: ['bad', 'Rechazado'] };
export const METHOD = { culqi: 'Tarjeta/Yape (Culqi)', yape: 'Yape', plin: 'Plin', transferencia: 'Transferencia', deposito: 'Depósito', efectivo: 'Efectivo', otro: 'Otro', mor: 'Merchant of Record' };
export const pill = (map, k, extra) => { const m = map[k] || ['mute', k]; return html`<span class="pill ${m[0]}">${m[1]}${extra ? html` · ${extra}` : ''}</span>`; };
export const licPill = (l) => pill(LIC, l.status, l.status === 'suspendida' && l.suspension === 'manual' ? 'manual' : '');
export const can = (perm) => !!(S.me && S.me.perms && S.me.perms.includes(perm));

/* ---------------- íconos (trazo, 24px) ---------------- */
const P = {
  home: 'M3 11.5 12 4l9 7.5M5.5 10v9.5h13V10',
  users: 'M16 19v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 17.5V19M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M20 19v-1.5a3.5 3.5 0 0 0-2.5-3.35M15.5 4.2a3.5 3.5 0 0 1 0 6.6',
  key: 'M14.5 9.5a4.5 4.5 0 1 1-1.3-3.2M13.2 6.3 20 13v3h-3v-2h-2v-2l-1.8-1.8M7.5 9.5h.01',
  card: 'M3 6.5h18v11H3zM3 10h18M7 14.5h3',
  box: 'M4 7.5 12 3.5l8 4v9l-8 4-8-4zM4 7.5l8 4 8-4M12 11.5v9',
  plug: 'M9 3v5M15 3v5M6.5 8h11v3a5.5 5.5 0 0 1-11 0zM12 16.5V21',
  inbox: 'M3 13.5h5l1.5 3h5l1.5-3h5M5 5.5h14l2 8v5H3v-5z',
  life: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8M5.6 5.6l3.6 3.6M14.8 14.8l3.6 3.6M18.4 5.6l-3.6 3.6M9.2 14.8l-3.6 3.6',
  chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  book: 'M5 4.5h11a3 3 0 0 1 3 3V20H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h11',
  team: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8M4 20.5a8 8 0 0 1 16 0',
  shield: 'M12 3 4.5 6v5.5c0 4.5 3.2 8.3 7.5 9.5 4.3-1.2 7.5-5 7.5-9.5V6zM9 12l2 2 4-4',
  gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8M5 20a7 7 0 0 1 14 0',
  plus: 'M12 5v14M5 12h14', search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14M20 20l-3.5-3.5', copy: 'M9 9h10v11H9zM5 15V4h10',
  send: 'M21 3 10 14M21 3l-7 18-4-7-7-4z', check: 'M5 12.5 10 17.5 19 7', x: 'M6 6l12 12M18 6 6 18', back: 'M15 5l-7 7 7 7',
  bolt: 'M13 3 5 13.5h6L10 21l8-10.5h-6z', alert: 'M12 4 2.5 20h19zM12 10v4.5M12 17.5h.01', logout: 'M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10',
  moon: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5', sun: 'M12 16.5a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
  wa: 'M4 20l1.3-3.9A8 8 0 1 1 8 19zM9 9.5c.5 2 2.5 4 4.5 4.5l1.5-1.5 2 1-.5 1.5c-3 .5-7.5-4-7-7L11 7.5l1 2z',
  refresh: 'M20 11a8 8 0 0 0-14.5-4.5L4 8M4 4v4h4M4 13a8 8 0 0 0 14.5 4.5L20 16M20 20v-4h-4', download: 'M12 4v11M7 10l5 5 5-5M5 20h14',
  pause: 'M9 5v14M15 5v14', play: 'M7 4.5v15l12-7.5z', clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18M12 7v5l3 2', menu: 'M4 7h16M4 12h16M4 17h16',
};
export const icon = (n, cls = '') => raw(`<svg class="ic ${cls}" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="${P[n] || ''}"/></svg>`);

/* ---------------- avisos (toast) ---------------- */
export function toast(msg, kind = '') {
  const box = $('#toasts'); const el = document.createElement('div');
  el.className = 'toast ' + kind; el.setAttribute('role', kind === 'bad' ? 'alert' : 'status'); el.textContent = msg;
  box.appendChild(el); setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 300); }, kind === 'bad' ? 6000 : 3500);
}
export const fail = (e) => toast(e && e.message ? e.message : 'Ocurrió un error.', 'bad');

/* ---------------- ventanas (modal) ---------------- */
let lastFocus = null;
export function modal(content, { wide = false, onClose = null } = {}) {
  closeModal();
  lastFocus = document.activeElement;
  const bg = document.createElement('div'); bg.className = 'modal-bg'; bg.id = 'modal';
  bg.innerHTML = `<div class="modal ${wide ? 'wide' : ''}" role="dialog" aria-modal="true">${content}</div>`;
  document.body.appendChild(bg);
  bg.addEventListener('mousedown', (e) => { if (e.target === bg) closeModal(); });
  bg.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeModal(); if (e.key === 'Tab') trap(e, bg); });
  bg._onClose = onClose;
  const f = bg.querySelector('[autofocus], input:not([type=hidden]), select, textarea, button'); if (f) setTimeout(() => f.focus(), 20);
  return bg.firstElementChild;
}
function trap(e, bg) {
  const els = $$('a[href], button:not([disabled]), input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])', bg).filter((x) => x.offsetParent !== null);
  if (!els.length) return; const first = els[0], last = els[els.length - 1];
  if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); } else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
}
export function closeModal() { const m = $('#modal'); if (m) { const cb = m._onClose; m.remove(); if (cb) cb(); if (lastFocus && lastFocus.focus) lastFocus.focus(); } }
export const isModalOpen = () => !!$('#modal');

/**
 * Formulario en ventana. fields: [{ k, label, type: text|number|money|select|textarea|date|checkbox|email|password|section|html, options:[[v,l]], value, help, required, placeholder, attrs }]
 * onSubmit(values) puede lanzar ApiError; si trae .field se marca el campo.
 */
export function form({ title, intro = null, fields, submit = 'Guardar', danger = false, wide = false, onSubmit, after = null }) {
  const f = (x) => {
    const id = 'f_' + x.k;
    if (x.type === 'section') return html`<h3 class="fsec">${x.label}</h3>`;
    if (x.type === 'html') return x.html;
    if (x.type === 'checkbox') return html`<label class="chk"><input type="checkbox" id="${id}" name="${x.k}" ${x.value ? raw('checked') : ''}> <span>${x.label}</span></label>${x.help ? html`<p class="help">${x.help}</p>` : ''}`;
    let input;
    const common = raw(`id="${id}" name="${esc(x.k)}" ${x.required ? 'required' : ''} ${x.attrs || ''}`);
    if (x.type === 'select') input = html`<select ${common}>${(x.options || []).map((o) => { const [v, l] = Array.isArray(o) ? o : [o, o]; return html`<option value="${v}" ${String(v) === String(x.value ?? '') ? raw('selected') : ''}>${l}</option>`; })}</select>`;
    else if (x.type === 'textarea') input = html`<textarea ${common} rows="${x.rows || 3}" placeholder="${x.placeholder || ''}">${x.value || ''}</textarea>`;
    else input = html`<input ${common} type="${x.type === 'money' ? 'text' : x.type || 'text'}" ${x.type === 'money' ? raw('inputmode="decimal"') : ''} value="${x.value ?? ''}" placeholder="${x.placeholder || ''}" autocomplete="${x.autocomplete || 'off'}">`;
    return html`<div class="fld ${x.half ? 'half' : ''}"><label for="${id}">${x.label}${x.required ? html`<b aria-hidden="true">*</b>` : ''}</label>${x.type === 'money' ? html`<div class="money-in"><span>S/</span>${input}</div>` : input}${x.help ? html`<p class="help">${x.help}</p>` : ''}<p class="ferr" id="${id}_err" role="alert"></p></div>`;
  };
  const el = modal(String(html`<form class="mform" novalidate><h2>${title}</h2>${intro || ''}<div class="fgrid">${fields.map(f)}</div><div class="ferr general" role="alert"></div><div class="acts"><button type="button" class="btn" data-close>Cancelar</button><button type="submit" class="btn ${danger ? 'danger' : 'pri'}">${submit}</button></div></form>`), { wide });
  const fm = el.querySelector('form');
  fm.querySelector('[data-close]').onclick = closeModal;
  if (after) after(fm);
  fm.addEventListener('submit', async (e) => {
    e.preventDefault();
    $$('.ferr', fm).forEach((x) => { x.textContent = ''; }); $$('.invalid', fm).forEach((x) => x.classList.remove('invalid'));
    const vals = {};
    for (const x of fields) {
      if (!x.k || ['section', 'html'].includes(x.type)) continue;
      const inp = fm.querySelector('#f_' + x.k); if (!inp) continue;
      vals[x.k] = x.type === 'checkbox' ? inp.checked : x.type === 'number' ? (inp.value === '' ? null : Number(inp.value)) : inp.value.trim();
      if (x.required && (vals[x.k] === '' || vals[x.k] == null)) { const er = fm.querySelector('#f_' + x.k + '_err'); er.textContent = 'Es obligatorio.'; inp.classList.add('invalid'); inp.focus(); return; }
    }
    const btn = fm.querySelector('button[type=submit]'); btn.disabled = true; btn.classList.add('busy');
    try { await onSubmit(vals, fm); }
    catch (err) {
      const fe = err.field && fm.querySelector('#f_' + err.field + '_err');
      if (fe) { fe.textContent = err.message; const i = fm.querySelector('#f_' + err.field); if (i) { i.classList.add('invalid'); i.focus(); } }
      else fm.querySelector('.ferr.general').textContent = err.message || 'Error';
    } finally { btn.disabled = false; btn.classList.remove('busy'); }
  });
  return fm;
}

export function confirmBox({ title, body, submit = 'Confirmar', danger = false, reason = false, reasonLabel = 'Motivo', onConfirm }) {
  return form({ title, intro: html`<p class="intro">${body}</p>`, fields: reason ? [{ k: 'reason', label: reasonLabel, type: 'textarea', required: true, rows: 2 }] : [], submit, danger, onSubmit: onConfirm });
}

/** Muestra un secreto UNA vez, con botón copiar y advertencia. */
export function secretBox(title, items, note) {
  modal(String(html`<h2>${title}</h2><p class="intro warnbox">${icon('alert')} ${note || 'Cópialo ahora y guárdalo en un lugar seguro. Por seguridad no se volverá a mostrar.'}</p>
    ${items.map(([label, value]) => html`<div class="secret"><span>${label}</span><code>${value}</code><button type="button" class="btn sm" data-copy="${value}">${icon('copy')} Copiar</button></div>`)}
    <div class="acts"><button class="btn pri" data-close>Ya lo guardé</button></div>`));
  $('#modal [data-close]').onclick = closeModal;
}

export async function copy(text) { try { await navigator.clipboard.writeText(text); toast('Copiado.'); } catch (_) { toast('No se pudo copiar. Selecciónalo y cópialo.', 'bad'); } }
document.addEventListener('click', (e) => { const b = e.target.closest('[data-copy]'); if (b) { e.preventDefault(); copy(b.getAttribute('data-copy')); } });

/* ---------------- confirmación con 2FA (sudo) ---------------- */
let sudoWaiter = null;
export function sudoPrompt() {
  if (sudoWaiter) return sudoWaiter;
  sudoWaiter = new Promise((resolve) => {
    let done = false;
    const prevModal = $('#modal'); if (prevModal) prevModal.style.display = 'none';
    const bg = document.createElement('div'); bg.className = 'modal-bg top'; bg.id = 'sudo';
    bg.innerHTML = String(html`<form class="modal mform" novalidate><h2>${icon('shield')} Confirma que eres tú</h2><p class="intro">Esta acción es delicada. Escribe el código de 6 dígitos de tu app autenticadora. Vale 10 minutos.</p>
      <div class="fld"><label for="sudo_code">Código</label><input id="sudo_code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" pattern="[0-9]*" class="code-in"></div><p class="ferr general" role="alert"></p>
      <div class="acts"><button type="button" class="btn" data-x>Cancelar</button><button class="btn pri" type="submit">Confirmar</button></div></form>`);
    document.body.appendChild(bg);
    const finish = (ok) => { if (done) return; done = true; bg.remove(); if (prevModal) prevModal.style.display = ''; sudoWaiter = null; resolve(ok); };
    bg.querySelector('[data-x]').onclick = () => finish(false);
    bg.addEventListener('keydown', (e) => { if (e.key === 'Escape') finish(false); });
    setTimeout(() => $('#sudo_code').focus(), 20);
    bg.querySelector('form').addEventListener('submit', async (e) => {
      e.preventDefault();
      try { const r = await api('POST', '/auth/sudo', { code: $('#sudo_code').value.trim() }, { retry: false }); S.sudoUntil = r.sudoUntil; finish(true); }
      catch (err) { bg.querySelector('.ferr').textContent = err.message; $('#sudo_code').select(); }
    });
  });
  return sudoWaiter;
}

/* ---------------- tablas ---------------- */
export function table(cols, rows, { empty = 'Sin registros.', rowAttrs = null } = {}) {
  if (!rows.length) return html`<div class="empty-row">${empty}</div>`;
  return html`<div class="tablewrap"><table><thead><tr>${cols.map((c) => html`<th class="${c.cls || ''}">${c.label}</th>`)}</tr></thead><tbody>${rows.map((r) => html`<tr ${rowAttrs ? raw(rowAttrs(r)) : ''}>${cols.map((c) => html`<td class="${c.cls || ''}" data-label="${c.label}">${c.render(r)}</td>`)}</tr>`)}</tbody></table></div>`;
}

/* ---------------- gráfico de barras simple (SVG) ---------------- */
export function bars(series, { keys, colors, labels, height = 180, fmt = money, labelOf = (x) => x.month }) {
  const W = Math.max(560, series.length * 92), H = height, pad = { l: 8, r: 8, t: 14, b: 26 };
  const max = Math.max(1, ...series.flatMap((s) => keys.map((k) => s[k] || 0)));
  const gw = (W - pad.l - pad.r) / series.length, bw = Math.min(22, (gw - 10) / keys.length);
  let out = `<svg viewBox="0 0 ${W} ${H}" class="chart" role="img" aria-label="Gráfico">`;
  for (let i = 0; i <= 3; i++) { const y = pad.t + (H - pad.t - pad.b) * (i / 3); out += `<line x1="${pad.l}" x2="${W - pad.r}" y1="${y}" y2="${y}" class="grid"/>`; }
  series.forEach((s, i) => {
    const x0 = pad.l + gw * i + (gw - bw * keys.length - 4 * (keys.length - 1)) / 2;
    keys.forEach((k, j) => {
      const v = s[k] || 0, h = (H - pad.t - pad.b) * (v / max), x = x0 + j * (bw + 4), y = H - pad.b - h;
      out += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${bw.toFixed(1)}" height="${Math.max(0, h).toFixed(1)}" rx="3" class="${colors[j]}"><title>${esc(labels[j])}: ${esc(fmt(v))}</title></rect>`;
    });
    out += `<text x="${(pad.l + gw * i + gw / 2).toFixed(1)}" y="${H - 8}" text-anchor="middle">${esc(labelOf(s))}</text>`;
  });
  return raw(out + '</svg>');
}
export const monthLabel = (ym) => { const [y, m] = ym.split('-'); return ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'][+m - 1] + ' ' + y.slice(2); };

/** Debounce simple. */
export const debounce = (fn, ms = 250) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

/** Ganchos que llena app.js (evita importaciones circulares). */
export const hooks = { reload: async () => {}, counts: async () => {} };
export const go = (hash) => { if (location.hash === hash) hooks.reload(); else location.hash = hash; };
