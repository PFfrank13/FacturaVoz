'use strict';
/**
 * Presentadores: convierten filas de la base en lo que ve el panel.
 * Aquí se descifran los datos personales SOLO cuando hace falta mostrarlos.
 */
const T = require('../lib/time');
const { effective, MODE } = require('./licenses');

function makeViews({ db, vault, billing, einvoice = null, tax = null }) {
  const dec = (v, aad) => (v ? vault.decrypt(v, aad) : '');

  function client(c, { full = false } = {}) {
    if (!c) return null;
    const o = {
      id: c.id, code: c.code, kind: c.kind, display_name: c.display_name, doc_type: c.doc_type, doc_hint: c.doc_hint ? '•••' + c.doc_hint : '', country: c.country || 'PE', region: c.region || null,
      city: c.city, verification: c.verification, owner_user_id: c.owner_user_id, created_at: c.created_at, updated_at: c.updated_at,
      anonymized: !!c.anonymized_at, version: c.version,
    };
    if (full && !c.anonymized_at) Object.assign(o, {
      legal_name: dec(c.legal_name_enc, 'clients.legal_name:' + c.id), doc_number: dec(c.doc_number_enc, 'clients.doc_number:' + c.id),
      contact_name: dec(c.contact_name_enc, 'clients.contact_name:' + c.id), email: dec(c.email_enc, 'clients.email:' + c.id),
      phone: dec(c.phone_enc, 'clients.phone:' + c.id), address: dec(c.address_enc, 'clients.address:' + c.id),
      notes: dec(c.notes_enc, 'clients.notes:' + c.id), checklist: JSON.parse(c.checklist || '{}'),
    });
    if (full && tax) o.tax = tax.describe(c);
    return o;
  }

  function license(l, now = Date.now()) {
    if (!l) return null;
    const eff = effective(l, now);
    const p = db.get('SELECT code, name, kind FROM products WHERE id = ?', l.product_id);
    const plan = db.get('SELECT code, name FROM plans WHERE id = ?', l.plan_id);
    const c = db.get('SELECT id, code, display_name FROM clients WHERE id = ?', l.client_id);
    const today = T.localDate(now, l.timezone);
    return {
      id: l.id, code: l.code, label: l.label, status: eff.status, stored_status: l.status, suspension: eff.kind || null, suspension_reason: l.suspension_reason,
      mode: MODE[eff.status], is_trial: !!l.is_trial,
      product: { id: l.product_id, code: p.code, name: p.name, kind: p.kind }, plan: { id: l.plan_id, code: plan.code, name: plan.name },
      client: { id: c.id, code: c.code, name: c.display_name },
      instance_id: l.instance_id, tenant_ref: l.tenant_ref,
      period_end: l.period_end, grace_end: l.grace_end, cut_at: eff.cutAt || null, timezone: l.timezone,
      period_end_local: l.period_end ? T.localDate(l.period_end, l.timezone) : null,
      grace_end_local: l.grace_end ? T.localDate(l.grace_end, l.timezone) : null,
      days_left: l.period_end ? T.diffDays(today, T.localDate(l.period_end, l.timezone)) : null,
      grace_days: l.grace_days, auto_cut: !!l.auto_cut, auto_invoice: !!l.auto_invoice,
      price_cents: l.price_cents, currency: l.currency, interval_unit: l.interval_unit, interval_count: l.interval_count, tax_mode: l.tax_mode,
      billing_provider: l.billing_provider, external_subscription_id: l.external_subscription_id,
      features: JSON.parse(l.features || '{}'), max_activations: l.max_activations, key_prefix: l.key_prefix,
      activated_at: l.activated_at, cancelled_at: l.cancelled_at, cancel_reason: l.cancel_reason, status_changed_at: l.status_changed_at,
      created_at: l.created_at, version: l.version,
    };
  }

  function invoice(i, { withLink = false } = {}) {
    if (!i) return null;
    const c = db.get('SELECT id, code, display_name FROM clients WHERE id = ?', i.client_id);
    const l = i.license_id ? db.get('SELECT id, code, label FROM licenses WHERE id = ?', i.license_id) : null;
    return {
      id: i.id, number: i.number, kind: i.kind, description: i.description, periods: i.periods, amount_cents: i.amount_cents, paid_cents: i.paid_cents,
      credit_applied_cents: i.credit_applied_cents, remaining_cents: billing.remaining(i), currency: i.currency, status: i.status, due_at: i.due_at,
      subtotal_cents: i.subtotal_cents, tax_cents: i.tax_cents, tax_rate_bp: i.tax_rate_bp, tax_label: i.tax_label, tax_treatment: i.tax_treatment, tax_operation: i.tax_operation,
      tax_note: i.tax_note, tax_mode: i.tax_mode, list_price_cents: i.list_price_cents, fiscal_doc: i.fiscal_doc, external_ref: i.external_ref,
      overdue: ['pendiente', 'parcial'].includes(i.status) && i.due_at && i.due_at < T.nowIso(),
      client: { id: c.id, code: c.code, name: c.display_name }, license: l ? { id: l.id, code: l.code, label: l.label } : null,
      created_at: i.created_at, paid_at: i.paid_at, voided_at: i.voided_at, void_reason: i.void_reason,
      pay_url: withLink && ['pendiente', 'parcial'].includes(i.status) ? billing.payUrl(i) : undefined,
    };
  }

  const userName = (id) => { if (!id) return null; const u = db.get('SELECT name FROM users WHERE id = ?', id); return u ? u.name : id; };

  function payment(p) {
    if (!p) return null;
    const c = db.get('SELECT id, code, display_name FROM clients WHERE id = ?', p.client_id);
    const inv = p.invoice_id ? db.get('SELECT id, number, description FROM invoices WHERE id = ?', p.invoice_id) : null;
    const l = p.license_id ? db.get('SELECT id, code, label FROM licenses WHERE id = ?', p.license_id) : null;
    return {
      id: p.id, number: p.number, method: p.method, provider: p.provider, source: p.source, amount_cents: p.amount_cents, currency: p.currency, status: p.status,
      operation_ref: p.operation_ref, paid_on: p.paid_on, card_label: p.card_label, note: p.note, reject_reason: p.reject_reason,
      payer_email: p.payer_email_enc ? dec(p.payer_email_enc, 'payments.payer_email:' + p.id) : '',
      created_by: userName(p.created_by), created_by_id: p.created_by, reviewed_by: userName(p.reviewed_by), reviewed_at: p.reviewed_at,
      reversed_at: p.reversed_at, reverse_reason: p.reverse_reason, created_at: p.created_at,
      client: { id: c.id, code: c.code, name: c.display_name }, invoice: inv, license: l,
      documents: db.all('SELECT id, kind, series, number, status FROM fiscal_documents WHERE payment_id = ? ORDER BY created_at', p.id)
        .map((d) => ({ id: d.id, kind: d.kind, doc: `${d.series}-${String(d.number).padStart(8, '0')}`, status: d.status })),
    };
  }

  return { client, license, invoice, payment, userName, dec };
}

module.exports = { makeViews };
