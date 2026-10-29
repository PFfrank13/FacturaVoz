/* Acciones compartidas entre vistas: formularios de cliente, licencia, cobro y pago. */
import { html, raw, $, S, get, post, put, form, confirmBox, closeModal, modal, toast, money, soles, cycle, METHOD, icon, secretBox, hooks, go, can, fdate, copy, COUNTRIES, PROVIDER, taxLine, debounce } from './core.js';

const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: S.tz }).format(new Date());

/* ---------------- clientes ---------------- */
export function clientForm(c = null, prefill = {}) {
  const v = Object.assign({ kind: 'empresa', doc_type: 'RUC', country: 'PE' }, prefill, c || {});
  form({
    title: c ? 'Editar cliente' : 'Nuevo cliente', wide: true, submit: c ? 'Guardar cambios' : 'Crear cliente',
    intro: html`<p class="intro">Los datos personales (documento, correo, celular, dirección, notas) se guardan cifrados. ${c ? 'Si cambias el documento, la verificación vuelve a "sin verificar".' : ''}</p>`,
    fields: [
      { k: 'kind', label: 'Tipo', type: 'select', options: [['empresa', 'Empresa (RUC)'], ['persona', 'Persona natural']], value: v.kind, half: true },
      { k: 'display_name', label: 'Nombre comercial', required: true, value: v.display_name, half: true, placeholder: 'Barbería Don Corte' },
      { k: 'country', label: 'País de residencia fiscal', type: 'select', options: COUNTRIES, value: v.country, half: true, help: 'Decide el impuesto: Perú = IGV; extranjero = exportación (0 %) o IGV, según tu inscripción.' },
      { k: 'region', label: 'Estado o provincia (extranjero)', value: v.region || '', half: true, placeholder: 'Opcional' },
      { k: 'doc_type', label: 'Documento', type: 'select', options: [['RUC', 'RUC'], ['DNI', 'DNI'], ['CE', 'Carné de extranjería'], ['PAS', 'Pasaporte'], ['EXT', 'Documento tributario extranjero (Tax ID, NIT, RFC…)']], value: v.doc_type, half: true },
      { k: 'doc_number', label: 'Número de documento', required: true, value: v.doc_number, half: true, attrs: 'inputmode="numeric" maxlength="15"' },
      { k: 'legal_name', label: 'Razón social o nombre completo', value: v.legal_name, help: 'Como figura en SUNAT (o en el registro de su país). Sale en la boleta o factura.' },
      { k: 'contact_name', label: 'Persona de contacto', value: v.contact_name, half: true },
      { k: 'city', label: 'Ciudad', value: v.city, half: true },
      { k: 'email', label: 'Correo', type: 'email', value: v.email, half: true, help: 'Aquí llegan los avisos de cobro y corte.' },
      { k: 'phone', label: 'Celular (WhatsApp)', value: v.phone ? String(v.phone).replace(/^51/, '') : '', half: true, attrs: 'inputmode="tel" maxlength="15"' },
      { k: 'address', label: 'Dirección fiscal', value: v.address, help: 'Obligatoria para emitir factura.' },
      { k: 'owner_user_id', label: 'Responsable en Solvex', type: 'select', options: [['', 'Sin asignar']].concat((S.lookups.users || []).map((u) => [u.id, u.name])), value: v.owner_user_id || '' },
      { k: 'notes', label: 'Notas internas', type: 'textarea', value: v.notes },
    ],
    onSubmit: async (x) => {
      if (!x.owner_user_id) delete x.owner_user_id;
      if (!x.region) delete x.region;
      const r = c ? await put('/clients/' + c.id, Object.assign(x, { version: c.version })) : await post('/clients', x);
      closeModal(); toast(c ? 'Cliente actualizado.' + (r.recalculated ? ` Se recalculó el impuesto de ${r.recalculated} cobro(s) sin pagar.` : '') : 'Cliente creado.');
      if (prefill.onCreated) return prefill.onCreated(r.client);
      if (c) hooks.reload(); else go('#/clientes/' + r.client.id);
    },
  });
}

