'use strict';
/** Parámetros del negocio editables desde el panel (Configuración). */
const { nowIso } = require('../lib/time');

const DEFAULTS = {
  company: { name: 'Solvex', legal_name: '', ruc: '', address: '', email: '', phone: '', website: '' },
  payment_instructions: {
    yape_number: '', yape_holder: '', plin_number: '', plin_holder: '',
    bank_accounts: [], // [{ bank, currency, account, cci, holder }]
    note: 'Envía el número de operación desde el enlace de pago para activar tu servicio.',
  },
  reminders_days: [7, 3, 1],      // avisos antes del vencimiento
  renewal_notice_days: 10,        // días antes del vencimiento en que se emite el cobro de renovación
  four_eyes: false,               // si es true, quien registra un pago manual no puede aprobarlo
  restore_anchor: 'fecha_pago',   // al pagar una licencia ya cortada: el nuevo ciclo empieza el día del pago
  allow_client_reports: true,     // el cliente puede reportar su pago (Yape/transferencia) desde el enlace
  complaint_days: 15,             // días hábiles para responder un reclamo (Libro de Reclamaciones)
  tax: {
    regime: 'mype',               // régimen tributario de Solvex: nrus (no cobra IGV, solo boletas) | rer | mype | general
    export_registered: false,     // inscrito en el Registro de Exportadores de Servicios de SUNAT: clientes del extranjero al 0 %
  },
  einvoice: {
    enabled: false,               // emitir boleta/factura electrónica por cada pago aprobado
    series_factura: 'F001', series_boleta: 'B001', series_nc_factura: 'FC01', series_nc_boleta: 'BC01',
    send_to_client: true,         // el proveedor envía el PDF al correo del cliente
  },
};

class Settings {
  constructor(db) { this.db = db; this.cache = null; }
  all() {
    if (this.cache) return this.cache;
    const out = JSON.parse(JSON.stringify(DEFAULTS));
    for (const r of this.db.all('SELECT key, value FROM settings')) {
      try { const v = JSON.parse(r.value); out[r.key] = (v && typeof v === 'object' && !Array.isArray(v) && out[r.key] && typeof out[r.key] === 'object' && !Array.isArray(out[r.key])) ? Object.assign({}, out[r.key], v) : v; } catch (_) { /* ignora valores corruptos */ }
    }
    this.cache = out; return out;
  }
  get(k) { return this.all()[k]; }
  set(k, v, userId) {
    if (!(k in DEFAULTS)) throw new Error('Parámetro desconocido: ' + k);
    this.db.run('INSERT INTO settings (key,value,updated_at,updated_by) VALUES (?,?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at, updated_by=excluded.updated_by',
      k, JSON.stringify(v), nowIso(), userId || null);
    this.cache = null;
  }
}

module.exports = { Settings, DEFAULTS };
