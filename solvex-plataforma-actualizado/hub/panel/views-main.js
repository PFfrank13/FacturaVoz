/* Vistas: Inicio, Clientes, Licencias. */
import { html, raw, $, $$, S, get, post, money, phoneFmt, fdate, fdatetime, ago, daysLabel, cycle, licPill, pill, INV, PAY, VER, METHOD, icon, table, bars, monthLabel, can, form, closeModal, toast, hooks, debounce, copy, taxLine, countryName, FISCAL, PROVIDER } from './core.js';
import { clientForm, verifyForm, licenseForm, editLicense, licenseAction, invoiceForm, paymentForm, approvePayment, rejectPayment, reversePayment, sendLink, payLinkBox } from './actions.js';

const head = (title, sub, tools = '') => html`<div class="top"><div><h1>${title}</h1>${sub ? html`<p class="sub">${sub}</p>` : ''}</div><div class="tools">${tools}</div></div>`;
const kpi = (label, value, note, cls = '', href = '') => html`<${href ? raw('a href="' + href + '"') : raw('div')} class="kpi ${cls}"><span class="l">${label}</span><b class="v">${value}</b>${note ? html`<span class="n">${note}</span>` : ''}</${href ? raw('a') : raw('div')}>`;
const ACT_LABEL = {
  'licencia.creada': 'creó una licencia', 'licencia.estado': 'cambió el estado de una licencia (automático)', 'licencia.editada': 'editó una licencia', 'licencia.vigencia_extendida': 'extendió una vigencia',
  'licencia.vigencia_revertida': 'revirtió una vigencia', 'licencia.suspendida_manual': 'suspendió una licencia', 'licencia.suspension_levantada': 'levantó una suspensión', 'licencia.cancelada': 'dio de baja una licencia',
  'licencia.reabierta': 'reabrió una licencia', 'licencia.clave_regenerada': 'regeneró una clave', 'licencia.reenviada': 'reenvió el estado a la instancia',
  'pago.aprobado': 'aprobó un pago', 'pago.registrado': 'registró un pago', 'pago.rechazado': 'rechazó un pago', 'pago.anulado': 'anuló un pago', 'pago.reembolsado': 'registró un reembolso', 'pago.tarjeta_rechazada': 'pago con tarjeta rechazado',
  'cobro.creado': 'emitió un cobro', 'cobro.anulado': 'anuló un cobro', 'cobro.enlace_enviado': 'envió un enlace de pago', 'cobro.enlace_solicitado': 'cliente pidió su enlace de pago',
  'cliente.creado': 'registró un cliente', 'cliente.editado': 'editó un cliente', 'cliente.consultado': 'consultó un cliente', 'cliente.verificacion': 'verificó un cliente', 'cliente.contacto': 'registró un contacto', 'cliente.exportado': 'exportó los datos de un cliente', 'cliente.anonimizado': 'anonimizó un cliente',
  'login.exitoso': 'inició sesión', 'login.fallido': 'intento de acceso fallido', 'login.bloqueo': 'cuenta bloqueada por intentos', 'logout': 'cerró sesión', '2fa.activado': 'activó el doble factor', '2fa.fallido': 'código 2FA incorrecto',
  'usuario.creado': 'invitó a una persona', 'usuario.editado': 'editó un usuario', 'usuario.contrasena_cambiada': 'cambió su contraseña', 'sesion.confirmacion': 'confirmó con 2FA',
  'instancia.creada': 'creó una instancia', 'instancia.editada': 'editó una instancia', 'instancia.secreto_rotado': 'rotó un secreto de instancia', 'producto.creado': 'creó un producto', 'plan.creado': 'creó un plan', 'plan.editado': 'editó un plan',
  'solicitud.recibida': 'nueva solicitud desde la web', 'solicitud.estado': 'actualizó una solicitud', 'ticket.creado': 'abrió un ticket', 'ticket.actualizado': 'actualizó un ticket', 'reclamo.recibido': 'nuevo reclamo', 'reclamo.respondido': 'respondió un reclamo',
  'gasto.registrado': 'registró un gasto', 'configuracion.editada': 'cambió la configuración', 'auditoria.verificada': 'verificó la bitácora', 'respaldo.creado': 'respaldo cifrado creado', 'saldo.ajuste': 'ajustó un saldo a favor',
};