export function verifyForm(c) {
  const ck = c.checklist || {};
  const items = [['documento', 'Documento de identidad del titular revisado'], ['ruc_sunat', 'RUC consultado en SUNAT: activo y habido'], ['local_redes', 'Local o redes del negocio confirmados'], ['contrato', 'Contrato firmado'], ['datos_facturacion', 'Datos de facturación confirmados']];
  form({
    title: 'Verificación de ' + c.display_name, submit: 'Guardar verificación',
    intro: html`<p class="intro">Verificar al cliente antes de activar evita suplantaciones y cobros a nombre equivocado.</p>`,
    fields: [{ k: 'verification', label: 'Resultado', type: 'select', options: [['pendiente', 'Sin verificar'], ['verificado', 'Verificado'], ['observado', 'Observado (falta algo)'], ['rechazado', 'Rechazado']], value: c.verification }]
      .concat(items.map(([k, l]) => ({ k: 'ck_' + k, label: l, type: 'checkbox', value: !!ck[k] })))
      .concat([{ k: 'note', label: 'Observación', type: 'textarea', rows: 2 }]),
    onSubmit: async (x) => {
      const checklist = Object.fromEntries(items.map(([k]) => [k, x['ck_' + k]]));
      await post(`/clients/${c.id}/verify`, { verification: x.verification, checklist, note: x.note });
      closeModal(); toast('Verificación guardada.'); hooks.reload();
    },
  });
}

