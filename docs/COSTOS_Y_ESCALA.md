# Costos y escala (revisado el 29/10/2026)

Regla: **costo cero o consumo controlado**. Abajo, los límites REALES de cada servicio, cuántos clientes aguanta y
cuándo hay que pagar. Los precios cambian: revisa las fuentes antes de decidir.

## Resumen: ¿cuándo pagar?
| Servicio | Gratis hasta | Primer problema | Qué pagar y cuándo |
|---|---|---|---|
| **Vercel** (Hobby) | 1 M invocaciones, 4 h CPU activa, 100 GB transferencia/mes | ⚠️ **Hobby es solo para uso personal NO comercial** | **Vercel Pro (US$ 20/mes) ANTES de cobrar al primer cliente.** |
| **Supabase** (Free) | 500 MB de base, 5 GB de egreso, 1 GB de archivos, 50 000 MAU | Se **pausa tras 1 semana sin actividad**; sin respaldos diarios | **Pro (US$ 25/mes) al salir a producción** (respaldos diarios, sin pausa, 8 GB). |
| **Groq** (gratis) | gpt-oss-20b: 30 pedidos/min, **1 000/día, 200 000 tokens/día** | Cada pregunta al Copiloto usa ~3 000–5 000 tokens → **~40–60 preguntas al día en TOTAL** | **Plan Developer (pago por uso)** cuando tengas ~10 negocios usando el Copiloto. Whisper: 2 000 audios/día, 8 h de audio/día. |
| **Resend** (Free) | **100 correos/día, 3 000/mes**, 3 dominios | Reportes diarios + cobranza de 30 negocios ≈ 60/día | Pro (US$ 20/mes, 50 000/mes) al pasar ~40 negocios con reporte diario. |
| **ElevenLabs** (Free) | 10 000 créditos/mes (≈ 20 000 caracteres con Flash) | ⚠️ **El plan gratis NO permite uso comercial y exige atribución** | **Starter (US$ 5/mes, 30 000 créditos ≈ 60 000 caracteres con Flash, con licencia comercial)** antes de ofrecer la voz a clientes que pagan. |
| **APISPERU** (DNI/RUC) | Token gratuito con límite (no publicado: míralo en tu panel) | Límite mensual del token | Plan pagado del proveedor cuando el contador de la app se acerque al límite. |