/* =========================================================== INICIO */
export async function dashboard(main) {
  const [d, sys] = await Promise.all([get('/dashboard'), get('/system')]);
  const k = d.kpis, st = k.by_status;
  const diff = k.income_prev_month_cents ? Math.round(((k.income_month_cents - k.income_prev_month_cents) / k.income_prev_month_cents) * 100) : null;
  main.innerHTML = String(html`
    ${head('Inicio', 'Así está hoy el negocio. Se actualiza solo.')}
    ${sys.warnings.length ? html`<div class="banner warn">${icon('alert')}<div>${sys.warnings.map((w) => html`<p>${w}</p>`)}</div></div>` : ''}
    <div class="kpis">
      ${kpi('Ingreso mensual recurrente', money(k.mrr_cents), `${st.activa + st.gracia} licencias pagadas`)}
      ${kpi('Cobrado este mes', money(k.income_month_cents), diff == null ? 'sin datos del mes anterior' : `${diff >= 0 ? '+' : ''}${diff}% vs. mes anterior`)}
      ${kpi('Activas · en prueba', `${st.activa} · ${st.prueba}`, `${st.pendiente} pendientes de activar`, '', '#/licencias')}
      ${kpi('En gracia', st.gracia, 'se cortan si no pagan', st.gracia ? 'warn' : '', '#/licencias?status=gracia')}
      ${kpi('Suspendidas', st.suspendida, 'se reactivan solas al pagar', st.suspendida ? 'bad' : '', '#/licencias?status=suspendida')}
      ${kpi('Pagos por verificar', k.pending_payments, 'Yape, Plin y transferencias', k.pending_payments ? 'alert' : '', '#/cobros')}
      ${kpi('Cobros vencidos', money(k.overdue.c), `${k.overdue.n} cobro(s)`, k.overdue.n ? 'warn' : '', '#/cobros')}
      ${kpi('IGV del mes', money(k.igv_month_cents || 0), 'según comprobantes emitidos (por declarar)', '', '#/cobros?tab=comprobantes')}
      ${k.fiscal_problems ? kpi('Comprobantes con problemas', k.fiscal_problems, 'con error o rechazados por SUNAT', 'bad', '#/cobros?tab=comprobantes') : ''}
      ${k.failed_deliveries ? kpi('Integraciones con fallas', k.failed_deliveries, 'avisos que no llegaron', 'bad', '#/integraciones') : ''}
    </div>
    <div class="grid2">
      <section class="panel"><h2>Se cortan pronto <span>en gracia, ordenadas por fecha de corte</span></h2>
        ${d.grace.length ? html`<ul class="list">${d.grace.map((l) => html`<li class="row"><div><a class="lnk" href="#/licencias/${l.id}">${l.label}</a> <span class="t2">${l.client.code} · ${l.product.name}</span><div class="t2">Corte: <b>${l.cut_at ? fdatetime(l.cut_at) : 'sin corte automático'}</b></div></div><div class="row-btns">${can('billing.view') ? html`<button class="btn sm" data-link="${l.id}">${icon('send')} Enviar enlace</button>` : ''}</div></li>`)}</ul>` : html`<p class="empty-row">${icon('check')} Ninguna licencia en gracia.</p>`}
      </section>
      <section class="panel"><h2>Pagos por verificar <span>aprobar reactiva al instante</span></h2>
        ${d.pending_payments.length ? html`<ul class="list">${d.pending_payments.map((p) => html`<li class="row"><div><b>${money(p.amount_cents)}</b> · ${METHOD[p.method]} ${p.operation_ref ? html`<span class="code">${p.operation_ref}</span>` : ''}<div class="t2">${p.client.name} · ${p.invoice ? p.invoice.number : ''} · ${p.source === 'cliente' ? 'reportado por el cliente' : 'registrado por ' + (p.created_by || '—')} · ${ago(p.created_at)}</div></div>
          ${can('payments.approve') ? html`<div class="row-btns"><button class="btn sm pri" data-ok="${p.id}">${icon('check')} Aprobar</button><button class="btn sm" data-no="${p.id}">Rechazar</button></div>` : ''}</li>`)}</ul>` : html`<p class="empty-row">${icon('check')} Nada pendiente.</p>`}
      </section>
    </div>
    <div class="grid2">
      <section class="panel"><h2>Ingresos y gastos <span>últimos 6 meses</span></h2>${bars(d.series, { keys: ['income_cents', 'expense_cents'], colors: ['b-ok', 'b-mute'], labels: ['Ingresos', 'Gastos'], labelOf: (x) => monthLabel(x.month) })}
        <div class="legend"><span><i class="dot b-ok"></i>Ingresos</span><span><i class="dot b-mute"></i>Gastos</span></div></section>
      <section class="panel"><h2>Cobros esperados <span>si todos renuevan</span></h2>
        ${d.forecast.map((f) => html`<div class="hbar"><span>${monthLabel(f.month)}</span><div class="bar"><i data-w="${Math.round((f.cents / Math.max(1, ...d.forecast.map((x) => x.cents))) * 100)}"></i></div><b>${money(f.cents)}</b><span class="t2">${f.count} cobro(s)</span></div>`)}
        <h2 class="mt">Vencen en los próximos 7 días</h2>
        ${d.expiring.length ? html`<ul class="list compact">${d.expiring.map((l) => html`<li class="row"><a class="lnk" href="#/licencias/${l.id}">${l.label}</a><span class="t2">${fdate(l.period_end_local)} · ${daysLabel(l.days_left)}</span></li>`)}</ul>` : html`<p class="empty-row">Ninguna.</p>`}
      </section>
    </div>
    <section class="panel"><h2>Actividad reciente <span>en vivo</span></h2>
      <ul class="list compact">${d.activity.map((a) => html`<li class="row"><span><b>${a.actor_label || a.actor_type}</b> ${ACT_LABEL[a.action] || a.action.replace(/[._]/g, ' ')}</span><span class="t2">${ago(a.at)}</span></li>`)}</ul>
    </section>`);
  $$('.bar i[data-w]', main).forEach((i) => { i.style.width = i.getAttribute('data-w') + '%'; });
  main.onclick = async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.link) sendLink({ id: b.dataset.link, code: '' });
    if (b.dataset.ok) approvePayment({ id: b.dataset.ok });
    if (b.dataset.no) rejectPayment(d.pending_payments.find((p) => p.id === b.dataset.no));
  };
}