/* ---------------- licencias ---------------- */
export async function licenseForm({ client = null } = {}) {
  const L = S.lookups;
  let clients = [];
  if (!client) clients = (await get('/clients-lite')).clients;
  const products = L.products.filter((p) => p.status !== 'retirado');
  const plansOf = (pid) => L.plans.filter((p) => p.product_id === pid && p.active);
  const firstP = products[0];
  form({
    title: 'Nueva licencia', wide: true, submit: 'Crear licencia',
    intro: html`<p class="intro">Una licencia une un <b>cliente</b> con un <b>producto</b> y un <b>plan</b>. Si el producto es multi-negocio (por ejemplo la barbería en la nube), indica en qué <b>instancia</b> vive y su identificador dentro de ella.</p>`,
    fields: [
      client ? { k: 'client_id', type: 'html', html: html`<input type="hidden" id="f_client_id" value="${client.id}"><p class="pre">Cliente: <b>${client.display_name || client.name}</b></p>` }
        : { k: 'client_id', label: 'Cliente', type: 'select', required: true, options: [['', 'Elige un cliente…']].concat(clients.map((c) => [c.id, `${c.name} · ${c.code}`])) },
      { k: 'product', label: 'Producto', type: 'select', options: products.map((p) => [p.id, p.name + (p.status === 'borrador' ? ' (borrador)' : '')]), value: firstP && firstP.id, half: true },
      { k: 'plan_id', label: 'Plan', type: 'select', required: true, options: [], half: true },
      { k: 'label', label: 'Nombre del negocio o sede (opcional)', placeholder: 'Ej. Don Corte · Ica', help: 'Si lo dejas vacío se usa el nombre del cliente.' },
      { type: 'section', label: 'Conexión con el sistema' },
      { k: 'instance_id', label: 'Instancia', type: 'select', options: [], half: true },
      { k: 'tenant_ref', label: 'Identificador del negocio en esa instancia', half: true, placeholder: 'don-corte', help: 'El mismo valor que usa el sistema (slug o id de la barbería).' },
      { type: 'section', label: 'Inicio' },
      { k: 'start', label: '¿Cómo empieza?', type: 'select', options: [['cobro', 'Emitir el primer cobro: se activa sola al pagarse'], ['prueba', 'Periodo de prueba gratuito'], ['pendiente', 'Pendiente (en implementación)']].concat(can('invoices.manage') ? [['cortesia', 'Activar ya, sin cobro (cortesía)']] : []) },
      { k: 'periods', label: 'Ciclos a cobrar / activar', type: 'number', value: 1, half: true, attrs: 'min="1" max="36"' },
      { k: 'note', label: 'Motivo (si es cortesía)', half: true },
      { type: 'section', label: 'Opciones avanzadas' },
      { k: 'price', label: 'Precio especial por ciclo', type: 'money', half: true, help: 'Vacío = precio del plan.' },
      { k: 'grace_days', label: 'Días de gracia', type: 'number', half: true, help: 'Vacío = los del plan.', attrs: 'min="0" max="90"' },
      { k: 'auto_cut', label: 'Cortar automáticamente al terminar la gracia', type: 'checkbox', value: true },
      { k: 'auto_invoice', label: 'Emitir cobros de renovación y enviar recordatorios automáticamente', type: 'checkbox', value: true },
      { k: 'max_activations', label: 'Equipos permitidos (solo productos instalables)', type: 'number', value: 1, half: true, attrs: 'min="1" max="100"' },
      { k: 'timezone', label: 'Zona horaria', value: S.tz, half: true },
    ],
    after: (fm) => {
      const prod = fm.querySelector('#f_product'), plan = fm.querySelector('#f_plan_id'), inst = fm.querySelector('#f_instance_id'), tr = fm.querySelector('#f_tenant_ref');
      const fill = () => {
        const pl = plansOf(prod.value);
        plan.innerHTML = String(html`${pl.map((p) => html`<option value="${p.id}">${p.name} · ${p.interval_unit === 'none' ? money(p.price_cents) + ' pago único' : money(p.price_cents) + ' ' + cycle(p.interval_unit, p.interval_count)}${p.trial_days ? ` · prueba ${p.trial_days} d` : ''}</option>`)}`);
        if (!pl.length) plan.innerHTML = '<option value="">Este producto no tiene planes activos</option>';
        const is = L.instances.filter((i) => i.product_id === prod.value);
        inst.innerHTML = String(html`<option value="">Sin instancia (se consulta con clave o manualmente)</option>${is.map((i) => html`<option value="${i.id}">${i.name} (${i.environment})</option>`)}`);
        if (is.length === 1) inst.value = is[0].id;
        tr.disabled = !inst.value;
      };
      prod.addEventListener('change', fill); inst.addEventListener('change', () => { tr.disabled = !inst.value; });
      fill();
    },
    onSubmit: async (x) => {
      const body = { client_id: x.client_id || (client && client.id), plan_id: x.plan_id, label: x.label || undefined, start: x.start, periods: x.periods || 1, note: x.note || undefined,
        instance_id: x.instance_id || undefined, tenant_ref: x.instance_id ? x.tenant_ref : undefined, auto_cut: x.auto_cut, auto_invoice: x.auto_invoice,
        max_activations: x.max_activations || 1, timezone: x.timezone || undefined };
      if (x.price) body.price = x.price.replace(',', '.');
      if (x.grace_days != null && x.grace_days !== '') body.grace_days = x.grace_days;
      const r = await post('/licenses', body);
      closeModal();
      if (r.licenseKey) secretBox('Clave de la licencia', [['Clave para el cliente', r.licenseKey]], 'Entrégala al cliente para activar el producto en su equipo. No se guarda en claro: si se pierde, se regenera.');
      else toast(r.invoice ? 'Licencia creada. Se emitió el cobro ' + r.invoice.number + '.' : 'Licencia creada.');
      go('#/licencias/' + r.license.id);
    },
  });
}

