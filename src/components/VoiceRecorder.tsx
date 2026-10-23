"use client";
import { useRef, useState } from "react";

export default function VoiceRecorder({
  onAudio,
  disabled,
}: {
  onAudio: (blob: Blob, filename: string) => void;
  disabled?: boolean;
}) {
  const [recording, setRecording] = useState(false);
  const [error, setError] = useState("");
  const recRef = useRef<MediaRecorder | null>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rafRef = useRef(0);
  const ctxRef = useRef<AudioContext | null>(null);

  async function start() {
    setError("");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mime = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/mp4";
      const rec = new MediaRecorder(stream, { mimeType: mime });
      const chunks: BlobPart[] = [];
      rec.ondataavailable = (e) => chunks.push(e.data);
      rec.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        cancelAnimationFrame(rafRef.current);
        ctxRef.current?.close();
        onAudio(new Blob(chunks, { type: mime }), mime === "audio/webm" ? "dictado.webm" : "dictado.mp4");
      };
      const ctx = new AudioContext();
      await ctx.resume(); // Safari/iOS lo crea suspendido
      ctxRef.current = ctx;
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 64;
      ctx.createMediaStreamSource(stream).connect(analyser);
      const data = new Uint8Array(analyser.frequencyBinCount);
      const draw = () => {
        const c = canvasRef.current;
        if (!c) return;
        const g = c.getContext("2d")!;
        analyser.getByteFrequencyData(data);
        g.clearRect(0, 0, c.width, c.height);
        g.fillStyle = "#ef4444";
        const w = c.width / data.length;
        data.forEach((v, i) => {
          const h = (v / 255) * c.height;
          g.fillRect(i * w + 1, (c.height - h) / 2, w - 2, Math.max(h, 2));
        });
        rafRef.current = requestAnimationFrame(draw);
      };
      draw();
      rec.start();
      recRef.current = rec;
      setRecording(true);
    } catch {
      setError("No se pudo acceder al micrófono");
    }
  }

  function stop() {
    recRef.current?.stop();
    setRecording(false);
  }

  return (
    <div className="flex flex-col items-center gap-4">
      <canvas ref={canvasRef} width={240} height={60} className={recording ? "" : "opacity-20"} />
      <button
        type="button"
        disabled={disabled}
        onClick={recording ? stop : start}
        className={`h-24 w-24 rounded-full text-4xl text-white shadow-lg disabled:opacity-50 ${
          recording ? "bg-red-600 animate-pulse" : "bg-blue-600"
        }`}
        aria-label={recording ? "Detener" : "Dictar factura"}
      >
        {recording ? "■" : "🎙"}
      </button>
      <p className="text-sm text-gray-500">
        {recording ? "Escuchando… toca para terminar" : "Toca y dicta: cliente, servicio e importe"}
      </p>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}
