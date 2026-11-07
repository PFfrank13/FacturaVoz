import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import PointOfSale from '../../src/components/erp/PointOfSale';
import DataTable from '../../src/components/erp/DataTable';
import Brand from '../../src/components/retail/Brand';
import '../../src/app/globals.css';
import '../retail-preview/preview.css';
type State={user:string;org:string;products:{id:string;name:string;unit_price:number;stock:number}[];history:Record<string,unknown>[];cash:{expected_cash:number}};
function Lab(){
 const [state,setState]=useState<State|null>(null);const [error,setError]=useState('');
 useEffect(()=>{let live=true;const refresh=()=>{fetch('/__lab/state').then(r=>{if(!r.ok)throw Error();return r.json();}).then(s=>{if(live){setState(s);setError('');}}).catch(()=>{if(live)setError('No se pudo leer PostgreSQL.');});};refresh();window.addEventListener('retail-lab-refresh',refresh);return()=>{live=false;window.removeEventListener('retail-lab-refresh',refresh);};},[]);
 return <main className="fv-content"><Brand product="Control"/><p role="note">Laboratorio local · Sesión sintética fija · PostgreSQL real aislado · Sin pagos externos.</p>
 {error&&<p role="alert">{error}</p>}{!state?<p role="status">Leyendo la tienda…</p>:<>
 <h1>Tu tienda de prueba</h1><p>Ventas: {state.history.length} · Caja esperada: S/{Number(state.cash.expected_cash??0).toFixed(2)}</p>
 <PointOfSale org={state.org} userId={state.user} products={state.products} currency="PEN" taxRate={18} canCollect canEdit={false}/>
 <h2>Inventario persistido</h2><DataTable rows={state.products} fields={[["name","Producto"],["unit_price","Precio"],["stock","Existencias"]]}/>
 <h2>Historial persistido</h2><DataTable rows={state.history} fields={[["number","Venta"],["status","Estado"],["amt_total","Total"]]}/>
 </>}</main>;
}
createRoot(document.getElementById('root')!).render(<React.StrictMode><Lab/></React.StrictMode>);