export function editLicense(d) {
  const l = d.license;
  form({
    title: 'Editar ' + l.code, wide: true,
    fields: [
      { k: 'label', label: 'Nombre del negocio o sede', value: l.label },
      { k: 'plan_id', label: 'Plan', type: 'select', options: d.plans.map((p) => [p.id, `${p.name} · ${money(p.price_cents)} ${cycle(p.interval_unit, p.interval_count)}`]), value: l.plan.id, help: 'Cambiar de plan aplica el precio y las funciones del plan nuevo desde ahora; la fecha de vencimiento no cambia.' },
      { k: 'instance_id', label: 'Instancia', type: 'select', options: [['', 'Sin instancia']].concat(S.lookups.instances.filter((i) => i.product_id === l.product.id).map((i) => [i.id, i.name])), value: l.instance_id || '', half: true },
      { k: 'tenant_ref', label: 'Identificador en la instancia', value: l.tenant_ref || '', half: true },
      { k: 'price', label: 'Precio por ciclo', type: 'money', value: soles(l.price_cents), half: true, help: can('invoices.manage') ? '' : 'Requiere permiso de Finanzas.' },
      { k: 'grace_days', label: 'Días de gracia', type: 'number', value: l.grace_days, half: true },
      { k: 'auto_cut', label: 'Corte automático al terminar la gracia', type: 'checkbox', value: l.auto_cut },
      { k: 'auto_invoice', label: 'Cobros de renovación y recordatorios automáticos', type: 'checkbox', value: l.auto_invoice },
      { k: 'max_activations', label: 'Equipos permitidos', type: 'number', value: l.max_activations, half: true },
      { k: 'timezone', label: 'Zona horaria', value: l.timezone, half: true },
      { type: 'section', label: 'Cobro e impuestos' },
      { k: 'tax_mode', label: 'El precio de la licencia…', type: 'select', options: [['incluido', 'ya incluye IGV (precio final para el Perú)'], ['mas_impuesto', 'es sin impuesto (se suma el que corresponda)']], value: l.tax_mode || 'incluido', half: true },
      { k: 'billing_provider', label: 'Quién cobra', type: 'select', options: Object.entries(PROVIDER).filter(([k]) => k === 'hub' || (S.lookups.mor || []).includes(k) || k === l.billing_provider), value: l.billing_provider || 'hub', half: true,
        help: 'Con un Merchant of Record, el Hub no emite cobros: la licencia se extiende cuando llega su aviso de pago. El checkout debe llevar solvex_license = ' + l.code + '.' },
    ],
    onSubmit: async (x) => {
      const body = { label: x.label, plan_id: x.plan_id, instance_id: x.instance_id, tenant_ref: x.tenant_ref || undefined, grace_days: x.grace_days, auto_cut: x.auto_cut, auto_invoice: x.auto_invoice, max_activations: x.max_activations, timezone: x.timezone, version: l.version };
      if (x.price && x.price.replace(',', '.') !== soles(l.price_cents)) body.price = x.price.replace(',', '.');
      if (x.plan_id === l.plan.id) delete body.plan_id;
      if (x.tax_mode !== (l.tax_mode || 'incluido')) body.tax_mode = x.tax_mode;
      if (x.billing_provider !== (l.billing_provider || 'hub')) body.billing_provider = x.billing_provider;
      await put('/licenses/' + l.id, body); closeModal(); toast('Licencia actualizada.'); hooks.reload();
    },
  });
}

