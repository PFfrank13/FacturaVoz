/* Solvex Hub · panel — arranque, menú, rutas y tiempo real. */
import { html, raw, $, $$, S, api, get, icon, toast, fail, setAuthLost, isModalOpen, closeModal, debounce, can, hooks } from './core.js';
import { renderAuth, LOGO } from './auth.js';
import * as M from './views-main.js';
import * as B from './views-billing.js';
import * as A from './views-admin.js';

const NAV = [
  ['Operación', [
    ['inicio', 'Inicio', 'home', M.dashboard, 'dashboard.view'],
    ['clientes', 'Clientes', 'users', M.clients, 'clients.view'],
    ['licencias', 'Licencias', 'key', M.licenses, 'licenses.view'],
    ['cobros', 'Cobros y pagos', 'card', B.billing, 'billing.view', 'pending_payments'],
  ]],
  ['Catálogo', [
    ['productos', 'Productos y planes', 'box', A.products, 'licenses.view'],
    ['integraciones', 'Integraciones', 'plug', A.integrations, 'licenses.view'],
  ]],
  ['Comercial y soporte', [
    ['solicitudes', 'Solicitudes', 'inbox', A.leads, 'leads.manage', 'new_leads'],
    ['soporte', 'Soporte', 'life', A.tickets, 'tickets.manage', 'open_tickets'],
    ['reclamaciones', 'Libro de reclamaciones', 'book', A.complaints, 'complaints.manage', 'complaints_due'],
  ]],
  ['Administración', [
    ['finanzas', 'Finanzas', 'chart', B.finance, 'billing.view'],
    ['equipo', 'Equipo y accesos', 'team', A.team, 'dashboard.view'],
    ['auditoria', 'Auditoría', 'shield', A.audit, 'audit.view'],
    ['configuracion', 'Configuración', 'gear', A.settings, 'dashboard.view'],
  ]],
];
const DETAIL = { clientes: M.clientDetail, licencias: M.licenseDetail };
const ALL = Object.fromEntries(NAV.flatMap((g) => g[1]).map((x) => [x[0], x]));
ALL.cuenta = ['cuenta', 'Mi cuenta', 'user', A.account, null];

const root = $('#root');
let current = null, es = null;

function theme(next) {
  const t = next || (() => { try { return localStorage.getItem('slx_theme'); } catch (_) { return null; } })();
  if (t) document.documentElement.setAttribute('data-theme', t); else document.documentElement.removeAttribute('data-theme');
  if (next) { try { localStorage.setItem('slx_theme', next); } catch (_) { /* privado */ } }
}
theme();

function layout() {
  root.innerHTML = String(html`<div class="app">
    <aside class="side" id="side"><div class="logo">${raw(LOGO)}<div><b>SOLVEX</b><small>Hub</small></div></div>
      <nav aria-label="Secciones">${NAV.map(([g, items]) => { const vis = items.filter((i) => !i[4] || can(i[4])); return vis.length ? html`<p class="grp">${g}</p>${vis.map((i) => html`<a class="nav-b" href="#/${i[0]}" data-nav="${i[0]}">${icon(i[2])}<span>${i[1]}</span>${i[5] ? html`<em class="cnt" data-cnt="${i[5]}" hidden></em>` : ''}</a>`)}` : ''; })}</nav>
      <div class="sidefoot"><a class="who" href="#/cuenta" data-nav="cuenta">${icon('user')}<span><b>${S.me.name}</b><small>${S.me.roleLabel}</small></span></a>
        <div class="row-btns"><button class="btn sm ghost" id="thm" title="Tema claro u oscuro" aria-label="Cambiar tema">${icon('moon')}</button><button class="btn sm ghost" id="out">${icon('logout')} Salir</button></div>
        <p class="live" id="live" title="Actualización en tiempo real"><i></i><span>En vivo</span></p></div></aside>
    <div class="mainwrap"><header class="topbar"><button class="btn ghost sm menu-b" id="menu" aria-label="Menú">${icon('menu')}</button><div id="crumbs"></div></header><main class="main" id="main" tabindex="-1"></main></div></div>`);
  $('#out').onclick = async () => { try { await api('POST', '/auth/logout'); } catch (_) { /* nada */ } if (es) es.close(); location.hash = ''; start(); };
  $('#thm').onclick = () => { const dark = document.documentElement.getAttribute('data-theme') === 'dark' || (!document.documentElement.getAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches); theme(dark ? 'light' : 'dark'); };
  $('#menu').onclick = () => $('#side').classList.toggle('open');
  $('#side').addEventListener('click', (e) => { if (e.target.closest('a')) $('#side').classList.remove('open'); });
}

