"use client";
import dynamic from "next/dynamic";

const PDFButton = dynamic(() => import("./PDFButton"), {
  ssr: false,
  loading: () => <div className="animate-pulse">Estructurando documento...</div>,
});

export default PDFButton;