export function licenseAction(kind, l) {
  const id = l.id, done = (m) => { closeModal(); toast(m); hooks.reload(); };
  if (kind === 'suspend') return confirmBox({ title: 'Suspender ' + l.code, body: 'Suspensión MANUAL: el sistema del cliente se bloquea al instante y NO se levanta sola aunque pague. Úsala por incumplimiento o riesgo, no por falta de pago (eso es automático).', reason: true, submit: 'Suspender', danger: true, onConfirm: async (x) => { await post(`/licenses/${id}/suspend`, { reason: x.reason }); done('Licencia suspendida.'); } });
  if (kind === 'resume') return confirmBox({ title: 'Levantar suspensión', body: 'El estado vuelve a calcularse por fechas: si está pagada se activa; si venció, entra en gracia o corte.', submit: 'Levantar', onConfirm: async () => { await post(`/licenses/${id}/resume`); done('Suspensión levantada.'); } });
  if (kind === 'cancel') return confirmBox({ title: 'Cancelar ' + l.code, body: 'Baja definitiva: el cliente queda en modo restringido (solo puede exportar sus datos), se anulan los cobros abiertos sin pagos y no se reactivará con pagos.', reason: true, submit: 'Dar de baja', danger: true, onConfirm: async (x) => { await post(`/licenses/${id}/cancel`, { reason: x.reason }); done('Licencia cancelada.'); } });
  if (kind === 'reopen') return confirmBox({ title: 'Reabrir ' + l.code, body: 'La licencia vuelve a su estado según fechas.', submit: 'Reabrir', onConfirm: async () => { await post(`/licenses/${id}/reopen`); done('Licencia reabierta.'); } });
  if (kind === 'push') return post(`/licenses/${id}/push`).then(() => toast('Se reenvió el estado al sistema del cliente.'), (e) => toast(e.message, 'bad'));
  if (kind === 'key') return confirmBox({ title: 'Regenerar clave', body: 'La clave actual deja de funcionar y se desactivan todos los equipos. El cliente deberá activar con la nueva.', submit: 'Regenerar', danger: true, onConfirm: async () => { const r = await post(`/licenses/${id}/rotate-key`); closeModal(); secretBox('Nueva clave de ' + l.code, [['Clave', r.licenseKey]]); hooks.reload(); } });
  if (kind === 'extend') return form({ title: 'Extender sin cobro', intro: html`<p class="intro">Úsalo para compensaciones o acuerdos. Queda registrado con tu nombre y el motivo.</p>`, fields: [{ k: 'periods', label: 'Ciclos', type: 'number', half: true, help: cycle(l.interval_unit, l.interval_count) }, { k: 'days', label: 'o días', type: 'number', half: true }, { k: 'note', label: 'Motivo', type: 'textarea', required: true, rows: 2 }], submit: 'Extender', onSubmit: async (x) => { await post(`/licenses/${id}/extend`, { periods: x.periods || undefined, days: x.days || undefined, note: x.note }); done('Vigencia extendida.'); } });
  if (kind === 'activate') return form({ title: 'Activar ' + l.code, fields: [{ k: 'mode', label: 'Modo', type: 'select', options: [['cobro', 'Emitir cobro (se activa sola al pagar)'], ['prueba', 'Periodo de prueba']].concat(can('invoices.manage') ? [['cortesia', 'Activar sin cobro (cortesía)']] : []) }, { k: 'periods', label: 'Ciclos', type: 'number', value: 1, half: true }, { k: 'note', label: 'Motivo (si es cortesía)', half: true }], submit: 'Activar', onSubmit: async (x) => { await post(`/licenses/${id}/activate`, x); done('Listo.'); } });
}

/* ---------------- cobros y pagos ---------------- */
export function invoiceForm({ license = null, client = null }) {
  if (license) {
    return form({ title: 'Nuevo cobro para ' + license.code, intro: html`<p class="intro">Precio por ciclo: <b>${money(license.price_cents)}</b> (${cycle(license.interval_unit, license.interval_count)}). Al pagarse se extiende la vigencia automáticamente.</p>`,
      fields: [{ k: 'periods', label: 'Ciclos', type: 'number', value: 1, attrs: 'min="1" max="36"', half: true }, { k: 'due_date', label: 'Vence', type: 'date', half: true, value: today() }],
      submit: 'Emitir cobro', onSubmit: async (x) => { const r = await post(`/licenses/${license.id}/invoice`, { periods: x.periods || 1, due_date: x.due_date || undefined }); closeModal(); payLinkBox(r.invoice); hooks.reload(); } });
  }
  return form({ title: 'Nuevo cobro', fields: [
    { k: 'kind', label: 'Tipo', type: 'select', options: [['implementacion', 'Implementación / instalación'], ['otro', 'Otro servicio']] },
    { k: 'description', label: 'Descripción', required: true, placeholder: 'Implementación de 2 sedes' }, { k: 'amount', label: 'Precio', type: 'money', required: true, half: true },
    { k: 'tax_mode', label: 'El precio…', type: 'select', options: [['incluido', 'ya incluye IGV'], ['mas_impuesto', 'es sin IGV (se suma)']], half: true },
    { k: 'due_date', label: 'Vence', type: 'date', half: true, value: today() },
    { type: 'html', html: html`<div class="taxprev" id="taxprev" aria-live="polite"><span class="t2">Escribe el precio para ver cuánto pagará el cliente.</span></div>` }],
  after: (fm) => {
    const show = debounce(async () => {
      const box = fm.querySelector('#taxprev'), amount = fm.querySelector('#f_amount').value.replace(',', '.');
      if (!(Number(amount) > 0)) return;
      try {
        const q = (await post('/tax/preview', { client_id: client.id, price: amount, tax_mode: fm.querySelector('#f_tax_mode').value })).quote;
        box.innerHTML = String(html`<div><span>Valor de venta</span><b>${money(q.subtotal_cents)}</b></div><div><span>${q.label}</span><b>${money(q.tax_cents)}</b></div><div class="tot"><span>El cliente paga</span><b>${money(q.total_cents)}</b></div><p class="t2">${q.fiscal_doc === 'factura' ? 'Factura' : q.fiscal_doc === 'boleta' ? 'Boleta' : 'Sin comprobante'} · ${q.note}</p>`);
      } catch (e) { box.textContent = e.message; }
    }, 300);
    fm.querySelector('#f_amount').addEventListener('input', show); fm.querySelector('#f_tax_mode').addEventListener('change', show);
  },
  submit: 'Emitir cobro', onSubmit: async (x) => { const r = await post('/invoices', Object.assign(x, { client_id: client.id, amount: x.amount.replace(',', '.') })); closeModal(); payLinkBox(r.invoice); hooks.reload(); } });
}

