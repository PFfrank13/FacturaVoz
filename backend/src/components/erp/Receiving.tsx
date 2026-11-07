"use client";
import { useState, useRef } from "react";
import { receiveStock } from "@/app/erp/receiving";
type Product = {id:string;name:string;stock:number|null};
export default function Receiving({org,products}:{org:string;products:Product[]}) {
  const [busy,setBusy]=useState(false);
  const [formVersion,setFormVersion]=useState(0);
  const [lineIds,setLineIds]=useState([0]);
  const nextLine=useRef(1);
  const [attempt,setAttempt]=useState<Parameters<typeof receiveStock>[1] | null>(null);
  const [result,setResult]=useState<{ok:boolean;message:string;id?:string}|null>(null);
  const running=useRef(false);
  async function submit(form:FormData) {
    if(running.current || result?.ok) return;
    const lines=lineIds.map(id=>({product_id:String(form.get(`product-${id}`)),quantity:Number(form.get(`quantity-${id}`)),unit_cost:Number(form.get(`cost-${id}`))}));
    if (!attempt && new Set(lines.map(l=>l.product_id)).size!==lines.length) {setResult({ok:false,message:'Un producto aparece dos veces. Combina sus cantidades antes de confirmar.'});return;}
    const input=attempt ?? {requestId:crypto.randomUUID(),supplier:String(form.get("supplier")).trim(),reference:String(form.get("reference")).trim(),lines};
    running.current=true; setBusy(true); setAttempt(input);
    try { const response=await receiveStock(org,input); setResult(response); if(response.rejected) setAttempt(null); }
    catch { setResult({ok:false,message:"No recibimos confirmación. Conservamos la misma operación para recuperarla sin duplicar stock."}); }
    finally {running.current=false;setBusy(false);}
  }
  return <section className="sr-record-detail">
    <p className="fv-eyebrow">ENTRADA DE MERCADERÍA</p><h2>De tu proveedor al anaquel</h2>
    <p>Registra los productos que recibiste. El servidor guarda el documento y actualiza stock y último costo juntos.</p>
    <form key={formVersion} onSubmit={event=>{event.preventDefault();void submit(new FormData(event.currentTarget));}} className="fv-form">
      <fieldset disabled={!!attempt || busy} style={{border:0,padding:0,display:"contents"}}>
        <label>Proveedor<input name="supplier" required maxLength={120} placeholder="Nombre comercial" /></label>
        <label>Documento o referencia única<input name="reference" required maxLength={80} placeholder="Ej.: F001-000123" /></label>
        {lineIds.map((id,index)=><section key={id} className="sr-receipt-line"><h3>Producto {index+1}</h3>
          <label>Producto con control de stock<select name={`product-${id}`} required defaultValue=""><option value="" disabled>Seleccionar producto</option>{products.filter(p=>p.stock!==null).map(p=><option key={p.id} value={p.id}>{p.name} · stock {p.stock}</option>)}</select></label>
          <label>Cantidad recibida<input name={`quantity-${id}`} type="number" min="0.01" max="100000" step="0.01" required /></label>
          <label>Costo unitario de adquisición<input name={`cost-${id}`} type="number" min="0" max="10000000" step="0.01" required /></label>
          {lineIds.length>1&&<button type="button" className="fv-button secondary" onClick={()=>setLineIds(ids=>ids.filter(n=>n!==id))}>Quitar producto {index+1}</button>}
        </section>)}
        <button type="button" className="fv-button secondary" disabled={lineIds.length>=50} onClick={()=>setLineIds(ids=>[...ids,nextLine.current++])}>Agregar otro producto</button>
      </fieldset>
      {!result?.ok && <button className="fv-button" disabled={busy || !products.some(p=>p.stock!==null)}>{busy?"Confirmando en servidor…":attempt?"Recuperar misma recepción":"Confirmar recepción"}</button>}
    </form>
    {result && <div role={result.ok?"status":"alert"}><p>{result.message}</p>{result.id&&<p>Recepción: {result.id}</p>}{result.ok&&<button className="fv-button secondary" onClick={()=>{setAttempt(null);setResult(null);setLineIds([nextLine.current++]);setFormVersion(v=>v+1);}}>Registrar otra recepción</button>}</div>}
    {!products.some(p=>p.stock!==null)&&<p>Primero crea un producto con control de stock desde Productos, en Flutter o Web.</p>}
    <p className="fv-caption">Importes en la moneda de la empresa. Este registro no confirma pago ni genera crédito fiscal. Un error no se presenta como mercadería recibida.</p>
  </section>;
}
