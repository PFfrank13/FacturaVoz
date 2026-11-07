import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import PointOfSale from "../../src/components/erp/PointOfSale";
import Brand from "../../src/components/retail/Brand";
import DataTable from "../../src/components/erp/DataTable";
import Receiving from "../../src/components/erp/Receiving";
import "../../src/app/globals.css";
import "./preview.css";
function Preview() {
  const [ricePrice, setRicePrice] = useState(2.50);
  return <main className="fv-content">
  <Brand product="POS" /><p role="note">LABORATORIO LOCAL · Productos sintéticos. Sin backend, pagos reales ni conexión a producción. El cobro simula una respuesta perdida.</p>
  <button onClick={() => setRicePrice(p => p + 1)}>Simular aumento de precio de Arroz QA</button>
  <h2>Catálogo de laboratorio</h2>
  <Receiving org="qa-retail-org" products={[{id:'11111111-1111-4111-8111-111111111111',name:'Arroz QA',stock:8}]}/>
  <DataTable rows={[{id:'qa-rice',name:'Arroz QA',price:ricePrice,active:true},{id:'qa-milk',name:'Leche QA',price:4.20,active:false}]} fields={[["name","Producto"],["price","Precio sin impuesto"],["active","Activo"]]} />
  <PointOfSale org="qa-retail-pricing" userId="qa-retail-user" currency="PEN" taxRate={18} canCollect canEdit={false} products={[
    {id:"11111111-1111-4111-8111-111111111111", name:"Arroz QA", unit_price:ricePrice},
    {id:"22222222-2222-4222-8222-222222222222", name:"Leche QA", unit_price:4.20},
  ]} />
</main>;
}
createRoot(document.getElementById("root")!).render(<React.StrictMode><Preview /></React.StrictMode>);