export function payLinkBox(inv) {
  modal(String(html`<h2>Cobro ${inv.number}</h2><p class="intro">${inv.description}<br>Monto: <b>${money(inv.remaining_cents, inv.currency)}</b>${inv.tax_treatment ? html`<br><span class="t2">${taxLine(inv)}</span>` : ''}</p>
    ${inv.pay_url ? html`<div class="secret"><span>Enlace de pago</span><code>${inv.pay_url}</code><button class="btn sm" data-copy="${inv.pay_url}">${icon('copy')} Copiar</button></div><p class="help">El enlace es personal (no se puede adivinar). El cliente paga con tarjeta/Yape o reporta su transferencia; al confirmarse, la licencia se actualiza sola.</p>` : ''}
    <div class="acts"><button class="btn pri" data-close>Listo</button></div>`));
  $('#modal [data-close]').onclick = closeModal;
}

/** Registrar pago manual. invoices: cobros abiertos para elegir. */
export function paymentForm({ invoices, preselect = null }) {
  if (!invoices.length) { toast('No hay cobros abiertos. Emite un cobro primero.', 'warn'); return; }
  const canApprove = can('payments.approve');
  form({
    title: 'Registrar pago', wide: true, submit: 'Registrar',
    intro: html`<p class="intro">Para Yape, Plin, transferencia o efectivo. Verifica en tu banco o app que el dinero llegó antes de aprobar.</p>`,
    fields: [
      { k: 'invoice_id', label: 'Cobro', type: 'select', options: invoices.map((i) => [i.id, `${i.number} · ${i.client.name} · ${i.description} · falta ${money(i.remaining_cents)}`]), value: preselect || invoices[0].id },
      { k: 'method', label: 'Medio', type: 'select', options: ['yape', 'plin', 'transferencia', 'deposito', 'efectivo', 'otro'].map((m) => [m, METHOD[m]]), half: true },
      { k: 'amount', label: 'Monto recibido', type: 'money', required: true, half: true, value: soles(invoices.find((i) => i.id === (preselect || invoices[0].id)).remaining_cents) },
      { k: 'operation_ref', label: 'N.º de operación', half: true, help: 'Obligatorio para Yape, Plin y bancos. Evita registrar el mismo pago dos veces.' },
      { k: 'paid_on', label: 'Fecha del pago', type: 'date', value: today(), half: true },
      { k: 'note', label: 'Nota', type: 'textarea', rows: 2 },
      canApprove ? { k: 'approve', label: 'Ya verifiqué que el dinero llegó: aprobar ahora', type: 'checkbox', value: false, help: 'Al aprobar se emite el recibo y, si el cobro queda completo, la licencia se extiende y reactiva al instante.' } : { type: 'html', html: html`<p class="help">Quedará "por verificar" hasta que Finanzas lo apruebe.</p>` },
    ],
    after: (fm) => { const sel = fm.querySelector('#f_invoice_id'); sel.addEventListener('change', () => { const i = invoices.find((x) => x.id === sel.value); fm.querySelector('#f_amount').value = soles(i.remaining_cents); }); },
    onSubmit: async (x) => {
      const r = await post('/payments', { invoice_id: x.invoice_id, method: x.method, amount: x.amount.replace(',', '.'), operation_ref: x.operation_ref || undefined, paid_on: x.paid_on || undefined, note: x.note || undefined, approve: !!x.approve });
      closeModal();
      toast(r.payment.status === 'aprobado' ? `Pago aprobado. Recibo ${r.payment.number}.` + (r.license ? ` Licencia: ${r.license.status}.` : '') : 'Pago registrado: queda por verificar.');
      hooks.reload(); hooks.counts();
    },
  });
}

