"use client";
import dynamic from "next/dynamic";

const PDFButton = dynamic(() => import("./PDFButton"), {
  ssr: false,
  loading: () => <span className="fv-button secondary" aria-busy="true">Preparando PDF…</span>,
});

export default PDFButton;