Fuentes: [Vercel Hobby](https://vercel.com/docs/plans/hobby) ·
[Supabase pricing](https://supabase.com/docs/pricing) · [Groq rate limits](https://console.groq.com/docs/rate-limits) ·
[Resend límites](https://resend.com/docs/knowledge-base/resend-sending-limits) · [ElevenLabs precios](https://www.elevenlabs.io/pricing) y
[BIGVU (licencia comercial / atribución del plan gratis; Flash = 0,5 crédito/carácter)](https://bigvu.tv/blog/elevenlabs-pricing-2026-plans-credits-commercial-rights-api-costs/).

## Cuántos negocios aguanta cada pieza (estimado)
Supuestos por negocio activo: 30 comprobantes/día, 20 preguntas al Copiloto/día, 1 reporte diario por correo, 20
consultas DNI/RUC/día (la caché ahorra ~60 %).

| Pieza | Límite | Negocios activos |
|---|---|---|
| Supabase Free (500 MB) | ~1 KB por comprobante con líneas → ~400 000 comprobantes | ~40 negocios un año |
| Supabase Pro (8 GB) | | ~600 negocios un año |
| Vercel CPU (4 h/mes Hobby) | ~150 ms CPU por llamada | ~3 000 llamadas/día → ~50 negocios (pero Hobby no es comercial) |
| Groq gratis (200 k tokens/día) | ~4 000 tokens por pregunta | **2–3 negocios** usando bien el Copiloto |
| Resend Free (100/día) | 1–3 correos por negocio/día | ~40 negocios |
| ElevenLabs Starter (60 000 caracteres/mes) | con tope global `TTS_GLOBAL_DAILY_CHARS=600` ≈ 18 000/mes | voz premium para ~30 negocios con uso moderado (la caché repite frases gratis) |

**Conclusión:** para un piloto con 1 rubro y 5–10 negocios: Vercel Pro + Supabase Pro + Groq Developer
(≈ US$ 45–60/mes en total). Con el plan Pro de FacturaVoz a S/ 79 (IGV incluido) alcanzan **3–4 clientes pagando** para cubrirlo.

## Cómo FacturaVoz controla el consumo
- **Copiloto:** modelo más rápido y barato (`openai/gpt-oss-20b`), respuesta en tiempo real, cuota por usuario
  (8/min, 150/día). Si el modelo falla, cambia solo a otro.
- **Voz premium (ElevenLabs, solo servidor `/api/tts`):** modelo `eleven_flash_v2_5` (buen español, la mitad de
  créditos que *multilingual*); MP3 de 32 kbps; **caché global por hash** (texto + voz + modelo): una frase repetida
  nunca se vuelve a pagar, aunque la pidan mil empresas; solo se genera cuando la persona toca **"Escuchar"** o
  preguntó **hablando**; cuota diaria por empresa según plan (300 / 2 000 / 6 000 caracteres) y **tope global**
  diario (`TTS_GLOBAL_DAILY_CHARS`, por defecto 600). Uso visible en Ajustes → *Voz del Copiloto*. Si no hay clave,
  cuota o internet, se usa la voz del teléfono y se avisa qué falta.
- **DNI/RUC (APISPERU):** caché en la base (DNI 180 días, RUC 15 días; si el proveedor cae, se usa la caché hasta
  60 días), 40 consultas por persona al día, 60 / 200 / 600 por empresa según plan, 60 por hora por persona. Contador
  `lookup_quota` (hoy y mes). Lo que sale de la caché no gasta cupo.
- **Base de datos:** totales guardados por comprobante y consultas agregadas (A2/A3): Inicio pide 2 números, no
  miles de filas.

## APISPERU (J1)
- Endpoints: `https://dniruc.apisperu.com/api/v1/dni/{n}?token=…` y `/api/v1/ruc/{n}?token=…` (el **token va como
  parámetro `token`**). Respuesta DNI: `dni, nombres, apellidoPaterno, apellidoMaterno`; RUC: `ruc, razonSocial,
  nombreComercial, estado, condicion, direccion, departamento, provincia, distrito, ubigeo…`. Fuentes: implementación
  pública del autor ([peru-consult-api](https://hub.docker.com/r/giansalex/peru-consult-api)) y ejemplos de uso
  ([1](https://github.com/Setrox1250/Parcial-Agile-I/issues/4), [2](https://groups.google.com/g/publicesvfoxpro/c/mqyUWtlWJ50)).
- **Límites gratuitos:** no están publicados en una página que pudiera verificar: revísalos en tu panel de
  apisperu.com. **Uso comercial:** no encontré los términos publicados; confírmalo con el proveedor antes de vender.
- La documentación oficial (`dniruc.apisperu.com/doc`) no se pudo leer automáticamente (página dinámica).

## ElevenLabs (D3)
- Llamada: `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_22050_32`, cabecera
  `xi-api-key` (la clave **nunca** va en la URL), cuerpo `{ text, model_id: "eleven_flash_v2_5" }`.
- Planes (US$/mes): Free 0 (10 k créditos, sin uso comercial, con atribución) · Starter 5–6 (30 k, licencia comercial)
  · Creator 11–22 (121 k) · Pro 99 (600 k). Flash/Turbo: 0,5 crédito por carácter; Multilingual: 1.
- No pude abrir la página de documentación del endpoint (bloqueada para lectura automática); el formato usado es el
  estándar de su API y está cubierto por pruebas con respuestas simuladas.
