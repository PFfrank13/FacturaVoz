// FacturaVoz: STAGING only, real authenticated tokens under RLS. Run with k6.
// This deliberately does NOT call SUNAT, SMS/SMTP or live payment providers.
import http from 'k6/http';
import { check, fail, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const profiles = {
  reference: { rate: .25, vus: 50, minutes: 20 },
  nominal: { rate: .69, vus: 200, minutes: 45 },
  peak: { rate: 1.67, vus: 400, minutes: 60 },
  stress5x: { rate: 8.33, vus: 800, minutes: 10 },
  stress10x: { rate: 16.67, vus: 800, minutes: 10 },
};
const profile = profiles[__ENV.PROFILE || 'reference'];
if (!profile) fail('Unknown PROFILE');
const root = (__ENV.SUPABASE_URL || '').replace(/\/$/, '');
const key = __ENV.SUPABASE_ANON_KEY;
const ref = __ENV.FV_EXPECTED_STAGING_REF;
if (__ENV.FV_STAGING_ONLY !== 'yes' || !root.startsWith('https://') || !ref || !root.includes(ref) || !key) {
  fail('Refusing to run: provide a verified STAGING URL, matching FV_EXPECTED_STAGING_REF, key and FV_STAGING_ONLY=yes');
}
const fixtures = JSON.parse(open('./fixtures.staging.json'));
if (!Array.isArray(fixtures) || fixtures.length < 1 || fixtures.some(f => !f.org_id || !f.product_id || !f.token)) {
  fail('fixtures.staging.json requires synthetic org_id, product_id, authenticated token per org');
}
const failedCheckout = new Counter('fv_checkout_failure');
const checkoutLatency = new Trend('fv_checkout_latency', true);
const duplicateMismatch = new Counter('fv_idempotency_failure');
const duration = `${profile.minutes}m`;

export const options = {
  scenarios: {
    checkout: {
      executor: 'constant-arrival-rate',
      rate: Math.round(profile.rate * 60), timeUnit: '1m', duration,
      preAllocatedVUs: Math.min(profile.vus, 250), maxVUs: Math.max(profile.vus, 300),
    },
  },
  thresholds: {
    'http_req_duration{journey:checkout}': ['p(95)<1500', 'p(99)<3000'],
    'http_req_failed{journey:checkout}': ['rate<0.001'],
    'dropped_iterations': ['count==0'],
    'fv_checkout_failure': ['count==0'],
    'fv_idempotency_failure': ['count==0'],
  },
};

function requestId() {
  // Test-data UUIDv4. Never use Math.random for security-sensitive identifiers in production.
  const digits = '0123456789abcdef';
  let s = '';
  for (let i = 0; i < 36; i++) s += i === 8 || i === 13 || i === 18 || i === 23 ? '-' : digits[Math.floor(Math.random() * 16)];
  return s.slice(0, 14) + '4' + s.slice(15, 19) + '89ab'[Math.floor(Math.random() * 4)] + s.slice(20);
}
export default function() {
  const fixture = fixtures[Math.floor(Math.random() * fixtures.length)];
  const id = requestId();
  const body = JSON.stringify({
    p_org_id: fixture.org_id, p_request_id: id, p_items: [
      { description: fixture.product_name || 'SKU de prueba', quantity: 1, unit_price: fixture.price || 10, product_id: fixture.product_id },
    ], p_tax_rate: 18, p_currency: 'PEN', p_method: 'efectivo', p_notes: 'LOAD TEST — STAGING',
  });
  const params = {
    headers: { apikey: key, Authorization: `Bearer ${fixture.token}`, 'Content-Type': 'application/json' },
    tags: { journey: 'checkout', org: 'synthetic' }, timeout: '15s',
  };
  const started = Date.now();
  const first = http.post(`${root}/rest/v1/rpc/fast_checkout_atomic`, body, params);
  checkoutLatency.add(Date.now() - started);
  const ok = check(first, { 'committed sale': r => r.status === 200 && Array.isArray(r.json()) && r.json().length > 0 && r.json()[0].invoice_id });
  if (!ok) { failedCheckout.add(1); return; }
  if (__ENV.CHECK_RETRY === 'yes' && Math.random() < .05) {
    const second = http.post(`${root}/rest/v1/rpc/fast_checkout_atomic`, body, params);
    const same = second.status === 200 && second.json()[0].invoice_id === first.json()[0].invoice_id && second.json()[0].reused === true;
    if (!same) duplicateMismatch.add(1);
  }
  sleep(.05);
}