/* =========================================================== CLIENTES */
export async function clients(main) {
  const params = new URLSearchParams(location.hash.split('?')[1] || '');
  const state = { q: params.get('q') || '', verification: params.get('verification') || '' };
  main.innerHTML = String(html`${head('Clientes', 'Barberías, restaurantes y empresas. Cada cliente puede tener varias licencias de distintos productos.', can('clients.edit') ? html`<button class="btn pri" id="new">${icon('plus')} Nuevo cliente</button>` : '')}
    <div class="panel"><div class="filters"><label class="search">${icon('search')}<input id="q" type="search" placeholder="Nombre, código, RUC/DNI exacto, correo o celular" value="${state.q}" aria-label="Buscar clientes"></label>
      <select id="ver" aria-label="Verificación"><option value="">Toda verificación</option>${Object.entries(VER).map(([k, v]) => html`<option value="${k}" ${state.verification === k ? raw('selected') : ''}>${v[1]}</option>`)}</select></div><div id="list"></div></div>`);
  const load = async () => {
    const r = await get(`/clients?q=${encodeURIComponent(state.q)}&verification=${state.verification}&limit=200`);
    $('#list', main).innerHTML = String(html`<p class="count">${r.total} cliente(s)</p>${table([
      { label: 'Cliente', render: (c) => html`<a class="lnk" href="#/clientes/${c.id}">${c.display_name}</a><div class="t2">${c.code} · ${c.doc_type} ${c.doc_hint}</div>` },
      { label: 'Ciudad', render: (c) => c.city || '—' },
      { label: 'Verificación', render: (c) => pill(VER, c.verification) },
      { label: 'Licencias', cls: 'num', render: (c) => html`${c.live_licenses} <span class="t2">/ ${c.licenses}</span>` },
      { label: 'Saldo a favor', cls: 'num', render: (c) => (c.balance_cents ? money(c.balance_cents) : '—') },
      { label: 'Alta', render: (c) => fdate(c.created_at) },
    ], r.clients, { empty: state.q ? 'Sin resultados. Para buscar por documento, correo o celular escribe el dato completo.' : 'Aún no hay clientes.' })}`);
  };
  $('#q', main).addEventListener('input', debounce((e) => { state.q = e.target.value.trim(); load(); }, 300));
  $('#ver', main).onchange = (e) => { state.verification = e.target.value; load(); };
  if ($('#new', main)) $('#new', main).onclick = () => clientForm();
  await load();
}

