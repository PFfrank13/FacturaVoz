# Checklist de salida a venta (hazlo en este orden)

## A. Base de datos y despliegue
1. Supabase → SQL Editor: ejecutar en orden `20261113` … `20261118` (todas aditivas e idempotentes). Dime "ejecutado" y las reviso en solo lectura.
2. Crear el bucket privado `tts-cache` en Storage si la 20261116 no pudo.
3. Vercel: subir `backend/` (git push). Variables (Production, Preview, Development; marca como *Sensitive* las claves): `GROQ_API_KEY`, `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `DOC_API_TOKEN`, `CRON_SECRET` (nueva), `ALLOWED_ORIGINS`, claves de Supabase, Resend. Después **Redeploy**.
4. Rotar lo que se compartió en chats: ElevenLabs, token de APISPERU y `CRON_SECRET`.

## B. Pruebas en el teléfono (3 min por rubro: `docs/GUIA_PRUEBAS_RUBROS.md`)
- Elegir rubro (queda fijo) → barra, Menú solo con lo del rubro, Gastos presente.
- Inicio: cifra del mes cuenta hacia arriba, "Hoy", gráfico de 14 días, venta nueva arriba al instante, Clientes de hoy.
- Bodega: Fiados → "Anotar fiado" por pasos; ficha del casero con historial.
- Planes: con el Hub encendido, probar Básico / Pro / Empresa en el MISMO rubro (candados y "Disponible en el plan X"); Tareas del Copiloto solo en Empresa.
- Tienda `/tienda/<slug>`: foto de producto, logo, pedido de prueba, Yape/Plin.
- Importar tu Excel real (1 500 facturas) en una empresa de PRUEBA y comparar conteos y totales.

## C. Legal y SUNAT (antes de cobrar o emitir en producción)
- SUNAT: RUC de 11 dígitos, usuario SOL secundario, certificado .pfx, prueba en beta, luego producción. Nunca pegar la clave SOL en un chat.
- Dominio propio y dominio verificado en Resend (correos).
- Publicar política de privacidad y términos (`docs/PRIVACIDAD_Y_TERMINOS.md`); inscribir bancos de datos (Ley 29733).

## D. Costos y límites (ver `docs/COSTOS_Y_ESCALA.md`)
- Vercel Hobby no permite uso comercial: pasar a Pro antes de cobrar. Supabase Pro, Groq con facturación, ElevenLabs con licencia comercial.

## E. Operación
- Cambiar el rubro de un cliente (solo tú): `select private.admin_set_rubro('<id empresa>', '<rubro>');` (`docs/OPERACION_PRODUCCION.md`).
- Piloto con UN rubro y 3–5 clientes reales antes de abrir al público.
