'use strict';
/**
 * Esquema de la base. Cada elemento del arreglo es una migración; nunca se edita una ya publicada,
 * se agrega otra al final. La versión aplicada se guarda en PRAGMA user_version.
 *
 * Convenciones:
 *  - Fechas/horas: texto ISO 8601 en UTC.  Montos: céntimos enteros (sin decimales flotantes).
 *  - Columnas *_enc: cifradas con AES-256-GCM.  Columnas *_bidx: índice ciego (HMAC) para buscar.
 *  - Ids: texto aleatorio con prefijo (cli_, lic_, pay_...). No son secuenciales ni adivinables.
 *  - Historial (auditoría, eventos de licencia, abonos): solo inserción; triggers impiden editar o borrar.
 */
module.exports = [
/* ---------------------------------------------------------------- v1 */
`
CREATE TABLE sequences (name TEXT PRIMARY KEY, value INTEGER NOT NULL);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL, updated_by TEXT);
CREATE TABLE locks (name TEXT PRIMARY KEY, owner TEXT NOT NULL, expires_at TEXT NOT NULL);

/* ---------- equipo de Solvex ---------- */
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('propietario','administrador','finanzas','soporte','implementacion','lectura')),
  password_hash TEXT NOT NULL,
  must_change_password INTEGER NOT NULL DEFAULT 1,
  totp_secret_enc TEXT,
  totp_enabled INTEGER NOT NULL DEFAULT 0,
  totp_last_counter INTEGER NOT NULL DEFAULT -1,
  recovery_codes TEXT NOT NULL DEFAULT '[]',
  failed_logins INTEGER NOT NULL DEFAULT 0,
  locked_until TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  last_login_at TEXT, last_login_ip TEXT, password_changed_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,                 -- SHA-256 del token: si se filtra la base, no se pueden reutilizar sesiones
  user_id TEXT NOT NULL REFERENCES users(id),
  csrf TEXT NOT NULL,
  mfa_ok INTEGER NOT NULL DEFAULT 0,
  sudo_until TEXT,
  ip TEXT, ua TEXT,
  created_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT
);
CREATE INDEX sessions_user ON sessions(user_id);

/* ---------- catálogo: productos y planes ---------- */
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('saas','instalable','a_medida')),
  status TEXT NOT NULL DEFAULT 'activo' CHECK (status IN ('borrador','activo','retirado')),
  description TEXT,
  feature_keys TEXT NOT NULL DEFAULT '[]',
  public INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE plans (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  interval_unit TEXT NOT NULL CHECK (interval_unit IN ('day','month','year','none')),
  interval_count INTEGER NOT NULL DEFAULT 1 CHECK (interval_count BETWEEN 1 AND 3650),
  price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
  setup_cents INTEGER NOT NULL DEFAULT 0 CHECK (setup_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'PEN',
  trial_days INTEGER NOT NULL DEFAULT 0 CHECK (trial_days BETWEEN 0 AND 365),
  grace_days INTEGER NOT NULL DEFAULT 5 CHECK (grace_days BETWEEN 0 AND 90),
  features TEXT NOT NULL DEFAULT '{}',
  public INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE (product_id, code)
);

/* ---------- clientes ---------- */
CREATE TABLE clients (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('empresa','persona')),
  display_name TEXT NOT NULL,          -- nombre comercial
  legal_name_enc TEXT,
  doc_type TEXT NOT NULL CHECK (doc_type IN ('RUC','DNI','CE','PAS')),
  doc_number_enc TEXT NOT NULL,
  doc_bidx TEXT NOT NULL,
  doc_hint TEXT,                       -- últimos 3 dígitos, para reconocerlo sin descifrar
  contact_name_enc TEXT,
  email_enc TEXT, email_bidx TEXT,
  phone_enc TEXT, phone_bidx TEXT,
  address_enc TEXT,
  city TEXT,
  verification TEXT NOT NULL DEFAULT 'pendiente' CHECK (verification IN ('pendiente','verificado','observado','rechazado')),
  checklist TEXT NOT NULL DEFAULT '{}',
  notes_enc TEXT,
  owner_user_id TEXT REFERENCES users(id),
  version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, anonymized_at TEXT
);
CREATE UNIQUE INDEX clients_doc ON clients(doc_bidx) WHERE deleted_at IS NULL;  -- un RUC/DNI = un cliente
CREATE INDEX clients_email ON clients(email_bidx);
CREATE INDEX clients_phone ON clients(phone_bidx);
CREATE TABLE client_contacts (
  id TEXT PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES clients(id),
  channel TEXT NOT NULL,
  note_enc TEXT NOT NULL,
  user_id TEXT REFERENCES users(id),
  created_at TEXT NOT NULL
);
CREATE INDEX client_contacts_client ON client_contacts(client_id, created_at);

/* ---------- instancias: cada despliegue de un producto que consulta licencias ---------- */
CREATE TABLE instances (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id),
  name TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('produccion','pruebas')),
  webhook_url TEXT,
  webhook_secret_enc TEXT,
  api_key_hash TEXT NOT NULL UNIQUE,
  api_key_prefix TEXT NOT NULL,
  allowed_ips TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'activa' CHECK (status IN ('activa','pausada','revocada')),
  last_seen_at TEXT, last_seen_ip TEXT, app_version TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

/* ---------- licencias ---------- */
CREATE TABLE licenses (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  client_id TEXT NOT NULL REFERENCES clients(id),
  product_id TEXT NOT NULL REFERENCES products(id),
  plan_id TEXT NOT NULL REFERENCES plans(id),
  instance_id TEXT REFERENCES instances(id),
  tenant_ref TEXT,                     -- id del negocio dentro del producto (ej. slug de la barbería)
  label TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pendiente','prueba','activa','gracia','suspendida','cancelada')),
  suspension_kind TEXT CHECK (suspension_kind IN ('auto','manual')),
  suspension_reason TEXT,
  is_trial INTEGER NOT NULL DEFAULT 0,
  period_end TEXT,                     -- NULL = perpetua (compra de licencia)
  grace_days INTEGER NOT NULL DEFAULT 5,
  grace_end TEXT,                      -- calculado: fin del último día de gracia (zona de la licencia)
  auto_cut INTEGER NOT NULL DEFAULT 1,
  auto_invoice INTEGER NOT NULL DEFAULT 1,
  anchor_day INTEGER,
  timezone TEXT NOT NULL DEFAULT 'America/Lima',
  price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'PEN',
  interval_unit TEXT NOT NULL,
  interval_count INTEGER NOT NULL,
  features TEXT NOT NULL DEFAULT '{}',
  max_activations INTEGER NOT NULL DEFAULT 1,
  key_hash TEXT UNIQUE,                -- clave para productos instalables (solo su hash)
  key_prefix TEXT,
  pending_plan_id TEXT REFERENCES plans(id),
  activated_at TEXT, cancelled_at TEXT, cancel_reason TEXT, status_changed_at TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX licenses_tenant ON licenses(instance_id, tenant_ref) WHERE tenant_ref IS NOT NULL;
CREATE INDEX licenses_sweep ON licenses(status, grace_end);
CREATE INDEX licenses_period ON licenses(status, period_end);
CREATE INDEX licenses_client ON licenses(client_id);
CREATE INDEX licenses_instance ON licenses(instance_id);

CREATE TABLE license_grants (          -- cada extensión o reducción de vigencia, con su motivo
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL REFERENCES licenses(id),
  kind TEXT NOT NULL CHECK (kind IN ('inicio','prueba','pago','cortesia','ajuste','reverso')),
  from_end TEXT, to_end TEXT,
  periods INTEGER NOT NULL DEFAULT 0,
  invoice_id TEXT, payment_id TEXT, reverses_id TEXT,
  note TEXT,
  actor TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX license_grants_lic ON license_grants(license_id, created_at);
CREATE TABLE license_events (          -- línea de tiempo de estados
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  license_id TEXT NOT NULL REFERENCES licenses(id),
  from_status TEXT, to_status TEXT NOT NULL,
  reason TEXT, actor TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX license_events_lic ON license_events(license_id, id);
CREATE TABLE activations (             -- equipos donde se activó un producto instalable
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL REFERENCES licenses(id),
  fingerprint_hash TEXT NOT NULL,
  label TEXT, ip TEXT,
  first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, revoked_at TEXT,
  UNIQUE (license_id, fingerprint_hash)
);

/* ---------- cobros ---------- */
CREATE TABLE invoices (
  id TEXT PRIMARY KEY,
  number TEXT NOT NULL UNIQUE,
  license_id TEXT REFERENCES licenses(id),
  client_id TEXT NOT NULL REFERENCES clients(id),
  kind TEXT NOT NULL CHECK (kind IN ('renovacion','alta','implementacion','otro')),
  description TEXT NOT NULL,
  periods INTEGER NOT NULL DEFAULT 0 CHECK (periods BETWEEN 0 AND 36),
  for_period_end TEXT,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  paid_cents INTEGER NOT NULL DEFAULT 0,
  credit_applied_cents INTEGER NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'PEN',
  status TEXT NOT NULL CHECK (status IN ('pendiente','parcial','pagada','anulada')),
  due_at TEXT,
  pay_token_hash TEXT UNIQUE,
  pay_token_enc TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL, paid_at TEXT, voided_at TEXT, void_reason TEXT
);
-- Una sola factura de renovación viva por licencia y ciclo: las tareas automáticas no la duplican.
CREATE UNIQUE INDEX invoices_renewal ON invoices(license_id, for_period_end) WHERE kind = 'renovacion' AND status <> 'anulada';
CREATE INDEX invoices_client ON invoices(client_id, created_at);
CREATE INDEX invoices_status ON invoices(status, due_at);

CREATE TABLE payments (
  id TEXT PRIMARY KEY,
  number TEXT UNIQUE,                  -- n.º de recibo interno, al aprobarse
  invoice_id TEXT REFERENCES invoices(id),
  license_id TEXT REFERENCES licenses(id),
  client_id TEXT NOT NULL REFERENCES clients(id),
  method TEXT NOT NULL CHECK (method IN ('culqi','yape','plin','transferencia','deposito','efectivo','otro')),
  source TEXT NOT NULL CHECK (source IN ('panel','cliente','pasarela')),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  currency TEXT NOT NULL DEFAULT 'PEN',
  status TEXT NOT NULL CHECK (status IN ('por_verificar','aprobado','rechazado','reembolsado','anulado')),
  operation_ref TEXT, operation_norm TEXT,
  paid_on TEXT,
  payer_email_enc TEXT,
  card_label TEXT,
  note TEXT,
  reject_reason TEXT,
  created_by TEXT,
  reviewed_by TEXT, reviewed_at TEXT,
  reversed_at TEXT, reverse_reason TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
-- El mismo número de operación no se registra dos veces (salvo que el anterior fuera rechazado).
CREATE UNIQUE INDEX payments_operation ON payments(method, operation_norm)
  WHERE operation_norm IS NOT NULL AND status IN ('por_verificar','aprobado','reembolsado');
CREATE INDEX payments_status ON payments(status, created_at);
CREATE INDEX payments_client ON payments(client_id, created_at);

CREATE TABLE credits (                 -- saldo a favor del cliente (pagos de más, ajustes)
  id TEXT PRIMARY KEY,
  client_id TEXT NOT NULL REFERENCES clients(id),
  amount_cents INTEGER NOT NULL,
  reason TEXT NOT NULL,
  payment_id TEXT, invoice_id TEXT,
  actor TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX credits_client ON credits(client_id);

CREATE TABLE gateway_events (          -- idempotencia de avisos de la pasarela
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  type TEXT, charge_id TEXT,
  received_at TEXT NOT NULL, processed_at TEXT, outcome TEXT
);

/* ---------- eventos hacia los productos (tiempo real) ---------- */
CREATE TABLE outbox (
  id TEXT PRIMARY KEY,
  topic TEXT NOT NULL,
  license_id TEXT, instance_id TEXT,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL REFERENCES outbox(id),
  instance_id TEXT NOT NULL REFERENCES instances(id),
  status TEXT NOT NULL CHECK (status IN ('pendiente','entregado','fallido','descartado')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  last_status INTEGER, last_error TEXT, delivered_at TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (event_id, instance_id)
);
CREATE INDEX deliveries_due ON deliveries(status, next_attempt_at);

/* ---------- avisos a clientes ---------- */
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('email','whatsapp')),
  to_enc TEXT NOT NULL,
  to_hint TEXT,
  template TEXT NOT NULL,
  payload_enc TEXT NOT NULL,
  client_id TEXT, license_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('pendiente','enviado','fallido','omitido')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  last_error TEXT,
  dedupe_key TEXT UNIQUE,
  created_at TEXT NOT NULL, sent_at TEXT
);
CREATE INDEX notifications_due ON notifications(status, next_attempt_at);

/* ---------- comercial y soporte ---------- */
CREATE TABLE leads (
  id TEXT PRIMARY KEY,
  name_enc TEXT, business TEXT, sector TEXT, branches TEXT,
  contact_enc TEXT NOT NULL, message_enc TEXT,
  status TEXT NOT NULL DEFAULT 'nuevo' CHECK (status IN ('nuevo','contactado','demo','cotizado','ganado','perdido','spam')),
  source TEXT NOT NULL DEFAULT 'web',
  client_id TEXT REFERENCES clients(id),
  ip_hash TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX leads_status ON leads(status, created_at);
CREATE TABLE tickets (
  id TEXT PRIMARY KEY,
  number TEXT NOT NULL UNIQUE,
  client_id TEXT REFERENCES clients(id),
  license_id TEXT REFERENCES licenses(id),
  subject TEXT NOT NULL,
  priority TEXT NOT NULL CHECK (priority IN ('alta','media','baja')),
  status TEXT NOT NULL CHECK (status IN ('abierto','en_curso','resuelto','cerrado')),
  assignee_id TEXT REFERENCES users(id),
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, resolved_at TEXT
);
CREATE INDEX tickets_status ON tickets(status, priority);
CREATE TABLE ticket_notes (
  id TEXT PRIMARY KEY,
  ticket_id TEXT NOT NULL REFERENCES tickets(id),
  user_id TEXT REFERENCES users(id),
  body_enc TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE expenses (
  id TEXT PRIMARY KEY,
  concept TEXT NOT NULL,
  category TEXT NOT NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  spent_on TEXT NOT NULL,
  product_id TEXT REFERENCES products(id),
  license_id TEXT REFERENCES licenses(id),
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
);
CREATE TABLE complaints (              -- Libro de Reclamaciones virtual (INDECOPI)
  id TEXT PRIMARY KEY,
  number TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('reclamo','queja')),
  consumer_enc TEXT NOT NULL,
  good_type TEXT NOT NULL CHECK (good_type IN ('producto','servicio')),
  description_enc TEXT NOT NULL,
  request_enc TEXT NOT NULL,
  amount_cents INTEGER,
  status TEXT NOT NULL DEFAULT 'recibido' CHECK (status IN ('recibido','en_revision','respondido')),
  due_on TEXT NOT NULL,
  response_enc TEXT, responded_at TEXT, responded_by TEXT,
  ip_hash TEXT,
  created_at TEXT NOT NULL
);

/* ---------- auditoría encadenada (a prueba de manipulación) ---------- */
CREATE TABLE audit_log (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  at TEXT NOT NULL,
  actor_type TEXT NOT NULL CHECK (actor_type IN ('usuario','sistema','instancia','publico','pasarela')),
  actor_id TEXT, actor_label TEXT,
  action TEXT NOT NULL,
  entity_type TEXT, entity_id TEXT,
  ip TEXT,
  data TEXT,
  prev_hash TEXT NOT NULL,
  hash TEXT NOT NULL
);
CREATE INDEX audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX audit_at ON audit_log(at);

CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit_log es de solo inserción'); END;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit_log es de solo inserción'); END;
CREATE TRIGGER grants_no_update BEFORE UPDATE ON license_grants BEGIN SELECT RAISE(ABORT, 'license_grants es de solo inserción'); END;
CREATE TRIGGER grants_no_delete BEFORE DELETE ON license_grants BEGIN SELECT RAISE(ABORT, 'license_grants es de solo inserción'); END;
CREATE TRIGGER levents_no_update BEFORE UPDATE ON license_events BEGIN SELECT RAISE(ABORT, 'license_events es de solo inserción'); END;
CREATE TRIGGER levents_no_delete BEFORE DELETE ON license_events BEGIN SELECT RAISE(ABORT, 'license_events es de solo inserción'); END;
CREATE TRIGGER credits_no_update BEFORE UPDATE ON credits BEGIN SELECT RAISE(ABORT, 'credits es de solo inserción'); END;
CREATE TRIGGER credits_no_delete BEFORE DELETE ON credits BEGIN SELECT RAISE(ABORT, 'credits es de solo inserción'); END;
-- Un pago aprobado nunca vuelve a "por verificar" ni cambia de monto o cliente.
CREATE TRIGGER payments_guard BEFORE UPDATE ON payments
WHEN OLD.status IN ('aprobado','reembolsado','anulado','rechazado') AND (
  NEW.amount_cents <> OLD.amount_cents OR NEW.client_id <> OLD.client_id OR NEW.method <> OLD.method
  OR (OLD.status = 'aprobado' AND NEW.status NOT IN ('aprobado','reembolsado','anulado'))
  OR (OLD.status IN ('reembolsado','anulado','rechazado') AND NEW.status <> OLD.status))
BEGIN SELECT RAISE(ABORT, 'pago cerrado: no se puede modificar'); END;
CREATE TRIGGER payments_no_delete BEFORE DELETE ON payments BEGIN SELECT RAISE(ABORT, 'los pagos no se borran, se anulan'); END;
CREATE TRIGGER invoices_no_delete BEFORE DELETE ON invoices BEGIN SELECT RAISE(ABORT, 'las facturas no se borran, se anulan'); END;
CREATE TRIGGER licenses_no_delete BEFORE DELETE ON licenses BEGIN SELECT RAISE(ABORT, 'las licencias no se borran, se cancelan'); END;
`,
/* ---------------------------------------------------------------- v2: impuestos, comprobantes electrónicos y Merchant of Record */
`
/* ---------- clientes: país de residencia fiscal y documento tributario extranjero ----------
   SQLite no permite cambiar un CHECK: se reconstruye la tabla (procedimiento oficial de SQLite;
   las llaves foráneas se desactivan solo durante la migración y se verifican antes de confirmar). */
CREATE TABLE clients_v2 (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('empresa','persona')),
  display_name TEXT NOT NULL,
  legal_name_enc TEXT,
  doc_type TEXT NOT NULL CHECK (doc_type IN ('RUC','DNI','CE','PAS','EXT')),   -- EXT: documento tributario del país del cliente (Tax ID, NIT, RFC, VAT...)
  doc_number_enc TEXT NOT NULL,
  doc_bidx TEXT NOT NULL,
  doc_hint TEXT,
  country TEXT NOT NULL DEFAULT 'PE' CHECK (length(country) = 2 AND country = upper(country)),  -- residencia fiscal (ISO 3166-1): decide el impuesto
  region TEXT,                         -- estado/provincia, para impuestos subnacionales (EE. UU., Canadá...)
  contact_name_enc TEXT,
  email_enc TEXT, email_bidx TEXT,
  phone_enc TEXT, phone_bidx TEXT,
  address_enc TEXT,
  city TEXT,
  verification TEXT NOT NULL DEFAULT 'pendiente' CHECK (verification IN ('pendiente','verificado','observado','rechazado')),
  checklist TEXT NOT NULL DEFAULT '{}',
  notes_enc TEXT,
  owner_user_id TEXT REFERENCES users(id),
  version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, anonymized_at TEXT,
  CHECK (doc_type <> 'RUC' OR country = 'PE'),        -- quien tiene RUC está domiciliado en el Perú
  CHECK (doc_type <> 'EXT' OR country <> 'PE')
);
INSERT INTO clients_v2 (id,code,kind,display_name,legal_name_enc,doc_type,doc_number_enc,doc_bidx,doc_hint,country,region,contact_name_enc,email_enc,email_bidx,phone_enc,phone_bidx,address_enc,city,verification,checklist,notes_enc,owner_user_id,version,created_at,updated_at,deleted_at,anonymized_at)
  SELECT id,code,kind,display_name,legal_name_enc,doc_type,doc_number_enc,doc_bidx,doc_hint,'PE',NULL,contact_name_enc,email_enc,email_bidx,phone_enc,phone_bidx,address_enc,city,verification,checklist,notes_enc,owner_user_id,version,created_at,updated_at,deleted_at,anonymized_at FROM clients;
DROP TABLE clients;
ALTER TABLE clients_v2 RENAME TO clients;
CREATE UNIQUE INDEX clients_doc ON clients(doc_bidx) WHERE deleted_at IS NULL;
CREATE INDEX clients_email ON clients(email_bidx);
CREATE INDEX clients_phone ON clients(phone_bidx);
CREATE INDEX clients_country ON clients(country);

/* ---------- pagos: nuevo medio "mor" (cobrado por un Merchant of Record: Paddle, Lemon Squeezy...) ---------- */
CREATE TABLE payments_v2 (
  id TEXT PRIMARY KEY,
  number TEXT UNIQUE,
  invoice_id TEXT REFERENCES invoices(id),
  license_id TEXT REFERENCES licenses(id),
  client_id TEXT NOT NULL REFERENCES clients(id),
  method TEXT NOT NULL CHECK (method IN ('culqi','yape','plin','transferencia','deposito','efectivo','otro','mor')),
  provider TEXT,                       -- culqi, paddle, lemonsqueezy, stripe (NULL = pago manual)
  source TEXT NOT NULL CHECK (source IN ('panel','cliente','pasarela')),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  currency TEXT NOT NULL DEFAULT 'PEN',
  status TEXT NOT NULL CHECK (status IN ('por_verificar','aprobado','rechazado','reembolsado','anulado')),
  operation_ref TEXT, operation_norm TEXT,
  paid_on TEXT,
  payer_email_enc TEXT,
  card_label TEXT,
  note TEXT,
  reject_reason TEXT,
  created_by TEXT,
  reviewed_by TEXT, reviewed_at TEXT,
  reversed_at TEXT, reverse_reason TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
INSERT INTO payments_v2 (id,number,invoice_id,license_id,client_id,method,provider,source,amount_cents,currency,status,operation_ref,operation_norm,paid_on,payer_email_enc,card_label,note,reject_reason,created_by,reviewed_by,reviewed_at,reversed_at,reverse_reason,created_at,updated_at)
  SELECT id,number,invoice_id,license_id,client_id,method,CASE WHEN method = 'culqi' THEN 'culqi' END,source,amount_cents,currency,status,operation_ref,operation_norm,paid_on,payer_email_enc,card_label,note,reject_reason,created_by,reviewed_by,reviewed_at,reversed_at,reverse_reason,created_at,updated_at FROM payments;
DROP TABLE payments;
ALTER TABLE payments_v2 RENAME TO payments;
CREATE UNIQUE INDEX payments_operation ON payments(method, operation_norm)
  WHERE operation_norm IS NOT NULL AND status IN ('por_verificar','aprobado','reembolsado');
CREATE INDEX payments_status ON payments(status, created_at);
CREATE INDEX payments_client ON payments(client_id, created_at);
CREATE TRIGGER payments_guard BEFORE UPDATE ON payments
WHEN OLD.status IN ('aprobado','reembolsado','anulado','rechazado') AND (
  NEW.amount_cents <> OLD.amount_cents OR NEW.client_id <> OLD.client_id OR NEW.method <> OLD.method OR NEW.currency <> OLD.currency
  OR (OLD.status = 'aprobado' AND NEW.status NOT IN ('aprobado','reembolsado','anulado'))
  OR (OLD.status IN ('reembolsado','anulado','rechazado') AND NEW.status <> OLD.status))
BEGIN SELECT RAISE(ABORT, 'pago cerrado: no se puede modificar'); END;
CREATE TRIGGER payments_no_delete BEFORE DELETE ON payments BEGIN SELECT RAISE(ABORT, 'los pagos no se borran, se anulan'); END;

/* ---------- planes y licencias: cómo se interpreta el precio y quién cobra ---------- */
-- incluido: el precio YA incluye el IGV (lo que paga un cliente del Perú). mas_impuesto: al precio se le suma el impuesto.
ALTER TABLE plans ADD COLUMN tax_mode TEXT NOT NULL DEFAULT 'incluido' CHECK (tax_mode IN ('incluido','mas_impuesto'));
ALTER TABLE licenses ADD COLUMN tax_mode TEXT NOT NULL DEFAULT 'incluido' CHECK (tax_mode IN ('incluido','mas_impuesto'));
-- hub: el Hub emite los cobros (Culqi/Yape...). paddle/lemonsqueezy/stripe: cobra el Merchant of Record y avisa por webhook.
ALTER TABLE licenses ADD COLUMN billing_provider TEXT NOT NULL DEFAULT 'hub' CHECK (billing_provider IN ('hub','paddle','lemonsqueezy','stripe'));
ALTER TABLE licenses ADD COLUMN external_subscription_id TEXT;
ALTER TABLE licenses ADD COLUMN external_customer_id TEXT;
CREATE UNIQUE INDEX licenses_external ON licenses(billing_provider, external_subscription_id) WHERE external_subscription_id IS NOT NULL;

/* ---------- cobros: desglose de impuestos congelado al emitirse ---------- */
ALTER TABLE invoices ADD COLUMN list_price_cents INTEGER;                 -- precio ingresado (antes de aplicar el modo de impuesto)
ALTER TABLE invoices ADD COLUMN tax_mode TEXT NOT NULL DEFAULT 'incluido' CHECK (tax_mode IN ('incluido','mas_impuesto'));
ALTER TABLE invoices ADD COLUMN subtotal_cents INTEGER NOT NULL DEFAULT 0;  -- base imponible (valor de venta)
ALTER TABLE invoices ADD COLUMN tax_cents INTEGER NOT NULL DEFAULT 0;       -- IGV / IVA / VAT
ALTER TABLE invoices ADD COLUMN tax_rate_bp INTEGER NOT NULL DEFAULT 0;     -- tasa en puntos básicos: 1800 = 18 %
ALTER TABLE invoices ADD COLUMN tax_treatment TEXT NOT NULL DEFAULT 'gravado' CHECK (tax_treatment IN ('gravado','exportacion','no_sujeto','impuesto_extranjero','mor'));
ALTER TABLE invoices ADD COLUMN tax_operation TEXT NOT NULL DEFAULT 'venta_interna' CHECK (tax_operation IN ('venta_interna','exportacion','no_domiciliado','nrus','extranjero','mor'));
ALTER TABLE invoices ADD COLUMN tax_code TEXT;                              -- regla aplicada (PE-IGV, EXPORTACION, MOR...)
ALTER TABLE invoices ADD COLUMN tax_label TEXT;                             -- texto para el cliente: "IGV 18 %"
ALTER TABLE invoices ADD COLUMN tax_country TEXT;
ALTER TABLE invoices ADD COLUMN tax_note TEXT;                              -- por qué se aplicó (queda como evidencia)
ALTER TABLE invoices ADD COLUMN fiscal_doc TEXT NOT NULL DEFAULT 'boleta' CHECK (fiscal_doc IN ('factura','boleta','ninguno'));
ALTER TABLE invoices ADD COLUMN bill_to_enc TEXT;                           -- datos del cliente al emitir (cifrados)
ALTER TABLE invoices ADD COLUMN external_ref TEXT;                          -- id de la transacción en el Merchant of Record
-- Cobros anteriores a esta versión: se asume precio con IGV incluido (lo que se cobró), 18 %.
UPDATE invoices SET list_price_cents = amount_cents, subtotal_cents = (amount_cents * 20000 + 11800) / 23600, tax_rate_bp = 1800, tax_code = 'PE-IGV', tax_label = 'IGV 18 %', tax_country = 'PE', tax_note = 'Cobro anterior a la versión con impuestos: se asume IGV incluido';
UPDATE invoices SET tax_cents = amount_cents - subtotal_cents;
UPDATE invoices SET fiscal_doc = CASE WHEN (SELECT doc_type FROM clients c WHERE c.id = invoices.client_id) = 'RUC' THEN 'factura' ELSE 'boleta' END;
-- Integridad: base + impuesto = total, siempre.
CREATE TRIGGER invoices_tax_sum_ins BEFORE INSERT ON invoices
WHEN NEW.subtotal_cents + NEW.tax_cents <> NEW.amount_cents OR NEW.subtotal_cents < 0 OR NEW.tax_cents < 0
BEGIN SELECT RAISE(ABORT, 'cobro: base + impuesto debe ser igual al total'); END;
CREATE TRIGGER invoices_tax_sum_upd BEFORE UPDATE OF subtotal_cents, tax_cents, amount_cents ON invoices
WHEN NEW.subtotal_cents + NEW.tax_cents <> NEW.amount_cents OR NEW.subtotal_cents < 0 OR NEW.tax_cents < 0
BEGIN SELECT RAISE(ABORT, 'cobro: base + impuesto debe ser igual al total'); END;
-- Con dinero aplicado (o cerrado), el desglose ya no cambia.
CREATE TRIGGER invoices_tax_frozen BEFORE UPDATE ON invoices
WHEN (OLD.paid_cents > 0 OR OLD.credit_applied_cents > 0 OR OLD.status IN ('pagada','anulada')) AND (
  NEW.amount_cents <> OLD.amount_cents OR NEW.subtotal_cents <> OLD.subtotal_cents OR NEW.tax_cents <> OLD.tax_cents OR NEW.tax_rate_bp <> OLD.tax_rate_bp
  OR NEW.tax_treatment <> OLD.tax_treatment OR NEW.currency <> OLD.currency OR NEW.fiscal_doc <> OLD.fiscal_doc)
BEGIN SELECT RAISE(ABORT, 'cobro con pagos: su desglose de impuestos no se modifica'); END;

/* ---------- reglas de impuesto por país (y región) con vigencia ----------
   Una regla para un país distinto del Perú significa: "Solvex está inscrito para cobrar ese impuesto allí".
   Sin regla, a un cliente del extranjero se le aplica exportación de servicios (0 %) o IGV, según la configuración. */
CREATE TABLE tax_rules (
  id TEXT PRIMARY KEY,
  country TEXT NOT NULL CHECK (length(country) = 2 AND country = upper(country)),
  region TEXT,
  code TEXT NOT NULL,
  label TEXT NOT NULL,
  rate_bp INTEGER NOT NULL CHECK (rate_bp BETWEEN 0 AND 5000),
  customer_kind TEXT NOT NULL DEFAULT 'todos' CHECK (customer_kind IN ('todos','empresa','persona')),
  valid_from TEXT NOT NULL,
  valid_to TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  note TEXT,
  created_by TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
CREATE INDEX tax_rules_lookup ON tax_rules(country, active, valid_from);
INSERT INTO tax_rules (id,country,region,code,label,rate_bp,customer_kind,valid_from,valid_to,active,note,created_by,created_at,updated_at)
VALUES ('txr_pe_igv_2011', 'PE', NULL, 'PE-IGV', 'IGV', 1800, 'todos', '2011-03-01', NULL, 1, 'IGV 16 % + IPM 2 % (Ley del IGV, art. 17 y Ley 29666)', 'Sistema', strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now'));

/* ---------- comprobantes electrónicos SUNAT (factura, boleta, nota de crédito) ----------
   Uno por cada pago aprobado (SUNAT: en servicios, el comprobante se emite al percibir la retribución, por el monto percibido).
   Se envían por un proveedor autorizado (OSE/PSE) con reintentos; la numeración es correlativa por serie y nunca se reutiliza. */
CREATE TABLE fiscal_documents (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('factura','boleta','nota_credito')),
  series TEXT NOT NULL CHECK (length(series) = 4),
  number INTEGER NOT NULL CHECK (number > 0),
  invoice_id TEXT NOT NULL REFERENCES invoices(id),
  payment_id TEXT NOT NULL REFERENCES payments(id),
  client_id TEXT NOT NULL REFERENCES clients(id),
  related_id TEXT REFERENCES fiscal_documents(id),   -- comprobante que corrige una nota de crédito
  note_reason TEXT,                                   -- catálogo SUNAT 09: 01 anulación de la operación, 06 devolución total
  operation TEXT NOT NULL CHECK (operation IN ('venta_interna','exportacion','no_domiciliado','nrus')),
  currency TEXT NOT NULL DEFAULT 'PEN',
  exchange_rate TEXT,
  subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
  tax_cents INTEGER NOT NULL CHECK (tax_cents >= 0),
  total_cents INTEGER NOT NULL CHECK (total_cents > 0),
  tax_rate_bp INTEGER NOT NULL,
  tax_treatment TEXT NOT NULL,
  customer_enc TEXT NOT NULL,                         -- datos del adquirente al emitir (cifrados)
  description TEXT NOT NULL,
  issue_date TEXT,                                    -- fecha de emisión (hora de Lima), se fija al enviarse
  status TEXT NOT NULL CHECK (status IN ('pendiente','enviado','aceptado','rechazado','error','anulado')),
  provider TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  last_error TEXT,
  sunat_code TEXT, sunat_description TEXT, hash TEXT, qr TEXT, link TEXT, pdf_url TEXT, xml_url TEXT, cdr_url TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL, sent_at TEXT, accepted_at TEXT, updated_at TEXT NOT NULL,
  UNIQUE (series, number),
  CHECK (subtotal_cents + tax_cents = total_cents),
  CHECK ((kind = 'nota_credito') = (related_id IS NOT NULL))
);
CREATE UNIQUE INDEX fiscal_one_per_payment ON fiscal_documents(payment_id) WHERE kind IN ('factura','boleta') AND status <> 'rechazado';
CREATE UNIQUE INDEX fiscal_one_note ON fiscal_documents(related_id) WHERE kind = 'nota_credito' AND status <> 'rechazado';
CREATE INDEX fiscal_due ON fiscal_documents(status, next_attempt_at);
CREATE INDEX fiscal_invoice ON fiscal_documents(invoice_id);
CREATE INDEX fiscal_issue ON fiscal_documents(issue_date);
CREATE TRIGGER fiscal_no_delete BEFORE DELETE ON fiscal_documents BEGIN SELECT RAISE(ABORT, 'los comprobantes no se borran: se corrigen con nota de crédito'); END;
CREATE TRIGGER fiscal_frozen BEFORE UPDATE ON fiscal_documents
WHEN NEW.kind <> OLD.kind OR NEW.series <> OLD.series OR NEW.number <> OLD.number OR NEW.payment_id <> OLD.payment_id OR NEW.invoice_id <> OLD.invoice_id
  OR NEW.subtotal_cents <> OLD.subtotal_cents OR NEW.tax_cents <> OLD.tax_cents OR NEW.total_cents <> OLD.total_cents OR NEW.currency <> OLD.currency
  OR (OLD.status IN ('enviado','aceptado','rechazado','anulado') AND NEW.customer_enc <> OLD.customer_enc)
  OR (OLD.status = 'aceptado' AND NEW.status NOT IN ('aceptado','anulado'))
  OR (OLD.status = 'rechazado' AND NEW.status <> 'rechazado')
BEGIN SELECT RAISE(ABORT, 'comprobante emitido: no se modifica'); END;

/* ---------- avisos de pasarelas y Merchant of Record: carga cifrada y reintentos ---------- */
ALTER TABLE gateway_events ADD COLUMN payload_enc TEXT;
ALTER TABLE gateway_events ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gateway_events ADD COLUMN last_error TEXT;
`,
];