export async function approvePayment(p) {
  try { const r = await post(`/payments/${p.id}/approve`); toast(`Aprobado. Recibo ${r.payment.number}.` + (r.license ? ` La licencia quedó ${r.license.status}.` : '')); hooks.reload(); hooks.counts(); }
  catch (e) { toast(e.message, 'bad'); }
}
export function rejectPayment(p) {
  confirmBox({ title: 'Rechazar pago', body: html`${money(p.amount_cents)} por ${METHOD[p.method]}${p.operation_ref ? ' · op. ' + p.operation_ref : ''}. Se avisará al cliente con el motivo.`, reason: true, reasonLabel: 'Motivo (lo verá el cliente)', submit: 'Rechazar', danger: true,
    onConfirm: async (x) => { await post(`/payments/${p.id}/reject`, { reason: x.reason }); closeModal(); toast('Pago rechazado.'); hooks.reload(); hooks.counts(); } });
}
export function reversePayment(p) {
  form({ title: 'Anular o reembolsar ' + (p.number || 'pago'), danger: true, submit: 'Confirmar',
    intro: html`<p class="intro warnbox">${icon('alert')} Se revierte la vigencia que este pago dio a la licencia (puede volver a gracia o corte). El pago queda en el historial como anulado/reembolsado.</p>`,
    fields: [{ k: 'kind', label: 'Tipo', type: 'select', options: [['anulado', 'Anular (error de registro, pago no válido)'], ['reembolsado', 'Reembolsado al cliente']] }, { k: 'reason', label: 'Motivo', type: 'textarea', required: true, rows: 2 }],
    onSubmit: async (x) => { await post(`/payments/${p.id}/reverse`, x); closeModal(); toast('Pago ' + x.kind + '.'); hooks.reload(); } });
}

export async function sendLink(l) {
  try {
    const r = await post(`/licenses/${l.id}/send-link`);
    modal(String(html`<h2>Enlace de pago · ${l.code}</h2><p class="intro">${r.queued ? `Se envió por ${r.queued} canal(es) registrados del cliente.` : 'El cliente no tiene correo/WhatsApp registrados o los canales no están configurados: envíalo tú.'}</p>
      <div class="secret"><span>Enlace</span><code>${r.pay_url}</code><button class="btn sm" data-copy="${r.pay_url}">${icon('copy')} Copiar</button></div>
      <div class="acts">${r.whatsapp_link ? html`<a class="btn" href="${r.whatsapp_link}" target="_blank" rel="noopener noreferrer">${icon('wa')} Abrir WhatsApp</a>` : ''}<button class="btn" data-copy="${r.text}">${icon('copy')} Copiar mensaje</button><button class="btn pri" data-close>Listo</button></div>`));
    $('#modal [data-close]').onclick = closeModal;
  } catch (e) { toast(e.message, 'bad'); }
}

export { copy, fdate, raw };
