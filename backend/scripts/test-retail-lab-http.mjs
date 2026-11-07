// Requires serve-retail-lab.mjs on loopback. All assertions read committed SQL.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const base='http://127.0.0.1:3102';
const state=()=>fetch(base+'/__lab/state').then(r=>{assert.equal(r.status,200);return r.json();});
const submit=async body=>{const r=await fetch(base+'/__lab/checkout',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};};
const before=await state();const product=before.products.find(p=>p.name==='Synthetic rice');
assert.ok(product);assert.ok(product.stock>=1);
const sale={requestId:randomUUID(),currency:'PEN',taxBasisPoints:1800,method:'efectivo',items:[{product_id:product.id,quantity:1,unit_price:product.unit_price}]};
const responses=await Promise.all([submit(sale),submit(sale)]);
responses.forEach(r=>{assert.equal(r.status,200);assert.equal(r.body.ok,true);});
assert.equal(responses[0].body.invoiceId,responses[1].body.invoiceId);
let after=await state();
assert.equal(after.history.length,before.history.length+1);
assert.equal(after.products.find(p=>p.id===product.id).stock,product.stock-1);
assert.equal(Math.round(Number(after.cash.expected_cash)*100),Math.round(Number(before.cash.expected_cash)*100)+1180);
for(const items of [[{...sale.items[0],unit_price:0.01}],[{...sale.items[0],quantity:99999}],[{...sale.items[0],quantity:0.001}]]){
 const rejected=await submit({...sale,requestId:randomUUID(),items});assert.equal(rejected.status,400);
 assert.deepEqual(await state(),after);
}
const forbidden=await fetch(base+'/__lab/checkout',{method:'POST',headers:{Origin:'https://untrusted.invalid','Content-Type':'application/json'},body:JSON.stringify(sale)});
assert.equal(forbidden.status,403);
console.log(JSON.stringify({passed:true,concurrent_clicks:2,committed_sales:1,charged:responses[0].body.charged,stock:after.products.find(p=>p.id===product.id).stock,cash:after.cash.expected_cash,history:after.history.length,rejected_without_writes:['stale_price','insufficient_stock','excess_quantity_precision','cross_origin']},null,2));
