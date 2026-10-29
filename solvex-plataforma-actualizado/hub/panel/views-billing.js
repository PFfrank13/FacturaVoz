/* Vistas: Cobros y pagos, Finanzas. */
import { html, raw, $, $$, S, get, post, put, del, money, fdate, ago, pill, INV, PAY, METHOD, icon, table, bars, monthLabel, can, form, closeModal, toast, hooks, debounce, taxLine, CPE } from './core.js';
import { paymentForm, approvePayment, rejectPayment, reversePayment, payLinkBox, invoiceForm } from './actions.js';

const head = (title, sub, tools = '') => html`<div class="top"><div><h1>${title}</h1>${sub ? html`<p class="sub">${sub}</p>` : ''}</div><div class="tools">${tools}</div></div>`;

export async function billing(main) {
  const tabs = [['verificar', 'Por verificar'], ['cobros', 'Cobros'], ['pagos', 'Pagos'], ['comprobantes', 'Comprobantes'], ['avisos', 'Avisos enviados']];
  const cur = (location.hash.split('?')[1] || '').replace('tab=', '') || 'verificar';
  main.innerHTML = String(html`${head('Cobros y pagos', 'Cada cobro tiene un enlace de pago personal. Al aprobarse un pago, la licencia se extiende y se reactiva al instante.', can('payments.register') ? html`<button class="btn pri" id="reg">${icon('plus')} Registrar pago</button>` : '')}
    <div class="tabs" role="tablist">${tabs.map(([k, l]) => html`<a class="tab" role="tab" href="#/cobros?tab=${k}" aria-selected="${cur === k}">${l}${k === 'verificar' && S.kpis && S.kpis.pending_payments ? html` <em class="cnt">${S.kpis.pending_payments}</em>` : ''}${k === 'comprobantes' && S.kpis && S.kpis.fiscal_problems ? html` <em class="cnt">${S.kpis.fiscal_problems}</em>` : ''}</a>`)}</div><div id="tab"></div>`);
  const box = $('#tab', main);
  if ($('#reg', main)) $('#reg', main).onclick = async () => { const r = await get('/invoices?status=abiertas&limit=200'); paymentForm({ invoices: r.invoices }); };

  if (cur === 'verificar') {
    const r = await get('/payments?status=por_verificar&limit=200');
    box.innerHTML = String(html`${r.four_eyes ? html`<p class="banner">${icon('shield')} Control de cuatro ojos activo: quien registró un pago no puede aprobarlo.</p>` : ''}
      ${r.payments.length ? html`<div class="cards">${r.payments.map((p) => html`<article class="paycard">
        <div class="pc-top"><b class="amt">${money(p.amount_cents)}</b>${pill(PAY, p.status)}</div>
        <dl class="dl"><div><dt>Medio</dt><dd>${METHOD[p.method]}</dd></div><div><dt>N.º de operación</dt><dd>${p.operation_ref ? html`<span class="code">${p.operation_ref}</span>` : '—'}</dd></div>
          <div><dt>Fecha que indica</dt><dd>${p.paid_on ? fdate(p.paid_on) : '—'}</dd></div><div><dt>Origen</dt><dd>${p.source === 'cliente' ? 'Reportado por el cliente' : 'Registrado por ' + (p.created_by || '—')}</dd></div>
          <div class="wide"><dt>Cliente / cobro</dt><dd><a class="lnk" href="#/clientes/${p.client.id}">${p.client.name}</a> · ${p.invoice ? p.invoice.number + ' · ' + p.invoice.description : ''}</dd></div></dl>
        <p class="t2">${icon('alert')} Antes de aprobar, confirma en tu app del banco o Yape que el dinero llegó con ese número de operación.</p>
        ${can('payments.approve') ? html`<div class="row-btns"><button class="btn pri" data-ok="${p.id}">${icon('check')} Aprobar</button><button class="btn" data-no="${p.id}">Rechazar</button></div>` : ''}</article>`)}</div>` : html`<div class="empty"><h2>${icon('check')} Todo al día</h2><p>No hay pagos esperando verificación.</p></div>`}`);
    box.querySelectorAll('[data-ok]').forEach((b) => { b.onclick = () => approvePayment({ id: b.dataset.ok }); });
    box.querySelectorAll('[data-no]').forEach((b) => { b.onclick = () => rejectPayment(r.payments.find((p) => p.id === b.dataset.no)); });
    return;
  }
  if (cur === 'cobros') {
    const st = { status: 'abiertas', q: '' };
    box.innerHTML = String(html`<div class="panel"><div class="filters"><label class="search">${icon('search')}<input id="q" type="search" placeholder="N.º de cobro, descripción o cliente" aria-label="Buscar cobros"></label>
      <select id="st" aria-label="Estado"><option value="abiertas">Abiertos</option><option value="vencida">Vencidos</option><option value="pagada">Pagados</option><option value="anulada">Anulados</option><option value="">Todos</option></select></div><div id="list"></div></div>`);
    const load = async () => {
      const r = await get(`/invoices?status=${st.status}&q=${encodeURIComponent(st.q)}&limit=200`);
      $('#list', box).innerHTML = String(html`<p class="count">${r.total} cobro(s)</p>${table([
        { label: 'Cobro', render: (i) => html`<b>${i.number}</b><div class="t2">${i.description}</div>` },
        { label: 'Cliente', render: (i) => html`<a class="lnk" href="#/clientes/${i.client.id}">${i.client.name}</a>${i.license ? html`<div class="t2"><a href="#/licencias/${i.license.id}">${i.license.code}</a></div>` : ''}` },
        { label: 'Estado', render: (i) => html`${pill(INV, i.status)}${i.overdue ? html` <span class="pill bad">Vencido</span>` : ''}` },
        { label: 'Vence', render: (i) => fdate(i.due_at) },
        { label: 'Monto', cls: 'num', render: (i) => html`${money(i.amount_cents, i.currency)}<div class="t2">${taxLine(i)}</div>${i.status !== 'pagada' && i.status !== 'anulada' && i.remaining_cents !== i.amount_cents ? html`<div class="t2">falta ${money(i.remaining_cents, i.currency)}</div>` : ''}` },
        { label: '', render: (i) => html`<div class="row-btns">${i.pay_url ? html`<button class="btn sm" data-link="${i.id}">${icon('send')} Enlace</button>` : ''}${can('payments.register') && ['pendiente', 'parcial'].includes(i.status) ? html`<button class="btn sm" data-pay="${i.id}">Pago</button>` : ''}${can('invoices.manage') && i.status === 'pendiente' && !i.paid_cents ? html`<button class="btn sm ghost" data-void="${i.id}">Anular</button>` : ''}</div>` },
      ], r.invoices, { empty: 'Sin cobros con ese filtro.' })}`);
      $('#list', box).onclick = (e) => {
        const b = e.target.closest('button'); if (!b) return;
        const inv = r.invoices.find((x) => x.id === (b.dataset.link || b.dataset.pay || b.dataset.void));
        if (b.dataset.link) payLinkBox(inv);
        if (b.dataset.pay) paymentForm({ invoices: r.invoices.filter((x) => ['pendiente', 'parcial'].includes(x.status)), preselect: inv.id });
        if (b.dataset.void) form({ title: 'Anular ' + inv.number, danger: true, submit: 'Anular cobro', intro: html`<p class="intro">El enlace de pago deja de funcionar. Si se aplicó saldo a favor, se devuelve al cliente.</p>`, fields: [{ k: 'reason', label: 'Motivo', type: 'textarea', required: true, rows: 2 }], onSubmit: async (x) => { await post(`/invoices/${inv.id}/void`, x); closeModal(); toast('Cobro anulado.'); load(); } });
      };
    };
    $('#q', box).addEventListener('input', debounce((e) => { st.q = e.target.value.trim(); load(); }, 300));
    $('#st', box).onchange = (e) => { st.status = e.target.value; load(); };
    await load();
    return;
  }
  if (cur === 'pagos') {
    const r = await get('/payments?limit=200');
    box.innerHTML = String(html`<div class="panel">${table([
      { label: 'Pago', render: (p) => html`<b>${money(p.amount_cents, p.currency)}</b> · ${METHOD[p.method]}${p.method === 'mor' && p.provider ? ' · ' + p.provider : ''}<div class="t2">${p.number || 'sin recibo'} ${p.operation_ref ? '· op. ' + p.operation_ref : ''} ${p.card_label ? '· ' + p.card_label : ''}${(p.documents || []).map((d) => ' · ' + d.doc)}</div>` },
      { label: 'Cliente', render: (p) => html`<a class="lnk" href="#/clientes/${p.client.id}">${p.client.name}</a><div class="t2">${p.invoice ? p.invoice.number : ''}</div>` },
      { label: 'Estado', render: (p) => html`${pill(PAY, p.status)}${p.reject_reason || p.reverse_reason ? html`<div class="t2">${p.reject_reason || p.reverse_reason}</div>` : ''}` },
      { label: 'Revisó', render: (p) => html`${p.reviewed_by || '—'}<div class="t2">${p.reviewed_at ? ago(p.reviewed_at) : ''}</div>` },
      { label: 'Registrado', render: (p) => html`${fdate(p.created_at)}<div class="t2">${p.source === 'pasarela' ? 'pasarela' : p.source === 'cliente' ? 'cliente' : p.created_by || ''}</div>` },
      { label: '', render: (p) => (p.status === 'aprobado' && can('payments.reverse') ? html`<button class="btn sm" data-rev="${p.id}">Anular / reembolsar</button>` : '') },
    ], r.payments, { empty: 'Sin pagos.' })}</div>`);
    box.querySelectorAll('[data-rev]').forEach((b) => { b.onclick = () => reversePayment(r.payments.find((p) => p.id === b.dataset.rev)); });
    return;
  }
  if (cur === 'comprobantes') {
    const now = new Intl.DateTimeFormat('en-CA', { timeZone: S.tz }).format(new Date()).slice(0, 7);
    const st = { status: '', month: now };
    box.innerHTML = String(html`<div class="panel"><div class="filters">
      <select id="st" aria-label="Estado"><option value="">Todos</option><option value="problemas">Con error o rechazados</option><option value="pendiente">Por enviar</option><option value="enviado">Esperando a SUNAT</option><option value="aceptado">Aceptados</option></select>
      <input id="mo" type="month" value="${now}" aria-label="Mes">
      <a class="btn sm" id="csv" href="#" download>${icon('download')} Registro de ventas del mes (CSV)</a></div><div id="list"></div></div>`);
    const load = async () => {
      const r = await get(`/fiscal-documents?status=${st.status}&month=${st.month}&limit=200`);
      $('#csv', box).setAttribute('href', `/api/admin/sales-register?month=${st.month}`);
      $('#list', box).innerHTML = String(html`${!r.provider ? html`<div class="banner warn">${icon('alert')}<div><p><b>Sin proveedor de comprobantes.</b> Configura EINVOICE_PROVIDER=nubefact, NUBEFACT_URL y NUBEFACT_TOKEN en el .env del servidor.</p></div></div>`
        : !r.active ? html`<div class="banner warn">${icon('alert')}<div><p>La emisión automática está apagada. Actívala en Configuración → Impuestos y comprobantes.</p></div></div>`
        : r.provider === 'simulado' ? html`<div class="banner warn">${icon('alert')}<div><p>Proveedor SIMULADO: los comprobantes no van a SUNAT.</p></div></div>` : ''}
        <p class="count">${r.total} comprobante(s)</p>${table([
        { label: 'Comprobante', render: (d) => html`<b>${d.label} ${d.doc}</b><div class="t2">${d.issue_date ? fdate(d.issue_date) : 'sin enviar'}${d.related ? ' · modifica ' + d.related.doc : ''} · ${({ venta_interna: 'venta interna', exportacion: 'exportación', no_domiciliado: 'no domiciliado', nrus: 'Nuevo RUS' })[d.operation] || d.operation}</div>` },
        { label: 'Cliente', render: (d) => html`${d.customer_name}<div class="t2">${d.customer_doc} · ${d.invoice ? d.invoice.number : ''}</div>` },
        { label: 'Estado', render: (d) => html`${pill(CPE, d.status)}${d.last_error ? html`<div class="t2 neg">${d.last_error}</div>` : d.sunat_description ? html`<div class="t2">${d.sunat_description}</div>` : ''}` },
        { label: 'Importe', cls: 'num', render: (d) => html`${d.kind === 'nota_credito' ? '−' : ''}${money(d.total_cents, d.currency)}<div class="t2">base ${money(d.subtotal_cents, d.currency)} · IGV ${money(d.tax_cents, d.currency)}</div>` },
        { label: '', render: (d) => html`<div class="row-btns">${d.pdf_url || d.link ? html`<a class="btn sm" href="${d.pdf_url || d.link}" target="_blank" rel="noopener noreferrer">PDF</a>` : ''}${['error', 'pendiente'].includes(d.status) && can('payments.approve') ? html`<button class="btn sm" data-retry="${d.id}">Reintentar</button>` : ''}</div>` },
      ], r.documents, { empty: 'Sin comprobantes con ese filtro.' })}`);
      $('#list', box).querySelectorAll('[data-retry]').forEach((b) => { b.onclick = async () => { try { await post(`/fiscal-documents/${b.dataset.retry}/retry`); toast('Reintentando el envío.'); setTimeout(load, 1200); } catch (e) { toast(e.message, 'bad'); } }; });
    };
    $('#st', box).onchange = (e) => { st.status = e.target.value; load(); };
    $('#mo', box).onchange = (e) => { st.month = e.target.value || now; load(); };
    await load();
    return;
  }
  if (cur === 'avisos') {
    const r = await get('/notifications');
    const ch = r.channels;
    box.innerHTML = String(html`<div class="banner ${ch.email || ch.whatsapp ? '' : 'warn'}">${icon('send')}<div><p>Correo: <b>${ch.email ? 'configurado' : ch.emailLog ? 'modo prueba (solo consola)' : 'no configurado'}</b> · WhatsApp: <b>${ch.whatsapp ? 'configurado' : 'no configurado'}</b>.</p><p class="t2">Los avisos de recordatorio, gracia, corte, reactivación y pago se envían solos y se reintentan si fallan.</p></div></div>
      <div class="panel">${table([
        { label: 'Aviso', render: (n) => html`<b>${n.template.replace(/_/g, ' ')}</b><div class="t2">${n.channel === 'email' ? 'Correo' : 'WhatsApp'} · ${n.to_hint || ''}</div>` },
        { label: 'Cliente', render: (n) => html`${n.client || '—'}<div class="t2">${n.license || ''}</div>` },
        { label: 'Estado', render: (n) => html`${pill({ pendiente: ['warn', 'Pendiente'], enviado: ['ok', 'Enviado'], fallido: ['bad', 'Fallido'], omitido: ['mute', 'Omitido'] }, n.status)}${n.last_error ? html`<div class="t2">${n.last_error}</div>` : ''}` },
        { label: 'Fecha', render: (n) => ago(n.sent_at || n.created_at) },
        { label: '', render: (n) => (n.status === 'fallido' ? html`<button class="btn sm" data-retry="${n.id}">Reintentar</button>` : '') },
      ], r.notifications, { empty: 'Aún no se enviaron avisos.' })}</div>`);
    box.querySelectorAll('[data-retry]').forEach((b) => { b.onclick = async () => { await post(`/notifications/${b.dataset.retry}/retry`); toast('Reintentando.'); hooks.reload(); }; });
  }
  void invoiceForm; void put;
}