export async function clientDetail(main, id) {
  const d = await get('/clients/' + id);
  const c = d.client;
  main.innerHTML = String(html`
    <a class="back" href="#/clientes">${icon('back')} Clientes</a>
    ${head(html`${c.display_name} <span class="code">${c.code}</span>`, html`${pill(VER, c.verification)} ${c.anonymized ? html`<span class="pill mute">Anonimizado</span>` : ''}`, c.anonymized ? '' : html`
      ${can('clients.edit') ? html`<button class="btn" id="edit">Editar</button>` : ''}${can('clients.verify') ? html`<button class="btn" id="verify">${icon('shield')} Verificar</button>` : ''}
      ${can('licenses.edit') ? html`<button class="btn pri" id="newlic">${icon('plus')} Nueva licencia</button>` : ''}`)}
    <div class="grid2">
      <section class="panel"><h2>Datos</h2>${c.anonymized ? html`<p class="t2">Los datos personales de este cliente fueron eliminados a pedido (derecho de supresión). Se conservan los registros contables.</p>` : html`
        <dl class="dl"><div><dt>Documento</dt><dd>${c.doc_type} ${c.doc_number}</dd></div><div><dt>Razón social</dt><dd>${c.legal_name || '—'}</dd></div>
        <div><dt>País fiscal</dt><dd>${countryName(c.country)}${c.region ? ' · ' + c.region : ''}</dd></div><div><dt>Impuesto que se le aplica</dt><dd>${c.tax ? html`${c.tax.label} · ${FISCAL[c.tax.fiscal_doc] || ''}<div class="t2">${c.tax.note}</div>` : '—'}</dd></div>
        <div><dt>Contacto</dt><dd>${c.contact_name || '—'}</dd></div><div><dt>Correo</dt><dd>${c.email || '—'}</dd></div>
        <div><dt>Celular</dt><dd>${c.phone ? html`<a class="lnk" href="https://wa.me/${c.phone}" target="_blank" rel="noopener noreferrer">${phoneFmt(c.phone)}</a>` : '—'}</dd></div><div><dt>Ciudad</dt><dd>${c.city || '—'}</dd></div>
        <div class="wide"><dt>Dirección</dt><dd>${c.address || '—'}</dd></div>${c.notes ? html`<div class="wide"><dt>Notas</dt><dd class="pre">${c.notes}</dd></div>` : ''}</dl>`}
      </section>
      <section class="panel"><h2>Cuenta</h2>
        <dl class="dl"><div><dt>Saldo a favor</dt><dd>${money(d.balance_cents)}</dd></div><div><dt>Pagado en total</dt><dd>${money(d.payments.filter((p) => p.status === 'aprobado').reduce((a, p) => a + p.amount_cents, 0))}</dd></div>
        <div><dt>Cobros abiertos</dt><dd>${d.invoices.filter((i) => ['pendiente', 'parcial'].includes(i.status)).length}</dd></div><div><dt>Cliente desde</dt><dd>${fdate(c.created_at)}</dd></div></dl>
        <div class="row-btns mt">${can('invoices.manage') && !c.anonymized ? html`<button class="btn sm" id="inv">${icon('card')} Cobro de otro servicio</button><button class="btn sm" id="credit">Ajustar saldo</button>` : ''}
        ${can('payments.register') ? html`<button class="btn sm" id="pay">Registrar pago</button>` : ''}
        ${can('clients.export') ? html`<button class="btn sm" id="export">${icon('download')} Exportar sus datos</button>` : ''}${can('clients.delete') && !c.anonymized ? html`<button class="btn sm danger" id="anon">Anonimizar</button>` : ''}</div>
      </section>
    </div>
    <section class="panel"><h2>Licencias</h2>${table([
      { label: 'Licencia', render: (l) => html`<a class="lnk" href="#/licencias/${l.id}">${l.label}</a><div class="t2">${l.code} · ${l.product.name} · ${l.plan.name}</div>` },
      { label: 'Estado', render: (l) => licPill(l) },
      { label: 'Vence', render: (l) => (l.period_end ? html`${fdate(l.period_end_local)}<div class="t2">${daysLabel(l.days_left)}</div>` : (l.status === 'pendiente' ? '—' : 'Sin vencimiento')) },
      { label: 'Cuota', cls: 'num', render: (l) => html`${money(l.price_cents)}<div class="t2">${cycle(l.interval_unit, l.interval_count)}</div>` },
    ], d.licenses, { empty: 'Sin licencias.' })}</section>
    <div class="grid2">
      <section class="panel"><h2>Cobros</h2>${table([
        { label: 'Cobro', render: (i) => html`<b>${i.number}</b><div class="t2">${i.description}</div>` },
        { label: 'Estado', render: (i) => html`${pill(INV, i.status)}${i.overdue ? html` <span class="pill bad">Vencido</span>` : ''}` },
        { label: 'Monto', cls: 'num', render: (i) => html`${money(i.amount_cents, i.currency)}<div class="t2">${taxLine(i)}</div>${i.remaining_cents && i.remaining_cents !== i.amount_cents && i.status !== 'anulada' ? html`<div class="t2">falta ${money(i.remaining_cents, i.currency)}</div>` : ''}` },
        { label: '', render: (i) => (i.pay_url ? html`<button class="btn sm" data-copy="${i.pay_url}">${icon('copy')} Enlace</button>` : '') },
      ], d.invoices.slice(0, 20), { empty: 'Sin cobros.' })}</section>
      <section class="panel"><h2>Pagos</h2>${table([
        { label: 'Pago', render: (p) => html`<b>${money(p.amount_cents, p.currency)}</b> · ${METHOD[p.method]}<div class="t2">${p.number || p.operation_ref || ''} · ${fdate(p.created_at)}${(p.documents || []).map((d) => ' · ' + d.doc)}</div>` },
        { label: 'Estado', render: (p) => pill(PAY, p.status) },
        { label: '', render: (p) => (p.status === 'por_verificar' && can('payments.approve') ? html`<button class="btn sm pri" data-ok="${p.id}">Aprobar</button>` : p.status === 'aprobado' && can('payments.reverse') ? html`<button class="btn sm" data-rev="${p.id}">Anular</button>` : '') },
      ], d.payments.slice(0, 20), { empty: 'Sin pagos.' })}</section>
    </div>
    <div class="grid2">
      <section class="panel"><h2>Contactos registrados ${can('clients.edit') && !c.anonymized ? html`<button class="btn sm right" id="contact">${icon('plus')} Registrar</button>` : ''}</h2>
        ${d.contacts.length ? html`<ul class="timeline">${d.contacts.map((x) => html`<li><b>${x.channel}</b> · <span class="t2">${x.user || '—'} · ${fdatetime(x.created_at)}</span><p class="pre">${x.note}</p></li>`)}</ul>` : html`<p class="empty-row">Sin contactos registrados.</p>`}</section>
      <section class="panel"><h2>Tickets de soporte</h2>${d.tickets.length ? html`<ul class="list compact">${d.tickets.map((t) => html`<li class="row"><span>${t.number} · ${t.subject}</span><span class="t2">${t.status}</span></li>`)}</ul>` : html`<p class="empty-row">Sin tickets.</p>`}
        ${d.credits.length ? html`<h2 class="mt">Movimientos de saldo</h2><ul class="list compact">${d.credits.map((x) => html`<li class="row"><span>${x.reason}</span><b class="${x.amount_cents < 0 ? 'neg' : 'pos'}">${money(x.amount_cents)}</b></li>`)}</ul>` : ''}</section>
    </div>`);
  const on = (sel, fn) => { const el = $(sel, main); if (el) el.onclick = fn; };
  on('#edit', () => clientForm(c));
  on('#verify', () => verifyForm(c));
  on('#newlic', () => licenseForm({ client: c }));
  on('#inv', () => invoiceForm({ client: c }));
  on('#pay', () => paymentForm({ invoices: d.invoices.filter((i) => ['pendiente', 'parcial'].includes(i.status)) }));
  on('#contact', () => form({ title: 'Registrar contacto', fields: [{ k: 'channel', label: 'Canal', type: 'select', options: ['WhatsApp', 'Llamada', 'Correo', 'Visita', 'Reunión'] }, { k: 'note', label: 'Qué se habló', type: 'textarea', required: true }], onSubmit: async (x) => { await post(`/clients/${c.id}/contacts`, x); closeModal(); toast('Contacto registrado.'); hooks.reload(); } }));
  on('#credit', () => form({ title: 'Ajustar saldo a favor', intro: html`<p class="intro">Positivo suma saldo (por ejemplo, una compensación); negativo lo descuenta. Se aplica solo al siguiente cobro.</p>`, fields: [{ k: 'amount', label: 'Monto (S/, puede ser negativo)', required: true }, { k: 'reason', label: 'Motivo', type: 'textarea', required: true, rows: 2 }], onSubmit: async (x) => { await post(`/clients/${c.id}/credit`, { amount: x.amount.replace(',', '.'), reason: x.reason }); closeModal(); toast('Saldo actualizado.'); hooks.reload(); } }));
  on('#export', async () => {
    try {
      const data = await get(`/clients/${c.id}/export`);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `cliente-${c.code}.json`; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      toast('Archivo descargado. Entrégalo solo al titular de los datos.');
    } catch (e) { toast(e.message, 'bad'); }
  });
  on('#anon', () => form({ title: 'Anonimizar cliente', danger: true, submit: 'Anonimizar definitivamente', intro: html`<p class="intro warnbox">${icon('alert')} Se borran de forma irreversible nombre de contacto, documento, correo, celular, dirección y notas. Se conservan montos y fechas de pagos (obligación contable). Solo es posible si todas sus licencias están canceladas.</p>`, fields: [], onSubmit: async () => { await post(`/clients/${c.id}/anonymize`); closeModal(); toast('Cliente anonimizado.'); hooks.reload(); } }));
  main.querySelectorAll('[data-ok]').forEach((b) => { b.onclick = () => approvePayment({ id: b.dataset.ok }); });
  main.querySelectorAll('[data-rev]').forEach((b) => { b.onclick = () => reversePayment(d.payments.find((p) => p.id === b.dataset.rev)); });
}

