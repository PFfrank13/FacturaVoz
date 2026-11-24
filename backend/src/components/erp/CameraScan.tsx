"use client";
import { useEffect, useRef, useState } from "react";

type Controls = { stop: () => void };

/**
 * Reads a barcode with the device camera (phone, tablet or webcam). Uses the free ZXing reader, loaded only when the
 * button is pressed, so the sale page stays light. The image never leaves the device.
 */
export default function CameraScan({ onCode, label = "Escanear con cámara" }: { onCode: (code: string) => void; label?: string }) {
  const [open, setOpen] = useState(false);
  const [err, setErr] = useState("");
  const video = useRef<HTMLVideoElement>(null);
  const controls = useRef<Controls | null>(null);
  const done = useRef(false);

  useEffect(() => {
    if (!open) return;
    done.current = false;
    let cancelled = false;
    (async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) { setErr("Este navegador no permite usar la cámara. Usa Chrome o el lector USB."); return; }
        const { BrowserMultiFormatReader } = await import("@zxing/browser");
        const reader = new BrowserMultiFormatReader();
        if (cancelled || !video.current) return;
        controls.current = await reader.decodeFromConstraints({ video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 } } }, video.current, result => {
          if (!result || done.current) return;
          done.current = true;
          navigator.vibrate?.(60);
          controls.current?.stop();
          setOpen(false);
          onCode(result.getText());
        });
      } catch (e) {
        const name = e instanceof Error ? e.name : "";
        setErr(name === "NotAllowedError" ? "Diste «Bloquear» a la cámara. Actívala en el candado de la barra de direcciones." : name === "NotFoundError" ? "No encontramos una cámara en este equipo." : "No se pudo abrir la cámara.");
      }
    })();
    return () => { cancelled = true; controls.current?.stop(); controls.current = null; };
  }, [open, onCode]);

  return <>
    <button type="button" className="fv-button secondary fv-cam-btn" onClick={() => { setErr(""); setOpen(true); }} aria-label={label} title={label}>
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3M7 9v6M10 9v6M13 9v6M16.5 9v6" /></svg>
      <span>Cámara</span>
    </button>
    {open && <div className="fv-cam" role="dialog" aria-modal="true" aria-label="Escanear código de barras">
      <div className="fv-cam-box">
        <video ref={video} muted playsInline />
        <i className="fv-cam-line" aria-hidden="true" />
        <p>{err || "Apunta al código de barras del producto"}</p>
        <button type="button" className="fv-button" onClick={() => setOpen(false)}>Cerrar</button>
      </div>
    </div>}
  </>;
}
