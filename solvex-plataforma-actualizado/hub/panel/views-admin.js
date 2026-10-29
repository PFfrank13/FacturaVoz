/* Vistas: Productos y planes, Integraciones, Solicitudes, Soporte, Reclamaciones, Equipo, Auditoría, Configuración, Mi cuenta. */
import { html, raw, $, $$, S, get, post, put, money, soles, fdate, fdatetime, ago, cycle, pill, icon, table, can, form, confirmBox, closeModal, toast, hooks, secretBox, modal, debounce, go, countryName, COUNTRIES } from './core.js';
import { clientForm } from './actions.js';

const head = (title, sub, tools = '') => html`<div class="top"><div><h1>${title}</h1>${sub ? html`<p class="sub">${sub}</p>` : ''}</div><div class="tools">${tools}</div></div>`;
const KIND = { saas: 'En la nube (multi-negocio)', instalable: 'Instalable con clave', a_medida: 'A medida' };
const PSTATUS = { activo: ['ok', 'Activo'], borrador: ['info', 'En preparación'], retirado: ['mute', 'Retirado'] };

/* =========================================================== PRODUCTOS */
export async function products(main) {
  const r = await get('/products');
  const manage = can('products.manage');
  main.innerHTML = String(html`${head('Productos y planes', 'Cada sistema que vende Solvex es un producto independiente con sus propios planes. Agregar un producto nuevo no requiere programar el panel.', manage ? html`<button class="btn pri" id="newp">${icon('plus')} Nuevo producto</button>` : '')}
    ${r.products.map((p) => html`<section class="panel product">
      <div class="ph"><div><h2>${p.name} <span class="code">${p.code}</span></h2><p class="t2">${KIND[p.kind]} · ${p.licenses} licencia(s) vigentes · ${p.instances} instancia(s) ${p.public ? '· visible en la web' : ''}</p></div>
        <div class="row-btns">${pill(PSTATUS, p.status)}${manage ? html`<button class="btn sm" data-ep="${p.id}">Editar</button><button class="btn sm pri" data-np="${p.id}">${icon('plus')} Plan</button>` : ''}</div></div>
      ${p.feature_keys.length ? html`<p class="t2">Funciones controladas: ${p.feature_keys.map((k) => html`<span class="code">${k}</span> `)}</p>` : ''}
      ${table([
        { label: 'Plan', render: (x) => html`<b>${x.name}</b> <span class="code">${x.code}</span>${x.active ? '' : html` <span class="pill mute">Inactivo</span>`}${x.public ? html` <span class="pill info">Web</span>` : ''}` },
        { label: 'Precio', cls: 'num', render: (x) => html`${money(x.price_cents)}<div class="t2">${cycle(x.interval_unit, x.interval_count)} · ${x.tax_mode === 'mas_impuesto' ? '+ IGV' : 'IGV incluido'}</div>` },
        { label: 'Prueba · gracia', render: (x) => html`${x.trial_days ? x.trial_days + ' d' : 'sin prueba'} · ${x.grace_days} d` },
        { label: 'Funciones', render: (x) => Object.entries(x.features).map(([k, v]) => html`<span class="code">${k}: ${v === -1 ? '∞' : v === true ? 'sí' : v === false ? 'no' : v}</span> `) },
        { label: '', render: (x) => (manage ? html`<button class="btn sm" data-epl="${x.id}">Editar</button>` : '') },
      ], p.plans, { empty: 'Sin planes. Crea al menos uno para vender este producto.' })}</section>`)}
    ${r.products.length ? '' : html`<div class="empty"><h2>Aún no hay productos</h2><p>Crea "Sistema de Barbería" y sus planes (mensual, anual...) para empezar a emitir licencias.</p></div>`}`);
  const prodForm = (p = null) => form({ title: p ? 'Editar producto' : 'Nuevo producto', fields: [
    { k: 'code', label: 'Código', required: true, value: p ? p.code : '', half: true, attrs: p ? 'disabled' : 'maxlength="30"', help: 'MAYÚSCULAS, sin espacios. Ej. BARBERIA. No se cambia después.' },
    { k: 'name', label: 'Nombre', required: true, value: p && p.name, half: true },
    { k: 'kind', label: 'Tipo', type: 'select', options: Object.entries(KIND), value: p ? p.kind : 'saas', help: 'En la nube: Solvex lo aloja y muchos negocios comparten una instancia. Instalable: corre en el equipo del cliente y se activa con clave. A medida: proyectos especiales.' },
    { k: 'status', label: 'Estado', type: 'select', options: Object.entries(PSTATUS).map(([k, v]) => [k, v[1]]), value: p ? p.status : 'activo', half: true },
    { k: 'feature_keys', label: 'Funciones controladas (separadas por coma)', value: p ? p.feature_keys.join(', ') : '', half: true, placeholder: 'max_branches, max_barbers' },
    { k: 'description', label: 'Descripción', type: 'textarea', value: p && p.description },
    { k: 'public', label: 'Mostrar en el catálogo de la web', type: 'checkbox', value: p ? p.public : false }],
  onSubmit: async (x) => { const b = Object.assign({}, x, { code: (p ? p.code : x.code).toUpperCase(), feature_keys: x.feature_keys.split(',').map((s) => s.trim()).filter(Boolean) }); if (p) await put('/products/' + p.id, b); else await post('/products', b); closeModal(); toast('Producto guardado.'); hooks.reload(); refreshLookups(); } });
  const planForm = (p, x = null) => {
    const keys = p.feature_keys;
    form({ title: (x ? 'Editar plan' : 'Nuevo plan') + ' · ' + p.name, wide: true, intro: x ? html`<p class="intro">Cambiar el precio no afecta a las licencias existentes (conservan su precio). Para cambiar el periodo, crea un plan nuevo.</p>` : '', fields: [
      { k: 'code', label: 'Código', required: true, value: x ? x.code : '', half: true, attrs: x ? 'disabled' : '', help: 'Ej. MENSUAL, ANUAL' }, { k: 'name', label: 'Nombre', required: true, value: x && x.name, half: true },
      { k: 'interval_unit', label: 'Cobro', type: 'select', options: [['month', 'Por meses'], ['year', 'Por años'], ['day', 'Por días'], ['none', 'Pago único (licencia perpetua)']], value: x ? x.interval_unit : 'month', half: true },
      { k: 'interval_count', label: 'Cada cuántos', type: 'number', value: x ? x.interval_count : 1, half: true, help: '1 = mensual/anual · 3 = trimestral · 6 = semestral' },
      { k: 'price', label: 'Precio por ciclo', type: 'money', required: true, value: x ? soles(x.price_cents) : '', half: true },
      { k: 'tax_mode', label: 'El precio…', type: 'select', options: [['incluido', 'ya incluye IGV (lo que paga un cliente del Perú)'], ['mas_impuesto', 'es sin IGV (el impuesto se suma)']], value: x ? x.tax_mode : 'incluido', half: true,
        help: 'A un cliente del extranjero con exportación se le cobra solo el valor de venta (sin IGV).' }, { k: 'setup', label: 'Implementación (se suma al primer cobro)', type: 'money', value: x ? soles(x.setup_cents) : '0', half: true },
      { k: 'trial_days', label: 'Días de prueba', type: 'number', value: x ? x.trial_days : 0, half: true }, { k: 'grace_days', label: 'Días de gracia antes del corte', type: 'number', value: x ? x.grace_days : 5, half: true },
      ...keys.map((k) => ({ k: 'ft_' + k, label: k + ' (número, -1 = ilimitado, o sí/no)', value: x && x.features[k] != null ? String(x.features[k]) : '', half: true })),
      { k: 'public', label: 'Mostrar en la web', type: 'checkbox', value: x ? x.public : false }, { k: 'active', label: 'Activo (disponible para licencias nuevas)', type: 'checkbox', value: x ? x.active : true }],
    onSubmit: async (v) => {
      const features = {}; for (const k of keys) { const s = (v['ft_' + k] || '').trim().toLowerCase(); if (!s) continue; features[k] = s === 'sí' || s === 'si' || s === 'true' ? true : s === 'no' || s === 'false' ? false : Number(s); if (Number.isNaN(features[k])) throw Object.assign(new Error('Valor no válido para ' + k), { field: 'ft_' + k }); }
      const b = { code: (x ? x.code : v.code).toUpperCase(), name: v.name, interval_unit: v.interval_unit, interval_count: v.interval_count || 1, price: v.price.replace(',', '.'), setup: (v.setup || '0').replace(',', '.'), trial_days: v.trial_days || 0, grace_days: v.grace_days ?? 5, features, public: v.public, active: v.active, tax_mode: v.tax_mode };
      if (x) await put('/plans/' + x.id, b); else await post(`/products/${p.id}/plans`, b);
      closeModal(); toast('Plan guardado.'); hooks.reload(); refreshLookups();
    } });
  };
  if ($('#newp', main)) $('#newp', main).onclick = () => prodForm();
  main.querySelectorAll('[data-ep]').forEach((b) => { b.onclick = () => prodForm(r.products.find((p) => p.id === b.dataset.ep)); });
  main.querySelectorAll('[data-np]').forEach((b) => { b.onclick = () => planForm(r.products.find((p) => p.id === b.dataset.np)); });
  main.querySelectorAll('[data-epl]').forEach((b) => { const p = r.products.find((pp) => pp.plans.some((x) => x.id === b.dataset.epl)); b.onclick = () => planForm(p, p.plans.find((x) => x.id === b.dataset.epl)); });
}
async function refreshLookups() { try { S.lookups = await get('/lookups'); } catch (_) { /* nada */ } }