/* =========================================================== LICENCIAS */
export async function licenses(main) {
  const params = new URLSearchParams(location.hash.split('?')[1] || '');
  const state = { status: params.get('status') || '', product: '', q: '' };
  const chips = [['', 'Todas'], ['pendiente', 'Pendientes'], ['prueba', 'En prueba'], ['activa', 'Activas'], ['gracia', 'En gracia'], ['suspendida', 'Suspendidas'], ['cancelada', 'Canceladas']];
  main.innerHTML = String(html`${head('Licencias', 'El estado se calcula en tiempo real con las fechas: vencer, entrar en gracia, cortar y reactivar ocurre solo.', can('licenses.edit') ? html`<button class="btn pri" id="new">${icon('plus')} Nueva licencia</button>` : '')}
    <div class="panel"><div class="chips" role="tablist">${chips.map(([k, l]) => html`<button class="chip" role="tab" data-st="${k}" aria-selected="${state.status === k}">${l}</button>`)}</div>
    <div class="filters"><label class="search">${icon('search')}<input id="q" type="search" placeholder="Código, negocio, cliente o identificador" aria-label="Buscar licencias"></label>
      <select id="prod" aria-label="Producto"><option value="">Todos los productos</option>${S.lookups.products.map((p) => html`<option value="${p.id}">${p.name}</option>`)}</select></div><div id="list"></div></div>`);
  const load = async () => {
    const r = await get(`/licenses?status=${state.status}&product=${state.product}&q=${encodeURIComponent(state.q)}&limit=200`);
    $('#list', main).innerHTML = String(html`<p class="count">${r.total} licencia(s)</p>${table([
      { label: 'Licencia', render: (l) => html`<a class="lnk" href="#/licencias/${l.id}">${l.label}</a><div class="t2">${l.code} · <a class="t2" href="#/clientes/${l.client.id}">${l.client.name}</a></div>` },
      { label: 'Producto', render: (l) => html`${l.product.name}<div class="t2">${l.plan.name}${l.tenant_ref ? html` · <span class="code">${l.tenant_ref}</span>` : ''}</div>` },
      { label: 'Estado', render: (l) => licPill(l) },
      { label: 'Vence', render: (l) => (l.period_end ? html`${fdate(l.period_end_local)}<div class="t2 ${l.days_left < 0 ? 'neg' : l.days_left <= 7 ? 'warn-t' : ''}">${daysLabel(l.days_left)}</div>` : '—') },
      { label: 'Corte', render: (l) => (l.status === 'gracia' ? (l.cut_at ? fdatetime(l.cut_at) : html`<span class="t2">sin corte automático</span>`) : l.status === 'suspendida' ? html`<span class="t2">${l.suspension === 'manual' ? 'manual' : 'por falta de pago'}</span>` : '') },
      { label: 'Cuota', cls: 'num', render: (l) => (l.interval_unit === 'none' ? 'Pago único' : html`${money(l.price_cents)}<div class="t2">${cycle(l.interval_unit, l.interval_count)}</div>`) },
    ], r.licenses, { empty: 'No hay licencias con ese filtro.' })}`);
  };
  main.querySelectorAll('.chip').forEach((b) => { b.onclick = () => { state.status = b.dataset.st; main.querySelectorAll('.chip').forEach((x) => x.setAttribute('aria-selected', x === b)); load(); }; });
  $('#q', main).addEventListener('input', debounce((e) => { state.q = e.target.value.trim(); load(); }, 250));
  $('#prod', main).onchange = (e) => { state.product = e.target.value; load(); };
  if ($('#new', main)) $('#new', main).onclick = () => licenseForm();
  await load();
}