/* =========================================================== FINANZAS */
export async function finance(main) {
  const [f, ex] = await Promise.all([get('/finance'), can('expenses.manage') ? get('/expenses') : Promise.resolve({ expenses: [] })]);
  const months = []; { const d = new Date(); for (let i = 11; i >= 0; i--) { const x = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - i, 1)); months.push(x.toISOString().slice(0, 7)); } }
  const series = months.map((m) => ({ month: m, income_cents: f.income_by_month[m] || 0, expense_cents: f.expense_by_month[m] || 0 }));
  const tot = (o) => Object.values(o).reduce((a, b) => a + b, 0);
  const inc12 = series.reduce((a, s) => a + s.income_cents, 0), exp12 = series.reduce((a, s) => a + s.expense_cents, 0);
  main.innerHTML = String(html`${head('Finanzas', 'Ingresos en soles aprobados (con IGV) y gastos. El IGV y la base de cada mes salen de los comprobantes emitidos.', can('expenses.manage') ? html`<button class="btn pri" id="newx">${icon('plus')} Registrar gasto</button>` : '')}
    <div class="kpis"><div class="kpi"><span class="l">Ingresos 12 meses</span><b class="v">${money(inc12)}</b></div><div class="kpi"><span class="l">Gastos 12 meses</span><b class="v">${money(exp12)}</b></div>
      <div class="kpi ${inc12 - exp12 < 0 ? 'bad' : ''}"><span class="l">Resultado</span><b class="v">${money(inc12 - exp12)}</b></div><div class="kpi"><span class="l">Saldos a favor de clientes</span><b class="v">${money(f.credits_total)}</b><span class="n">dinero recibido aún no aplicado</span></div></div>
    ${Object.keys(f.tax_by_month || {}).length ? html`<section class="panel"><h2>Ventas según comprobantes <span>base imponible e IGV por mes (las notas de crédito restan)</span></h2>${table([
      { label: 'Mes', render: (x) => monthLabel(x[0]) }, { label: 'Base', cls: 'num', render: (x) => money(x[1].base) }, { label: 'IGV', cls: 'num', render: (x) => money(x[1].igv) }, { label: 'Total', cls: 'num', render: (x) => money(x[1].base + x[1].igv) },
      { label: '', render: (x) => html`<a class="btn sm" href="/api/admin/sales-register?month=${x[0]}" download>${icon('download')} CSV</a>` },
    ], Object.entries(f.tax_by_month).sort((a, b) => (a[0] < b[0] ? 1 : -1)))}</section>` : ''}
    ${(f.mor_income || []).length ? html`<section class="panel"><h2>Cobrado por Merchant of Record <span>en su moneda; el impuesto lo declara el MoR</span></h2><dl class="dl">${f.mor_income.map((m) => html`<div><dt>${m.currency}</dt><dd>${money(m.c, m.currency)} · ${m.n} pago(s)</dd></div>`)}</dl></section>` : ''}
    <section class="panel"><h2>Ingresos y gastos por mes</h2>${bars(series, { keys: ['income_cents', 'expense_cents'], colors: ['b-ok', 'b-mute'], labels: ['Ingresos', 'Gastos'], labelOf: (x) => monthLabel(x.month), height: 200 })}<div class="legend"><span><i class="dot b-ok"></i>Ingresos</span><span><i class="dot b-mute"></i>Gastos</span></div></section>
    <div class="grid2"><section class="panel"><h2>Ingresos por producto</h2>${Object.entries(f.income_by_product).sort((a, b) => b[1] - a[1]).map(([k, v]) => html`<div class="hbar"><span>${k}</span><div class="bar"><i data-w="${Math.round((v / Math.max(1, tot(f.income_by_product))) * 100)}"></i></div><b>${money(v)}</b></div>`)}</section>
      <section class="panel"><h2>Ingresos por medio de pago</h2>${Object.entries(f.income_by_method).sort((a, b) => b[1] - a[1]).map(([k, v]) => html`<div class="hbar"><span>${METHOD[k] || k}</span><div class="bar"><i data-w="${Math.round((v / Math.max(1, tot(f.income_by_method))) * 100)}"></i></div><b>${money(v)}</b></div>`)}</section></div>
    ${can('expenses.manage') ? html`<section class="panel"><h2>Gastos</h2>${table([
      { label: 'Concepto', render: (e) => html`<b>${e.concept}</b><div class="t2">${e.category}${e.product_name ? ' · ' + e.product_name : ''}${e.license_code ? ' · ' + e.license_code : ''}</div>` },
      { label: 'Fecha', render: (e) => fdate(e.spent_on) }, { label: 'Monto', cls: 'num', render: (e) => money(e.amount_cents) },
      { label: '', render: (e) => html`<div class="row-btns"><button class="btn sm" data-ed="${e.id}">Editar</button><button class="btn sm ghost" data-del="${e.id}">Eliminar</button></div>` },
    ], ex.expenses, { empty: 'Sin gastos registrados.' })}</section>` : ''}`);
  $$('.bar i[data-w]', main).forEach((i) => { i.style.width = i.getAttribute('data-w') + '%'; });
  const expForm = (e = {}) => form({ title: e.id ? 'Editar gasto' : 'Registrar gasto', fields: [
    { k: 'concept', label: 'Concepto', required: true, value: e.concept }, { k: 'category', label: 'Categoría', type: 'select', options: ['Infraestructura', 'Comunicación', 'Marketing', 'Sueldos', 'Herramientas', 'Impuestos', 'Otros'], value: e.category, half: true },
    { k: 'amount', label: 'Monto', type: 'money', required: true, value: e.amount_cents ? (e.amount_cents / 100).toFixed(2) : '', half: true },
    { k: 'spent_on', label: 'Fecha', type: 'date', required: true, value: e.spent_on || new Intl.DateTimeFormat('en-CA', { timeZone: S.tz }).format(new Date()), half: true },
    { k: 'product_id', label: 'Producto (para rentabilidad)', type: 'select', options: [['', 'General']].concat(S.lookups.products.map((p) => [p.id, p.name])), value: e.product_id || '', half: true }],
  onSubmit: async (x) => { const b = Object.assign({}, x, { amount: x.amount.replace(',', '.'), product_id: x.product_id || undefined }); if (e.id) await put('/expenses/' + e.id, b); else await post('/expenses', b); closeModal(); toast('Gasto guardado.'); hooks.reload(); } });
  if ($('#newx', main)) $('#newx', main).onclick = () => expForm();
  main.querySelectorAll('[data-ed]').forEach((b) => { b.onclick = () => expForm(ex.expenses.find((e) => e.id === b.dataset.ed)); });
  main.querySelectorAll('[data-del]').forEach((b) => { b.onclick = async () => { await del('/expenses/' + b.dataset.del); toast('Gasto eliminado.'); hooks.reload(); }; });
  void raw;
}