async function refreshCounts() {
  try {
    const d = await get('/dashboard'); S.kpis = d.kpis;
    for (const el of $$('[data-cnt]')) { const n = d.kpis[el.getAttribute('data-cnt')] || 0; el.textContent = n; el.hidden = !n; }
  } catch (_) { /* sin permiso o sin conexión */ }
}

async function route() {
  if (!S.me) return;
  const [name, id] = (location.hash.replace(/^#\/?/, '').split('?')[0] || 'inicio').split('/');
  const entry = ALL[name] || ALL.inicio;
  if (entry[4] && !can(entry[4])) { $('#main').innerHTML = String(html`<div class="empty"><h2>Sin acceso</h2><p>Tu rol no permite ver esta sección.</p></div>`); return; }
  $$('[data-nav]').forEach((a) => a.setAttribute('aria-current', a.getAttribute('data-nav') === entry[0] ? 'page' : 'false'));
  const fn = id && DETAIL[entry[0]] ? DETAIL[entry[0]] : entry[3];
  current = { name: entry[0], id, fn };
  const main = $('#main');
  main.onclick = null; // cada vista registra sus propios manejadores
  if (!main.dataset.keep) main.innerHTML = '<div class="loading" aria-busy="true"><span></span><span></span><span></span></div>';
  try { await fn(main, id); } catch (e) { if (e.status !== 401) main.innerHTML = String(html`<div class="empty"><h2>No se pudo cargar</h2><p>${e.message}</p></div>`); }
  document.title = (entry[1] || 'Panel') + ' · Solvex Hub';
  const cr = $('#crumbs'); if (cr) cr.textContent = entry[1] || '';
}
const reload = () => { const m = $('#main'); if (m) m.dataset.keep = '1'; return route().finally(() => { if (m) delete m.dataset.keep; }); };
hooks.reload = reload; hooks.counts = () => refreshCounts();
window.addEventListener('hashchange', () => { closeModal(); route(); window.scrollTo(0, 0); });

/* Tiempo real: el servidor avisa cambios y la vista actual se actualiza sola (si no estás llenando un formulario). */
function live() {
  if (es) es.close();
  es = new EventSource('/api/admin/stream');
  const dot = () => $('#live');
  es.onopen = () => dot() && dot().classList.add('on');
  es.onerror = () => dot() && dot().classList.remove('on');
  const soft = debounce(() => { refreshCounts(); if (!isModalOpen() && !document.activeElement.closest('.filters, .inline-edit')) reload(); }, 600);
  es.onmessage = (m) => {
    let e; try { e = JSON.parse(m.data); } catch (_) { return; }
    if (e.type === 'lead') toast('Nueva solicitud desde la web.');
    if (e.type === 'complaint') toast('Nuevo reclamo en el Libro de Reclamaciones.', 'warn');
    if (e.type === 'payment' && e.status === 'por_verificar') toast('Hay un pago por verificar.');
    if (e.type === 'delivery_failed') toast('Una integración no está recibiendo avisos. Revisa Integraciones.', 'warn');
    if (e.type === 'warning') toast(e.message, 'warn');
    soft();
  };
}

async function start() {
  S.me = null;
  setAuthLost(() => { if (S.me) { S.me = null; if (es) es.close(); toast('Tu sesión terminó. Vuelve a entrar.', 'warn'); start(); } });
  let me = null;
  try { me = await api('GET', '/auth/me'); } catch (_) { me = null; }
  if (!me || me.stage !== 'listo') { renderAuth(root, me ? me.stage : 'login', boot); return; }
  boot(me);
}
async function boot(me) {
  S.me = me.user; S.csrf = me.csrf;
  try { S.lookups = await get('/lookups'); S.tz = S.lookups.timezone || S.tz; } catch (e) { fail(e); }
  layout(); live(); refreshCounts(); route();
}
start();