const STEPS = [['pendiente', 'Pendiente'], ['prueba', 'Prueba'], ['activa', 'Activa'], ['gracia', 'Gracia'], ['suspendida', 'Suspendida']];
export async function licenseDetail(main, id) {
  const d = await get('/licenses/' + id);
  const l = d.license, tp = d.token_preview;
  const live = ['prueba', 'activa', 'gracia'].includes(l.status);
  const open = d.invoices.filter((i) => ['pendiente', 'parcial'].includes(i.status));
  const tl = [...d.events.map((e) => ({ at: e.created_at, kind: 'estado', text: html`${e.from_status ? html`${e.from_status} → ` : ''}<b>${e.to_status}</b>`, note: e.reason, who: e.actor })),
    ...d.grants.map((g) => ({ at: g.created_at, kind: g.kind, text: g.kind === 'reverso' ? html`Reverso de vigencia` : html`Vigencia ${g.kind === 'pago' ? 'por pago' : g.kind === 'prueba' ? 'de prueba' : 'por ' + g.kind}`, note: html`${g.from_end ? fdatetime(g.from_end) + ' → ' : ''}${g.to_end ? fdatetime(g.to_end) : 'sin vencimiento'}${g.note ? ' · ' + g.note : ''}`, who: g.actor }))].sort((a, b) => (a.at < b.at ? 1 : -1));
  const canAct = can('licenses.suspend');
  main.innerHTML = String(html`
    <a class="back" href="#/licencias">${icon('back')} Licencias</a>
    ${head(html`${l.label} <span class="code">${l.code}</span>`, html`<a class="lnk" href="#/clientes/${l.client.id}">${l.client.name}</a> · ${l.product.name} · ${l.plan.name}`, html`
      ${l.status === 'pendiente' && can('licenses.edit') ? html`<button class="btn pri" data-a="activate">${icon('play')} Activar</button>` : ''}
      ${can('payments.register') && open.length ? html`<button class="btn pri" id="pay">${icon('card')} Registrar pago</button>` : ''}
      ${can('billing.view') && l.status !== 'cancelada' && l.interval_unit !== 'none' ? html`<button class="btn" id="link">${icon('send')} Enlace de pago</button>` : ''}
      ${can('licenses.edit') ? html`<button class="btn" id="edit">Editar</button>` : ''}`)}
    <section class="status-hero s-${l.status}">
      <div class="sh-main"><div>${licPill(l)} ${l.is_trial ? html`<span class="pill info">Prueba</span>` : ''}</div>
        <p class="sh-big">${l.status === 'pendiente' ? 'Aún no activada' : l.period_end ? html`${l.status === 'gracia' || l.status === 'suspendida' ? 'Venció el' : 'Pagada hasta el'} ${fdate(l.period_end_local)}` : 'Sin vencimiento'}</p>
        <p class="sh-sub">${l.period_end ? daysLabel(l.days_left) : ''}${l.status === 'gracia' && l.cut_at ? html` · <b>se corta el ${fdatetime(l.cut_at)}</b>` : ''}${l.status === 'suspendida' ? html` · ${l.suspension === 'manual' ? 'Suspensión manual: ' + (l.suspension_reason || '') : 'Se reactiva sola al registrarse el pago'}` : ''}${l.status === 'cancelada' ? html` · ${l.cancel_reason || ''}` : ''}</p></div>
      <ol class="flow">${STEPS.map(([k, t]) => html`<li class="${l.status === k ? 'on' : ''}">${t}</li>`)}</ol>
    </section>
    <div class="grid2">
      <section class="panel"><h2>Condiciones</h2><dl class="dl">
        <div><dt>Cuota</dt><dd>${l.interval_unit === 'none' ? 'Pago único' : html`${money(l.price_cents)} ${cycle(l.interval_unit, l.interval_count)}`}</dd></div>
        <div><dt>Gracia</dt><dd>${l.grace_days} día(s) ${l.is_trial ? html`<span class="t2">(no aplica en prueba)</span>` : ''}</dd></div>
        <div><dt>Corte automático</dt><dd>${l.auto_cut ? 'Sí' : 'No'}</dd></div><div><dt>Cobros automáticos</dt><dd>${l.auto_invoice ? 'Sí' : 'No'}</dd></div>
        <div><dt>Zona horaria</dt><dd>${l.timezone}</dd></div><div><dt>Activada</dt><dd>${l.activated_at ? fdate(l.activated_at) : '—'}</dd></div>
        <div class="wide"><dt>Funciones y límites</dt><dd>${Object.keys(l.features).length ? Object.entries(l.features).map(([k, v]) => html`<span class="code">${k}: ${v === -1 ? 'ilimitado' : v === true ? 'sí' : v === false ? 'no' : v}</span> `) : '—'}</dd></div></dl>
        ${canAct || can('invoices.manage') ? html`<div class="row-btns mt">
          ${can('invoices.manage') && l.status !== 'cancelada' && l.interval_unit !== 'none' ? html`<button class="btn sm" id="newinv">${icon('plus')} Emitir cobro</button><button class="btn sm" data-a="extend">Extender sin cobro</button>` : ''}
          ${canAct && l.status !== 'cancelada' ? (l.suspension === 'manual' ? html`<button class="btn sm" data-a="resume">${icon('play')} Levantar suspensión</button>` : html`<button class="btn sm" data-a="suspend">${icon('pause')} Suspender</button>`) : ''}
          ${canAct ? (l.status === 'cancelada' ? html`<button class="btn sm" data-a="reopen">Reabrir</button>` : html`<button class="btn sm danger" data-a="cancel">Dar de baja</button>`) : ''}</div>` : ''}
      </section>
      <section class="panel"><h2>Conexión con el sistema</h2><dl class="dl">
        <div><dt>Instancia</dt><dd>${d.instance ? html`${d.instance.name} <span class="t2">· visto ${ago(d.instance.last_seen_at)}</span>` : 'Ninguna'}</dd></div>
        <div><dt>Identificador</dt><dd>${l.tenant_ref ? html`<span class="code">${l.tenant_ref}</span>` : '—'}</dd></div>
        <div><dt>Quién cobra</dt><dd>${PROVIDER[l.billing_provider || 'hub']}${l.external_subscription_id ? html`<div class="t2">suscripción ${l.external_subscription_id}</div>` : ''}</dd></div>
        <div><dt>Precio</dt><dd>${l.tax_mode === 'mas_impuesto' ? 'sin impuesto (se suma)' : 'con IGV incluido'}</dd></div>
        ${l.product.kind === 'instalable' ? html`<div><dt>Clave</dt><dd><span class="code">${l.key_prefix}…</span></dd></div><div><dt>Equipos</dt><dd>${d.activations.filter((a) => !a.revoked_at).length} / ${l.max_activations}</dd></div>` : ''}</dl>
        <p class="t2 mt">Lo que recibe el sistema del cliente ahora (token firmado, vence ${fdatetime(new Date(tp.exp * 1000).toISOString())}):</p>
        <div class="tokenview"><span class="pill ${tp.mode === 'full' ? 'ok' : tp.mode === 'warning' ? 'warn' : tp.mode === 'blocked' ? 'info' : 'bad'}">modo: ${tp.mode}</span> <span class="t2">${tp.message || 'funcionamiento normal'}</span></div>
        <details><summary>Ver contenido del token</summary><pre class="out">${JSON.stringify(tp, null, 2)}</pre></details>
        <div class="row-btns mt">${can('licenses.edit') && l.instance_id ? html`<button class="btn sm" data-a="push">${icon('refresh')} Reenviar estado ahora</button>` : ''}${can('licenses.keys') && l.product.kind === 'instalable' ? html`<button class="btn sm" data-a="key">Regenerar clave</button>` : ''}</div>
        ${d.deliveries.length ? html`<h3 class="fsec">Últimos avisos a la instancia</h3><ul class="list compact">${d.deliveries.map((x) => html`<li class="row"><span>${pill({ entregado: ['ok', 'Entregado'], pendiente: ['warn', 'Pendiente'], fallido: ['bad', 'Fallido'], descartado: ['mute', 'Reemplazado'] }, x.status)} <span class="t2">${x.last_error || ''}</span></span><span class="t2">${ago(x.created_at)}</span></li>`)}</ul>` : ''}
        ${d.activations.length ? html`<h3 class="fsec">Equipos activados</h3><ul class="list compact">${d.activations.map((a) => html`<li class="row"><span>${a.label || 'Equipo'} <span class="t2">${a.ip || ''} · visto ${ago(a.last_seen_at)}</span></span>${a.revoked_at ? html`<span class="pill mute">Revocado</span>` : can('licenses.keys') ? html`<button class="btn sm" data-revoke="${a.id}">Revocar</button>` : ''}</li>`)}</ul>` : ''}
      </section>
    </div>
    <div class="grid2">
      <section class="panel"><h2>Cobros y pagos</h2>${table([
        { label: 'Cobro', render: (i) => html`<b>${i.number}</b><div class="t2">${i.description}</div>` },
        { label: 'Estado', render: (i) => html`${pill(INV, i.status)}${i.overdue ? html` <span class="pill bad">Vencido</span>` : ''}` },
        { label: 'Monto', cls: 'num', render: (i) => html`${money(i.amount_cents, i.currency)}<div class="t2">${taxLine(i)}</div>${i.credit_applied_cents ? html`<div class="t2">saldo aplicado ${money(i.credit_applied_cents)}</div>` : ''}${i.remaining_cents && i.remaining_cents !== i.amount_cents && i.status !== 'anulada' && i.status !== 'pagada' ? html`<div class="t2">falta ${money(i.remaining_cents)}</div>` : ''}` },
        { label: '', render: (i) => (i.pay_url ? html`<button class="btn sm" data-copy="${i.pay_url}">${icon('copy')} Enlace</button>` : '') },
      ], d.invoices, { empty: 'Sin cobros.' })}
      ${d.payments.length ? html`<h3 class="fsec">Pagos</h3>${table([
        { label: 'Pago', render: (p) => html`<b>${money(p.amount_cents, p.currency)}</b> · ${METHOD[p.method]}${p.provider && p.method === 'mor' ? ' · ' + p.provider : ''}<div class="t2">${p.number || ''} ${p.operation_ref ? '· op. ' + p.operation_ref : ''} ${p.card_label ? '· ' + p.card_label : ''}${(p.documents || []).map((d) => ' · ' + d.doc)}</div>` },
        { label: 'Estado', render: (p) => pill(PAY, p.status) }, { label: 'Fecha', render: (p) => fdate(p.created_at) },
        { label: '', render: (p) => (p.status === 'por_verificar' && can('payments.approve') ? html`<button class="btn sm pri" data-ok="${p.id}">Aprobar</button>` : p.status === 'aprobado' && can('payments.reverse') ? html`<button class="btn sm" data-rev="${p.id}">Anular</button>` : '') },
      ], d.payments)}` : ''}</section>
      <section class="panel"><h2>Historial</h2><ul class="timeline">${tl.map((x) => html`<li class="k-${x.kind}"><span>${x.text}</span> <span class="t2">· ${x.who} · ${fdatetime(x.at)}</span>${x.note ? html`<p class="t2">${x.note}</p>` : ''}</li>`)}</ul></section>
    </div>`);
  main.querySelectorAll('[data-a]').forEach((b) => { b.onclick = () => licenseAction(b.dataset.a, l); });
  const on = (sel, fn) => { const el = $(sel, main); if (el) el.onclick = fn; };
  on('#edit', () => editLicense(d));
  on('#pay', () => paymentForm({ invoices: open.map((i) => Object.assign({}, i, { client: { name: l.client.name } })) }));
  on('#link', () => sendLink(l));
  on('#newinv', () => invoiceForm({ license: l }));
  main.querySelectorAll('[data-ok]').forEach((b) => { b.onclick = () => approvePayment({ id: b.dataset.ok }); });
  main.querySelectorAll('[data-rev]').forEach((b) => { b.onclick = () => reversePayment(d.payments.find((p) => p.id === b.dataset.rev)); });
  main.querySelectorAll('[data-revoke]').forEach((b) => { b.onclick = async () => { await post(`/activations/${b.dataset.revoke}/revoke`); toast('Equipo revocado.'); hooks.reload(); }; });
  void payLinkBox; void copy;
}
