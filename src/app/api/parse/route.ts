import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { invoiceInputSchema } from "@/lib/schemas";

export const maxDuration = 30;

const GROQ = "https://api.groq.com/openai/v1";
const SYSTEM = `Extrae datos de factura del dictado del usuario (español). Responde SOLO JSON:
{"client_name": string, "tax_rate": number (21 si no se menciona), "notes": string opcional,
"items": [{"description": string, "quantity": number, "unit_price": number}]}
Los importes son sin impuestos salvo que se diga lo contrario. No inventes datos.`;

const MAX_PER_MINUTE = 5;
const MAX_PER_DAY = 100;

export async function POST(req: Request) {
  // CSRF (defensa en profundidad): solo mismo origen
  const origin = req.headers.get("origin");
  const host = req.headers.get("host");
  if (origin) {
    let ok = false;
    try { ok = new URL(origin).host === host; } catch { ok = false; }
    if (!ok) return NextResponse.json({ error: "Origen no permitido" }, { status: 403 });
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "No autorizado" }, { status: 401 });

  // Rate limit por usuario (protege la cuota gratuita de Groq)
  const count = async (sinceMs: number) =>
    (
      await supabase
        .from("api_usage")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .gte("created_at", new Date(Date.now() - sinceMs).toISOString())
    ).count ?? 0;
  if ((await count(60_000)) >= MAX_PER_MINUTE || (await count(86_400_000)) >= MAX_PER_DAY)
    return NextResponse.json({ error: "Demasiadas solicitudes, espera un momento" }, { status: 429 });
  await supabase.from("api_usage").insert({ user_id: user.id });

  const form = await req.formData();
  const audio = form.get("audio");
  if (
    !(audio instanceof File) ||
    audio.size === 0 ||
    audio.size > 4_000_000 || // límite de Vercel: 4,5 MB por petición
    !/^(audio|video)\/(webm|mp4|mpeg|ogg|wav|x-m4a)/.test(audio.type)
  )
    return NextResponse.json({ error: "Audio no válido" }, { status: 400 });

  const headers = { Authorization: `Bearer ${process.env.GROQ_API_KEY}` };

  const stt = new FormData();
  stt.append("file", audio, audio.name || "dictado.webm");
  stt.append("model", "whisper-large-v3-turbo");
  stt.append("language", "es");
  stt.append("response_format", "json");
  const sttRes = await fetch(`${GROQ}/audio/transcriptions`, { method: "POST", headers, body: stt });
  if (!sttRes.ok) return NextResponse.json({ error: "Fallo al transcribir" }, { status: 502 });
  const { text } = (await sttRes.json()) as { text: string };
  if (!text?.trim()) return NextResponse.json({ error: "No se oyó nada" }, { status: 422 });

  const llmRes = await fetch(`${GROQ}/chat/completions`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: process.env.GROQ_LLM_MODEL || "openai/gpt-oss-120b", // llama-3.3-70b-versatile fue retirado por Groq
      temperature: 0,
      reasoning_effort: "low",
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM },
        { role: "user", content: text },
      ],
    }),
  });
  if (!llmRes.ok) {
    console.error("groq llm", llmRes.status, (await llmRes.text()).slice(0, 300));
    return NextResponse.json({ error: "Fallo al interpretar" }, { status: 502 });
  }

  try {
    const json = await llmRes.json();
    const raw = JSON.parse(json.choices[0].message.content);
    const parsed = invoiceInputSchema.safeParse({ ...raw, transcript: text });
    if (!parsed.success)
      return NextResponse.json({ error: "No se entendió la factura", transcript: text }, { status: 422 });
    return NextResponse.json({ invoice: parsed.data });
  } catch {
    return NextResponse.json({ error: "Respuesta no válida" }, { status: 502 });
  }
}