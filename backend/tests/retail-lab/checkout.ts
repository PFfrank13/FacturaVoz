export type { CheckoutResult } from '../../src/app/erp/checkout';
export async function checkout(_org: string, input: unknown) {
  const response = await fetch('/__lab/checkout', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});
  const result = await response.json();
  window.dispatchEvent(new Event('retail-lab-refresh'));
  return result;
}