/* =========================================================== INTEGRACIONES */
export async function integrations(main) {
  const [r, dl] = await Promise.all([get('/instances'), get('/deliveries')]);
  const manage = can('instances.manage');
  const k = r.keys.find((x) => x.active);
  main.innerHTML = String(html`${head('Integraciones', 'Cada instalación de un producto (por ejemplo, la barbería en producción) es una instancia. Recibe el estado de sus licencias al instante por webhook firmado, y además lo consulta cada 5 minutos por si acaso.', manage ? html`<button class="btn pri" id="newi">${icon('plus')} Nueva instancia</button>` : '')}
    <div class="grid2"><section class="panel"><h2>Llave pública de licencias</h2><p class="t2">Va dentro de cada sistema para verificar que las respuestas vienen del Hub. No es secreta.</p>
      <dl class="dl"><div><dt>Id de llave (kid)</dt><dd><span class="code">${k.kid}</span></dd></div><div class="wide"><dt>Formato libsodium (PHP)</dt><dd><span class="code wrap">${k.raw_b64}</span> <button class="btn sm" data-copy="${k.raw_b64}">${icon('copy')}</button></dd></div></dl>
      <details><summary>PEM y llaves de rotación</summary><pre class="out">${r.keys.map((x) => `# ${x.kid}${x.active ? ' (activa)' : ' (anunciada)'}\n${x.pem}`).join('\n')}</pre></details>
      <p class="t2">Endpoint público: <span class="code">${r.hub_url}/.well-known/solvex-license-keys.json</span></p></section>
    <section class="panel"><h2>Cómo se conecta un producto</h2><ol class="steps-list">
      <li>Crea la instancia aquí y copia la <b>clave de API</b> y el <b>secreto del webhook</b> (se muestran una sola vez).</li>
      <li>En el sistema (por ejemplo la barbería en Laravel) pon en <span class="code">.env</span>: <span class="code">SOLVEX_HUB_URL</span>, <span class="code">SOLVEX_INSTANCE_ID</span>, <span class="code">SOLVEX_API_KEY</span>, <span class="code">SOLVEX_WEBHOOK_SECRET</span>, <span class="code">SOLVEX_PUBLIC_KEY</span>.</li>
      <li>Al crear cada licencia, elige la instancia y el identificador del negocio (el slug de la barbería).</li>
      <li>Prueba con "Enviar ping" y revisa que el aviso quede "Entregado".</li></ol><p class="t2">Guía completa: docs/03-integracion-productos.md</p></section></div>
    <section class="panel"><h2>Instancias</h2>${table([
      { label: 'Instancia', render: (i) => html`<b>${i.name}</b> ${pill({ activa: ['ok', 'Activa'], pausada: ['warn', 'Pausada'], revocada: ['mute', 'Revocada'] }, i.status)}<div class="t2">${i.product.name} · ${i.environment} · ${i.licenses} licencia(s)</div>` },
      { label: 'Conexión', render: (i) => html`${i.last_seen_at ? html`Visto ${ago(i.last_seen_at)}` : html`<span class="t2">Nunca se conectó</span>`}<div class="t2">${i.app_version ? 'v' + i.app_version : ''} ${i.last_seen_ip || ''}</div>` },
      { label: 'Webhook', render: (i) => html`${i.webhook_url ? html`<span class="code wrap">${i.webhook_url}</span>` : html`<span class="t2">sin webhook (solo consulta)</span>`}<div class="t2">${i.deliveries.ok || 0} entregados · <span class="${i.deliveries.failed ? 'neg' : ''}">${i.deliveries.failed || 0} fallidos</span> · ${i.deliveries.pending || 0} en cola</div>` },
      { label: 'Id · clave', render: (i) => html`<span class="code">${i.id}</span> <button class="btn sm ghost" data-copy="${i.id}" aria-label="Copiar id">${icon('copy')}</button><div class="t2">${i.api_key_prefix}…</div>` },
      { label: '', render: (i) => (manage && i.status !== 'revocada' ? html`<div class="row-btns"><button class="btn sm" data-ping="${i.id}">Enviar ping</button><button class="btn sm" data-sync="${i.id}">Reenviar todo</button><button class="btn sm" data-edit="${i.id}">Editar</button><button class="btn sm" data-rot="${i.id}">Rotar secretos</button></div>` : '') },
    ], r.instances, { empty: 'Sin instancias. Crea una por cada despliegue de un producto (producción y pruebas por separado).' })}</section>
    <section class="panel"><h2>Avisos enviados a las instancias <span>reintentos automáticos hasta ~28 h</span></h2>${table([
      { label: 'Evento', render: (x) => html`<b>${x.topic}</b><div class="t2">${x.license_code ? x.license_code + ' · ' + (x.label || '') : ''}</div>` },
      { label: 'Instancia', render: (x) => x.instance_name },
      { label: 'Estado', render: (x) => html`${pill({ entregado: ['ok', 'Entregado'], pendiente: ['warn', 'En cola'], fallido: ['bad', 'Fallido'], descartado: ['mute', 'Reemplazado'] }, x.status)}<div class="t2">${x.attempts} intento(s) ${x.last_status ? '· HTTP ' + x.last_status : ''} ${x.last_error || ''}</div>` },
      { label: 'Creado', render: (x) => ago(x.created_at) },
      { label: '', render: (x) => (manage && ['fallido', 'pendiente'].includes(x.status) ? html`<button class="btn sm" data-retry="${x.id}">Reintentar</button>` : '') },
    ], dl.deliveries.slice(0, 50), { empty: 'Sin avisos todavía.' })}</section>`);
  const instForm = (i = null) => form({ title: i ? 'Editar instancia' : 'Nueva instancia', wide: true, fields: [
    i ? { type: 'html', html: html`<p class="pre">Producto: <b>${i.product.name}</b></p>` } : { k: 'product_id', label: 'Producto', type: 'select', options: S.lookups.products.map((p) => [p.id, p.name]) },
    { k: 'name', label: 'Nombre', required: true, value: i && i.name, placeholder: 'Barbería SaaS · producción', half: true },
    { k: 'environment', label: 'Entorno', type: 'select', options: [['produccion', 'Producción'], ['pruebas', 'Pruebas']], value: i && i.environment, half: true },
    { k: 'webhook_url', label: 'URL del webhook', value: i && i.webhook_url, placeholder: 'https://app.solvex.pe/solvex/webhook', help: 'Debe ser https y pública. El Hub firma cada aviso.' },
    { k: 'allowed_ips', label: 'IPs permitidas para consultar (opcional)', value: i && i.allowed_ips, placeholder: '203.0.113.10, 198.51.100.0/24', help: 'Si la clave de API se filtrara, solo serviría desde estas IPs.' },
    ...(i ? [{ k: 'status', label: 'Estado', type: 'select', options: [['activa', 'Activa'], ['pausada', 'Pausada (no recibe avisos ni consulta)'], ['revocada', 'Revocada (definitivo)']], value: i.status }] : [])],
  onSubmit: async (x) => {
    if (i) { await put('/instances/' + i.id, Object.assign(x, { product_id: i.product_id, webhook_url: x.webhook_url || undefined, allowed_ips: x.allowed_ips || '' })); closeModal(); toast('Instancia actualizada.'); hooks.reload(); return; }
    const res = await post('/instances', Object.assign(x, { webhook_url: x.webhook_url || undefined }));
    closeModal(); secretBox('Credenciales de ' + res.instance.name, [['SOLVEX_INSTANCE_ID', res.instance.id], ['SOLVEX_API_KEY', res.apiKey], ['SOLVEX_WEBHOOK_SECRET', res.webhookSecret]], 'Pégalas en el .env del sistema. No se vuelven a mostrar: si se pierden, se rotan.');
    refreshLookups(); hooks.reload();
  } });
  if ($('#newi', main)) $('#newi', main).onclick = () => instForm();
  main.onclick = async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    const inst = r.instances.find((x) => x.id === (b.dataset.edit || b.dataset.rot || b.dataset.ping || b.dataset.sync));
    try {
      if (b.dataset.edit) instForm(inst);
      if (b.dataset.ping) { await post(`/instances/${inst.id}/ping`); toast('Ping enviado. Revisa el estado en unos segundos.'); setTimeout(() => hooks.reload(), 2500); }
      if (b.dataset.sync) { const x = await post(`/instances/${inst.id}/resync`); toast(`Se reenvió el estado de ${x.queued} licencia(s).`); }
      if (b.dataset.retry) { await post(`/deliveries/${b.dataset.retry}/retry`); toast('Reintentando.'); setTimeout(() => hooks.reload(), 1500); }
      if (b.dataset.rot) form({ title: 'Rotar secretos de ' + inst.name, intro: html`<p class="intro warnbox">${icon('alert')} El secreto anterior deja de funcionar al instante. Ten listo el .env del sistema para actualizarlo.</p>`, fields: [{ k: 'what', label: 'Qué rotar', type: 'select', options: [['api_key', 'Clave de API (consultas)'], ['webhook_secret', 'Secreto del webhook (firma)']] }], submit: 'Rotar', danger: true, onSubmit: async (x) => { const res = await post(`/instances/${inst.id}/rotate`, x); closeModal(); secretBox('Nuevo secreto', [[x.what === 'api_key' ? 'SOLVEX_API_KEY' : 'SOLVEX_WEBHOOK_SECRET', res.apiKey || res.webhookSecret]]); } });
    } catch (err) { toast(err.message, 'bad'); }
  };
}

/* =========================================================== SOLICITUDES */
const LEAD = { nuevo: ['info', 'Nuevo'], contactado: ['warn', 'Contactado'], demo: ['warn', 'Demo'], cotizado: ['warn', 'Cotizado'], ganado: ['ok', 'Ganado'], perdido: ['mute', 'Perdido'], spam: ['mute', 'Spam'] };
export async function leads(main) {
  const r = await get('/leads');
  const cols = ['nuevo', 'contactado', 'demo', 'cotizado', 'ganado', 'perdido'];
  main.innerHTML = String(html`${head('Solicitudes', 'Llegan desde el formulario de la web. Cada una se guarda cifrada.')}
    <div class="kanban">${cols.map((c) => html`<section class="kcol"><h2>${LEAD[c][1]} <span>${r.leads.filter((l) => l.status === c).length}</span></h2>${r.leads.filter((l) => l.status === c).map((l) => html`<article class="kcard">
      <b>${l.business || l.name || 'Sin nombre'}</b><p class="t2">${l.name} · ${l.sector || ''} · ${l.branches || ''}</p>${l.message ? html`<p class="msg">${l.message}</p>` : ''}
      <p class="t2">${l.contact} · ${ago(l.created_at)}</p>
      <div class="row-btns"><select data-st="${l.id}" aria-label="Estado">${Object.entries(LEAD).map(([k, v]) => html`<option value="${k}" ${k === l.status ? raw('selected') : ''}>${v[1]}</option>`)}</select>
      ${/^\+?[\d\s-]{9,}$/.test(l.contact) ? html`<a class="btn sm" target="_blank" rel="noopener noreferrer" href="https://wa.me/${(l.contact.replace(/\D/g, '').length === 9 ? '51' : '') + l.contact.replace(/\D/g, '')}">${icon('wa')}</a>` : ''}
      ${!l.client_id && can('clients.edit') ? html`<button class="btn sm" data-conv="${l.id}">Convertir en cliente</button>` : l.client_id ? html`<a class="btn sm" href="#/clientes/${l.client_id}">Ver cliente</a>` : ''}</div></article>`)}</section>`)}</div>`);
  main.querySelectorAll('[data-st]').forEach((s) => { s.onchange = async () => { await put('/leads/' + s.dataset.st, { status: s.value }); toast('Estado actualizado.'); hooks.reload(); hooks.counts(); }; });
  main.querySelectorAll('[data-conv]').forEach((b) => { b.onclick = () => { const l = r.leads.find((x) => x.id === b.dataset.conv); const isMail = l.contact.includes('@');
    clientForm(null, { display_name: l.business, contact_name: l.name, email: isMail ? l.contact : '', phone: isMail ? '' : l.contact.replace(/\D/g, ''), notes: l.message, onCreated: async (c) => { await put('/leads/' + l.id, { status: 'ganado', client_id: c.id }); go('#/clientes/' + c.id); } }); }; });
}

/* =========================================================== SOPORTE */
const TK = { abierto: ['warn', 'Abierto'], en_curso: ['info', 'En curso'], resuelto: ['ok', 'Resuelto'], cerrado: ['mute', 'Cerrado'] };
const PR = { alta: ['bad', 'Alta'], media: ['warn', 'Media'], baja: ['mute', 'Baja'] };
export async function tickets(main) {
  const r = await get('/tickets?status=abiertos'), all = await get('/tickets');
  main.innerHTML = String(html`${head('Soporte', 'Cada consulta con responsable, prioridad e historial.', html`<button class="btn pri" id="newt">${icon('plus')} Nuevo ticket</button>`)}
    <section class="panel"><h2>Abiertos y en curso</h2>${tt(r.tickets)}</section><section class="panel"><h2>Todos</h2>${tt(all.tickets.filter((t) => !['abierto', 'en_curso'].includes(t.status)))}</section>`);
  function tt(list) { return table([
    { label: 'Ticket', render: (t) => html`<a class="lnk" href="#" data-open="${t.id}">${t.subject}</a><div class="t2">${t.number} · ${t.client ? t.client.name : 'sin cliente'}${t.license ? ' · ' + t.license.code : ''}</div>` },
    { label: 'Prioridad', render: (t) => pill(PR, t.priority) }, { label: 'Estado', render: (t) => pill(TK, t.status) },
    { label: 'Responsable', render: (t) => (t.assignee ? t.assignee.name : '—') }, { label: 'Abierto', render: (t) => ago(t.created_at) },
  ], list, { empty: 'Nada por aquí.' }); }
  $('#newt', main).onclick = async () => {
    const cl = (await get('/clients-lite')).clients;
    form({ title: 'Nuevo ticket', fields: [{ k: 'subject', label: 'Asunto', required: true }, { k: 'client_id', label: 'Cliente', type: 'select', options: [['', 'Sin cliente']].concat(cl.map((c) => [c.id, c.name])) },
      { k: 'priority', label: 'Prioridad', type: 'select', options: [['media', 'Media'], ['alta', 'Alta'], ['baja', 'Baja']], half: true }, { k: 'assignee_id', label: 'Responsable', type: 'select', options: [['', 'Sin asignar']].concat(S.lookups.users.map((u) => [u.id, u.name])), half: true },
      { k: 'note', label: 'Detalle', type: 'textarea' }],
    onSubmit: async (x) => { for (const k of ['client_id', 'assignee_id', 'note']) if (!x[k]) delete x[k]; await post('/tickets', x); closeModal(); toast('Ticket creado.'); hooks.reload(); hooks.counts(); } });
  };
  main.onclick = async (e) => {
    const a = e.target.closest('[data-open]'); if (!a) return; e.preventDefault();
    const d = await get('/tickets/' + a.dataset.open), t = d.ticket;
    form({ title: t.number + ' · ' + t.subject, wide: true, intro: html`<ul class="timeline">${d.notes.map((n) => html`<li><b>${n.user || '—'}</b> <span class="t2">${fdatetime(n.created_at)}</span><p class="pre">${n.body}</p></li>`)}</ul>`, fields: [
      { k: 'status', label: 'Estado', type: 'select', options: Object.entries(TK).map(([k, v]) => [k, v[1]]), value: t.status, half: true }, { k: 'priority', label: 'Prioridad', type: 'select', options: Object.entries(PR).map(([k, v]) => [k, v[1]]), value: t.priority, half: true },
      { k: 'assignee_id', label: 'Responsable', type: 'select', options: [['', 'Sin asignar']].concat(S.lookups.users.map((u) => [u.id, u.name])), value: t.assignee_id || '' }, { k: 'note', label: 'Agregar nota', type: 'textarea' }],
    onSubmit: async (x) => { if (!x.assignee_id) delete x.assignee_id; if (!x.note) delete x.note; await put('/tickets/' + t.id, x); closeModal(); toast('Ticket actualizado.'); hooks.reload(); hooks.counts(); } });
  };
}

/* =========================================================== RECLAMACIONES */
export async function complaints(main) {
  const r = await get('/complaints');
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: S.tz }).format(new Date());
  main.innerHTML = String(html`${head('Libro de Reclamaciones', 'Obligatorio para vender por internet en Perú. Plazo de respuesta: 15 días hábiles. La respuesta enviada no se modifica.')}
    <section class="panel">${table([
      { label: 'N.º', render: (c) => html`<a class="lnk" href="#" data-open="${c.id}">${c.number}</a><div class="t2">${c.kind} · ${c.good_type}</div>` },
      { label: 'Consumidor', render: (c) => c.consumer_name },
      { label: 'Estado', render: (c) => pill({ recibido: ['warn', 'Recibido'], en_revision: ['info', 'En revisión'], respondido: ['ok', 'Respondido'] }, c.status) },
      { label: 'Responder hasta', render: (c) => html`${fdate(c.due_on)}${c.status !== 'respondido' && c.due_on < today ? html` <span class="pill bad">Fuera de plazo</span>` : ''}` },
      { label: 'Recibido', render: (c) => fdate(c.created_at) },
    ], r.complaints, { empty: 'Sin reclamos registrados.' })}</section>`);
  main.onclick = async (e) => {
    const a = e.target.closest('[data-open]'); if (!a) return; e.preventDefault();
    const c = (await get('/complaints/' + a.dataset.open)).complaint;
    const info = html`<dl class="dl"><div><dt>Consumidor</dt><dd>${c.consumer.name}</dd></div><div><dt>Documento</dt><dd>${c.consumer.doc_type} ${c.consumer.doc_number}</dd></div><div><dt>Correo</dt><dd>${c.consumer.email}</dd></div><div><dt>Teléfono</dt><dd>${c.consumer.phone || '—'}</dd></div><div class="wide"><dt>Dirección</dt><dd>${c.consumer.address}</dd></div>${c.amount_cents ? html`<div><dt>Monto reclamado</dt><dd>${money(c.amount_cents)}</dd></div>` : ''}<div class="wide"><dt>Detalle</dt><dd class="pre">${c.description}</dd></div><div class="wide"><dt>Pedido</dt><dd class="pre">${c.request}</dd></div></dl>`;
    if (c.status === 'respondido') { modal(String(html`<h2>${c.kind} ${c.number}</h2>${info}<h3 class="fsec">Respuesta enviada</h3><p class="pre">${c.response}</p><div class="acts"><button class="btn pri" data-close>Cerrar</button></div>`)); $('#modal [data-close]').onclick = closeModal; return; }
    form({ title: `${c.kind} ${c.number}`, wide: true, intro: info, submit: 'Enviar respuesta', fields: [{ k: 'response', label: 'Respuesta al consumidor (se envía por correo y no se puede editar)', type: 'textarea', rows: 6, required: true }],
      onSubmit: async (x) => { await post(`/complaints/${c.id}/respond`, x); closeModal(); toast('Respuesta enviada.'); hooks.reload(); hooks.counts(); } });
  };
}

/* =========================================================== EQUIPO */
export async function team(main) {
  const r = await get('/team');
  const manage = can('team.manage');
  main.innerHTML = String(html`${head('Equipo y accesos', 'Cada persona con su cuenta y su rol. Doble factor obligatorio para todos.', manage ? html`<button class="btn pri" id="newu">${icon('plus')} Invitar persona</button>` : '')}
    <section class="panel">${table([
      { label: 'Persona', render: (u) => html`<b>${u.name}</b>${u.id === S.me.id ? html` <span class="pill info">Tú</span>` : ''}<div class="t2">${u.email}</div>` },
      { label: 'Rol', render: (u) => u.roleLabel },
      { label: 'Seguridad', render: (u) => html`${u.totpEnabled ? html`<span class="pill ok">2FA activo</span>` : html`<span class="pill warn">2FA pendiente</span>`}${u.mustChangePassword ? html` <span class="pill warn">Contraseña temporal</span>` : ''}${u.lockedUntil && u.lockedUntil > new Date().toISOString() ? html` <span class="pill bad">Bloqueado</span>` : ''}` },
      { label: 'Último acceso', render: (u) => (u.lastLoginAt ? ago(u.lastLoginAt) : 'nunca') },
      { label: 'Estado', render: (u) => (u.active ? html`<span class="pill ok">Activo</span>` : html`<span class="pill mute">Desactivado</span>`) },
      { label: '', render: (u) => (manage ? html`<div class="row-btns"><button class="btn sm" data-ed="${u.id}">Editar</button><button class="btn sm" data-rs="${u.id}">Restablecer</button></div>` : '') },
    ], r.users)}</section>
    <section class="panel"><h2>Qué puede hacer cada rol</h2><div class="tablewrap"><table class="matrix"><thead><tr><th>Permiso</th>${r.roles.map((x) => html`<th>${x.label}</th>`)}</tr></thead><tbody>
      ${[...new Set(r.roles.flatMap((x) => x.perms))].filter((p) => p !== '*').concat(['team.manage']).filter((v, i, a) => a.indexOf(v) === i).map((p) => html`<tr><td>${PERM[p] || p}</td>${r.roles.map((x) => html`<td>${x.perms.includes('*') || x.perms.includes(p) ? icon('check', 'ok') : ''}</td>`)}</tr>`)}</tbody></table></div></section>`);
  if ($('#newu', main)) $('#newu', main).onclick = () => form({ title: 'Invitar persona', intro: html`<p class="intro">Se genera una contraseña temporal. Al entrar deberá cambiarla y activar el doble factor.</p>`, fields: [{ k: 'name', label: 'Nombre', required: true }, { k: 'email', label: 'Correo', type: 'email', required: true }, { k: 'role', label: 'Rol', type: 'select', options: r.roles.map((x) => [x.key, x.label]), value: 'soporte' }],
    onSubmit: async (x) => { const res = await post('/team', x); closeModal(); secretBox('Acceso de ' + res.user.name, [['Correo', res.user.email], ['Contraseña temporal', res.tempPassword]], 'Envíala por un canal distinto al correo (por ejemplo, en persona o por llamada).'); hooks.reload(); } });
  main.querySelectorAll('[data-ed]').forEach((b) => { const u = r.users.find((x) => x.id === b.dataset.ed); b.onclick = () => form({ title: 'Editar ' + u.name, fields: [{ k: 'name', label: 'Nombre', value: u.name, required: true }, { k: 'role', label: 'Rol', type: 'select', options: r.roles.map((x) => [x.key, x.label]), value: u.role }, { k: 'active', label: 'Cuenta activa', type: 'checkbox', value: u.active, help: 'Desactivar cierra todas sus sesiones al instante.' }], onSubmit: async (x) => { await put('/team/' + u.id, x); closeModal(); toast('Guardado.'); hooks.reload(); } }); });
  main.querySelectorAll('[data-rs]').forEach((b) => { const u = r.users.find((x) => x.id === b.dataset.rs); b.onclick = () => form({ title: 'Restablecer acceso de ' + u.name, fields: [{ k: 'what', label: 'Qué hacer', type: 'select', options: [['unlock', 'Desbloquear (tras intentos fallidos)'], ['password', 'Nueva contraseña temporal'], ['2fa', 'Reiniciar doble factor (perdió el celular)']] }], submit: 'Aplicar', onSubmit: async (x) => { const res = await post(`/team/${u.id}/reset`, x); closeModal(); if (res.tempPassword) secretBox('Contraseña temporal', [['Contraseña', res.tempPassword]]); else toast('Listo. Se cerraron sus sesiones.'); hooks.reload(); } }); });
}
const PERM = { 'dashboard.view': 'Ver tablero', 'clients.view': 'Ver clientes', 'clients.edit': 'Crear/editar clientes', 'clients.verify': 'Verificar clientes', 'clients.delete': 'Anonimizar clientes', 'clients.export': 'Exportar datos de un cliente', 'licenses.view': 'Ver licencias', 'licenses.edit': 'Crear/editar licencias', 'licenses.suspend': 'Suspender, cancelar, reabrir', 'licenses.keys': 'Claves y equipos', 'billing.view': 'Ver cobros', 'payments.register': 'Registrar pagos', 'payments.approve': 'Aprobar/rechazar pagos', 'payments.reverse': 'Anular/reembolsar pagos', 'invoices.manage': 'Cobros, cortesías y saldos', 'products.manage': 'Productos y planes', 'instances.manage': 'Integraciones', 'leads.manage': 'Solicitudes', 'tickets.manage': 'Soporte', 'expenses.manage': 'Gastos', 'complaints.manage': 'Libro de reclamaciones', 'audit.view': 'Auditoría', 'settings.manage': 'Configuración', 'team.manage': 'Equipo y roles' };

/* =========================================================== AUDITORÍA */
export async function audit(main) {
  const st = { q: '', offset: 0 };
  main.innerHTML = String(html`${head('Auditoría', 'Quién hizo qué y cuándo. Cada registro está encadenado al anterior con una firma: si alguien lo altera, la verificación lo detecta.', html`<button class="btn pri" id="ver">${icon('shield')} Verificar integridad</button>`)}
    <div id="vres"></div><section class="panel"><div class="filters"><label class="search">${icon('search')}<input id="q" type="search" placeholder="Acción, persona o dato" aria-label="Buscar en auditoría"></label></div><div id="list"></div></section>`);
  const load = async () => {
    const r = await get(`/audit?q=${encodeURIComponent(st.q)}&limit=100&offset=${st.offset}`);
    $('#list', main).innerHTML = String(html`<p class="count">${r.total} registro(s)</p>${table([
      { label: '#', cls: 'num', render: (a) => a.seq }, { label: 'Cuándo', render: (a) => fdatetime(a.at) },
      { label: 'Quién', render: (a) => html`${a.actor_label || '—'}<div class="t2">${a.actor_type}${a.ip ? ' · ' + a.ip : ''}</div>` },
      { label: 'Acción', render: (a) => html`<span class="code">${a.action}</span>` }, { label: 'Sobre', render: (a) => (a.entity_type ? html`${a.entity_type} <span class="t2">${a.entity_id || ''}</span>` : '—') },
      { label: 'Detalle', render: (a) => (a.data ? html`<span class="t2 mono">${a.data.length > 140 ? a.data.slice(0, 140) + '…' : a.data}</span>` : '') },
    ], r.rows)}<div class="row-btns mt">${st.offset ? html`<button class="btn sm" id="prev">Anteriores</button>` : ''}${st.offset + 100 < r.total ? html`<button class="btn sm" id="next">Más antiguos</button>` : ''}</div>`);
    if ($('#prev', main)) $('#prev', main).onclick = () => { st.offset = Math.max(0, st.offset - 100); load(); };
    if ($('#next', main)) $('#next', main).onclick = () => { st.offset += 100; load(); };
  };
  $('#q', main).addEventListener('input', debounce((e) => { st.q = e.target.value.trim(); st.offset = 0; load(); }, 300));
  $('#ver', main).onclick = async () => { const v = await post('/audit/verify'); $('#vres', main).innerHTML = String(v.ok ? html`<div class="banner ok">${icon('check')} Bitácora íntegra: ${v.count} registros verificados. Cabeza: <span class="code">${v.head.slice(0, 24)}…</span></div>` : html`<div class="banner bad">${icon('alert')} ALTERACIÓN DETECTADA en el registro ${v.brokenAt}: ${v.reason}. Sigue el plan de respuesta a incidentes.</div>`); };
  await load();
}

/* =========================================================== CONFIGURACIÓN */
export async function settings(main) {
  const [r, sys, tr] = await Promise.all([get('/settings'), get('/system'), get('/tax-rules')]);
  const s = r.settings, pi = s.payment_instructions, co = s.company, edit = can('settings.manage'), tx = s.tax, ei = s.einvoice;
  const REGIME = { nrus: 'Nuevo RUS (no cobra IGV, solo boletas)', rer: 'Régimen Especial (RER)', mype: 'Régimen MYPE Tributario', general: 'Régimen General' };
  main.innerHTML = String(html`${head('Configuración', 'Reglas de cobro, datos de la empresa e instrucciones de pago que ve el cliente.')}
    ${sys.warnings.length ? html`<div class="banner warn">${icon('alert')}<div>${sys.warnings.map((w) => html`<p>${w}</p>`)}</div></div>` : ''}
    <div class="grid2">
      <section class="panel"><h2>Reglas de cobro y corte ${edit ? html`<button class="btn sm right" id="e1">Editar</button>` : ''}</h2><dl class="dl">
        <div><dt>Emitir cobro de renovación</dt><dd>${s.renewal_notice_days} días antes del vencimiento</dd></div><div><dt>Recordatorios</dt><dd>${s.reminders_days.join(', ')} días antes</dd></div>
        <div><dt>Al pagar una licencia cortada</dt><dd>${s.restore_anchor === 'fecha_pago' ? 'El ciclo nuevo empieza el día del pago' : 'Continúa desde el vencimiento anterior'}</dd></div>
        <div><dt>Control de cuatro ojos</dt><dd>${s.four_eyes ? 'Sí: quien registra no aprueba' : 'No'}</dd></div><div><dt>El cliente reporta su pago</dt><dd>${s.allow_client_reports ? 'Sí, desde su enlace' : 'No'}</dd></div>
        <div><dt>Plazo de reclamos</dt><dd>${s.complaint_days} días hábiles</dd></div></dl></section>
      <section class="panel"><h2>Instrucciones de pago ${edit ? html`<button class="btn sm right" id="e2">Editar</button>` : ''}</h2><dl class="dl">
        <div><dt>Yape</dt><dd>${pi.yape_number || '—'} ${pi.yape_holder ? '· ' + pi.yape_holder : ''}</dd></div><div><dt>Plin</dt><dd>${pi.plin_number || '—'} ${pi.plin_holder ? '· ' + pi.plin_holder : ''}</dd></div>
        <div class="wide"><dt>Cuentas</dt><dd>${(pi.bank_accounts || []).map((a) => html`<p>${a.bank} (${a.currency}) ${a.account}${a.cci ? ' · CCI ' + a.cci : ''} · ${a.holder}</p>`)}${(pi.bank_accounts || []).length ? '' : '—'}</dd></div><div class="wide"><dt>Nota</dt><dd>${pi.note}</dd></div></dl></section>
    </div>
    <div class="grid2">
      <section class="panel"><h2>Impuestos ${edit ? html`<button class="btn sm right" id="e4">Editar</button>` : ''}</h2><dl class="dl">
        <div><dt>Régimen de Solvex</dt><dd>${REGIME[tx.regime] || tx.regime}</dd></div>
        <div><dt>Registro de Exportadores de Servicios</dt><dd>${tx.export_registered ? 'Inscrito: clientes del extranjero al 0 % (exportación)' : html`<span class="neg">No inscrito</span>: a clientes del extranjero se les cobra IGV`}</dd></div></dl>
        <h3 class="fsec">Tasas por país ${edit ? html`<button class="btn sm right" id="e6">${icon('plus')} Nueva tasa</button>` : ''}</h3>
        ${table([
          { label: 'País', render: (x) => html`${countryName(x.country)}${x.region ? ' · ' + x.region : ''}<div class="t2">${x.code}${x.customer_kind !== 'todos' ? ' · ' + x.customer_kind : ''}</div>` },
          { label: 'Tasa', cls: 'num', render: (x) => html`<b>${(x.rate_bp / 100).toLocaleString('es-PE')} %</b><div class="t2">${x.label}</div>` },
          { label: 'Vigencia', render: (x) => html`desde ${fdate(x.valid_from)}${x.valid_to ? html`<div class="t2">hasta ${fdate(x.valid_to)}</div>` : html`<div class="t2">vigente</div>`}` },
        ], tr.rules)}
        <p class="t2 mt">Una tasa de otro país significa que Solvex está inscrito para cobrar ese impuesto allí. Sin ella, el cliente del extranjero va como exportación (o con IGV si no estás inscrito). Para vender en muchos países sin inscribirte en cada uno, usa un Merchant of Record.</p></section>
      <section class="panel"><h2>Comprobantes electrónicos ${edit ? html`<button class="btn sm right" id="e5">Editar</button>` : ''}</h2><dl class="dl">
        <div><dt>Proveedor (OSE/PSE)</dt><dd>${sys.einvoice_provider || html`<span class="neg">no configurado</span>`}</dd></div>
        <div><dt>Emisión automática</dt><dd>${ei.enabled ? 'Activa: una boleta o factura por cada pago aprobado' : 'Apagada'}</dd></div>
        <div><dt>Series</dt><dd>Factura ${ei.series_factura} · Boleta ${ei.series_boleta}<div class="t2">Notas de crédito ${ei.series_nc_factura} · ${ei.series_nc_boleta}</div></dd></div>
        <div><dt>Enviar el PDF al cliente</dt><dd>${ei.send_to_client ? 'Sí, a su correo' : 'No'}</dd></div>
        <div><dt>Merchant of Record</dt><dd>${(sys.mor || []).length ? sys.mor.join(', ') : 'ninguno configurado'}<div class="t2">Webhook: ${sys.hub_url}/webhooks/mor/&lt;proveedor&gt;</div></dd></div></dl>
        <p class="t2 mt">El token del proveedor y los secretos de los MoR se configuran en el .env del servidor, nunca aquí.</p></section>
    </div>
    <div class="grid2">
      <section class="panel"><h2>Empresa ${edit ? html`<button class="btn sm right" id="e3">Editar</button>` : ''}</h2><dl class="dl"><div><dt>Nombre</dt><dd>${co.name}</dd></div><div><dt>Razón social</dt><dd>${co.legal_name || '—'}</dd></div><div><dt>RUC</dt><dd>${co.ruc || '—'}</dd></div><div><dt>Correo</dt><dd>${co.email || '—'}</dd></div><div><dt>Teléfono</dt><dd>${co.phone || '—'}</dd></div><div><dt>Web</dt><dd>${co.website || '—'}</dd></div></dl></section>
      <section class="panel"><h2>Sistema</h2><dl class="dl"><div><dt>Versión</dt><dd>${sys.version}${sys.dev ? ' · DESARROLLO' : ''}</dd></div><div><dt>Zona horaria</dt><dd>${sys.timezone}</dd></div>
        <div><dt>Pasarela</dt><dd>${sys.gateway || 'ninguna'}</dd></div><div><dt>Correo · WhatsApp</dt><dd>${sys.channels.email ? 'sí' : sys.channels.emailLog ? 'prueba' : 'no'} · ${sys.channels.whatsapp ? 'sí' : 'no'}</dd></div>
        <div><dt>Llave de firma</dt><dd><span class="code">${sys.signing_kid}</span></dd></div><div><dt>Último respaldo</dt><dd>${sys.last_backup ? fdatetime(sys.last_backup.at) : html`<span class="neg">nunca</span>`}</dd></div></dl>
        <p class="t2 mt">Los secretos (llaves, Culqi, correo) se cambian en el archivo .env del servidor, nunca desde el panel.</p></section>
    </div>`);
  const save = async (b) => { await put('/settings', b); closeModal(); toast('Configuración guardada.'); hooks.reload(); };
  const on = (id, fn) => { const e = $(id, main); if (e) e.onclick = fn; };
  on('#e1', () => form({ title: 'Reglas de cobro y corte', fields: [
    { k: 'renewal_notice_days', label: 'Emitir el cobro de renovación (días antes)', type: 'number', value: s.renewal_notice_days, half: true }, { k: 'reminders_days', label: 'Recordatorios (días antes, separados por coma)', value: s.reminders_days.join(', '), half: true },
    { k: 'restore_anchor', label: 'Al pagar una licencia ya cortada', type: 'select', options: [['fecha_pago', 'El ciclo nuevo empieza el día del pago (recomendado)'], ['continuar', 'Continuar desde el vencimiento anterior (cobra los días cortados)']], value: s.restore_anchor },
    { k: 'four_eyes', label: 'Cuatro ojos: quien registra un pago manual no puede aprobarlo', type: 'checkbox', value: s.four_eyes, help: 'Recomendado cuando hay 2 o más personas con permiso de aprobar.' },
    { k: 'allow_client_reports', label: 'Permitir que el cliente reporte su Yape/transferencia desde el enlace', type: 'checkbox', value: s.allow_client_reports },
    { k: 'complaint_days', label: 'Plazo del Libro de Reclamaciones (días hábiles)', type: 'number', value: s.complaint_days }],
  onSubmit: (x) => save(Object.assign({}, x, { reminders_days: x.reminders_days.split(',').map((v) => Number(v.trim())).filter((n) => n > 0) })) }));
  on('#e2', () => form({ title: 'Instrucciones de pago', wide: true, fields: [
    { k: 'yape_number', label: 'Yape (celular)', value: pi.yape_number, half: true }, { k: 'yape_holder', label: 'Titular Yape', value: pi.yape_holder, half: true },
    { k: 'plin_number', label: 'Plin (celular)', value: pi.plin_number, half: true }, { k: 'plin_holder', label: 'Titular Plin', value: pi.plin_holder, half: true },
    { k: 'banks', label: 'Cuentas (una por línea: Banco | Moneda | Cuenta | CCI | Titular)', type: 'textarea', rows: 4, value: (pi.bank_accounts || []).map((a) => [a.bank, a.currency, a.account, a.cci || '', a.holder].join(' | ')).join('\n') },
    { k: 'note', label: 'Nota para el cliente', type: 'textarea', rows: 2, value: pi.note }],
  onSubmit: (x) => save({ payment_instructions: { yape_number: x.yape_number, yape_holder: x.yape_holder, plin_number: x.plin_number, plin_holder: x.plin_holder, note: x.note,
    bank_accounts: x.banks.split('\n').map((l) => l.split('|').map((v) => v.trim())).filter((p) => p.length >= 5 && p[0]).map((p) => ({ bank: p[0], currency: p[1] || 'PEN', account: p[2], cci: p[3], holder: p[4] })) } }) }));
  on('#e4', () => form({ title: 'Impuestos', intro: html`<p class="intro">Confírmalo con tu contador. Al guardar, los cobros que aún no recibieron pagos se recalculan cuando el cliente abre su enlace.</p>`, fields: [
    { k: 'regime', label: 'Régimen tributario de Solvex', type: 'select', options: Object.entries(REGIME), value: tx.regime },
    { k: 'export_registered', label: 'Solvex está inscrito en el Registro de Exportadores de Servicios de SUNAT', type: 'checkbox', value: tx.export_registered, help: 'Solo así un servicio a un cliente del extranjero califica como exportación (0 % de IGV).' }],
  onSubmit: (x) => save({ tax: x }) }));
  on('#e5', () => form({ title: 'Comprobantes electrónicos', wide: true, fields: [
    { k: 'enabled', label: 'Emitir boleta o factura automáticamente por cada pago aprobado', type: 'checkbox', value: ei.enabled, help: sys.einvoice_provider ? 'Proveedor: ' + sys.einvoice_provider : 'Primero configura el proveedor en el .env del servidor.' },
    { k: 'series_factura', label: 'Serie de facturas', value: ei.series_factura, half: true, help: 'Empieza con F, 4 caracteres.' }, { k: 'series_boleta', label: 'Serie de boletas', value: ei.series_boleta, half: true, help: 'Empieza con B.' },
    { k: 'series_nc_factura', label: 'Notas de crédito de facturas', value: ei.series_nc_factura, half: true }, { k: 'series_nc_boleta', label: 'Notas de crédito de boletas', value: ei.series_nc_boleta, half: true },
    { k: 'send_to_client', label: 'Que el proveedor envíe el PDF al correo del cliente', type: 'checkbox', value: ei.send_to_client }],
  onSubmit: (x) => save({ einvoice: Object.assign({}, x, { series_factura: x.series_factura.toUpperCase(), series_boleta: x.series_boleta.toUpperCase(), series_nc_factura: x.series_nc_factura.toUpperCase(), series_nc_boleta: x.series_nc_boleta.toUpperCase() }) }) }));
  on('#e6', () => form({ title: 'Nueva tasa de impuesto', intro: html`<p class="intro">Si cambia el IGV, crea la nueva tasa con su fecha de inicio: la anterior se cierra sola el día previo y los cobros ya emitidos no cambian.</p>`, fields: [
    { k: 'country', label: 'País', type: 'select', options: COUNTRIES, value: 'PE', half: true }, { k: 'region', label: 'Estado/provincia (opcional)', half: true },
    { k: 'code', label: 'Código', required: true, placeholder: 'PE-IGV, CL-IVA…', half: true }, { k: 'label', label: 'Nombre en el comprobante', required: true, placeholder: 'IGV, IVA, VAT', half: true },
    { k: 'rate', label: 'Tasa (%)', required: true, placeholder: '18', half: true }, { k: 'valid_from', label: 'Vigente desde', type: 'date', required: true, half: true },
    { k: 'customer_kind', label: 'Aplica a', type: 'select', options: [['todos', 'Todos'], ['empresa', 'Solo empresas'], ['persona', 'Solo personas']], half: true },
    { k: 'note', label: 'Base legal o nota', type: 'textarea', rows: 2 }],
  onSubmit: async (x) => { if (!x.region) delete x.region; await post('/tax-rules', x); closeModal(); toast('Tasa guardada.'); hooks.reload(); } }));
  on('#e3', () => form({ title: 'Datos de la empresa', fields: [{ k: 'name', label: 'Nombre comercial', value: co.name, required: true }, { k: 'legal_name', label: 'Razón social', value: co.legal_name }, { k: 'ruc', label: 'RUC', value: co.ruc, half: true }, { k: 'phone', label: 'Teléfono', value: co.phone, half: true }, { k: 'email', label: 'Correo', value: co.email, half: true }, { k: 'website', label: 'Web', value: co.website, half: true }, { k: 'address', label: 'Dirección', value: co.address }],
    onSubmit: (x) => save({ company: x }) }));
}

/* =========================================================== MI CUENTA */
export async function account(main) {
  const r = await get('/auth/sessions');
  main.innerHTML = String(html`${head('Mi cuenta', S.me.email + ' · ' + S.me.roleLabel)}
    <div class="grid2"><section class="panel"><h2>Seguridad</h2><div class="row-btns"><button class="btn" id="pw">Cambiar contraseña</button><button class="btn" id="rc">Nuevos códigos de respaldo</button></div>
      <p class="t2 mt">Si pierdes tu celular, usa un código de respaldo para entrar y pide a un propietario que reinicie tu doble factor.</p></section>
    <section class="panel"><h2>Sesiones abiertas</h2>${table([{ label: 'Dispositivo', render: (x) => html`${x.ua ? x.ua.slice(0, 60) : '—'}${x.current ? html` <span class="pill ok">Esta</span>` : ''}<div class="t2">${x.ip || ''}</div>` }, { label: 'Última actividad', render: (x) => ago(x.last_seen_at) }], r.sessions)}
      <button class="btn mt" id="ro">Cerrar las demás sesiones</button></section></div>`);
  $('#pw', main).onclick = () => form({ title: 'Cambiar contraseña', fields: [{ k: 'current', label: 'Contraseña actual', type: 'password', required: true, autocomplete: 'current-password' }, { k: 'next', label: 'Nueva (12+ caracteres)', type: 'password', required: true, autocomplete: 'new-password' }, { k: 'again', label: 'Repite la nueva', type: 'password', required: true, autocomplete: 'new-password' }],
    onSubmit: async (x) => { if (x.next !== x.again) throw Object.assign(new Error('No coinciden.'), { field: 'again' }); await post('/auth/password', { current: x.current, next: x.next }); closeModal(); toast('Contraseña cambiada. Se cerraron tus otras sesiones.'); } });
  $('#rc', main).onclick = async () => { try { const x = await post('/auth/recovery-codes'); secretBox('Códigos de respaldo', x.recoveryCodes.map((c, i) => ['Código ' + (i + 1), c]), 'Los anteriores dejaron de servir. Guárdalos en tu gestor de contraseñas.'); } catch (e) { toast(e.message, 'bad'); } };
  $('#ro', main).onclick = async () => { await post('/auth/sessions/revoke-others'); toast('Listo.'); hooks.reload(); };
  void confirmBox; void $$;
}
