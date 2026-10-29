"use client";

/** Botón para imprimir o guardar como PDF (el navegador lo hace: no se necesita ningún servicio). */
export default function PrintButton({ label = "Imprimir o guardar PDF" }: { label?: string }) {
  return (
    <button type="button" onClick={() => window.print()} className="no-print rounded-2xl bg-[#6a62e2] px-5 py-3 text-[15px] font-semibold text-white shadow">
      {label}
    </button>
  );
}
