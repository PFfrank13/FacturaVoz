# FacturaVoz v3 — informe final

## Qué cambió (en simple)
- **Copiloto en tiempo real**: la respuesta aparece palabra por palabra mientras se escribe (antes esperabas la
  respuesta completa). Usa el modelo más rápido de Groq y arma los datos del negocio mientras te escucha.
- **Copiloto por rubro**: sabe tu rubro, tu plan y tu rol; usa las palabras de tu negocio; responde solo con datos
  reales (si no hay, dice "no lo tengo registrado"); a cajeros y técnicos no les muestra plata; en consultorios nunca
  habla de diagnósticos. **Voz natural** (ElevenLabs) al tocar "Escuchar" o al preguntar hablando, con caché y cuota;
  si falta la clave o la cuota, usa la voz del teléfono.
- **Importador de libro Excel**: lee varias hojas (clientes, comprobantes, detalle, catálogo), muestra conteos y
  totales antes de guardar, guarda todo relacionado, compara "en el archivo" vs "guardado" y se puede **deshacer**.
  Importar el mismo archivo dos veces no duplica nada.
- **Una sola cifra de ventas en toda la app** (Inicio, Reportes, Mi negocio, Copiloto): con IGV, misma moneda, sin
  anuladas, menos notas de crédito. Inicio muestra un esqueleto hasta tener el número (nunca uno a medias).
- **Mucho más rápido**: con 10 000 comprobantes, la cifra del mes pasó de 1,2 s a 0,01 s y el resumen del Copiloto
  de 9,3 s a 0,34 s.
- **9 rubros, cada uno su propia app**: barra de 4 destinos + micrófono, sus palabras, su Inicio, su Menú, sus
  medios de cobro, su ticket, datos de práctica y **una función estrella** (reposición inteligente, cuenta dividida y
  costo por plato, corte por mora, paquetes y no-shows, historial privado, búsqueda por placa, crédito con límite,
  pensiones por grupo, margen por obra). **"Otro / personalizado" ya no existe**: se pide elegir rubro, sin perder nada.
  Cambiar de rubro en Ajustes con vista previa, al instante y sin perder datos.
- **Planes × rubro**: el núcleo de tu rubro va en todos los planes; lo que tu plan no trae se ve con candado y dice
  "Disponible en el plan X".
- **Inicio limpio + Menú**: saludo, hoy, meta, 1–2 sugerencias y 3–4 accesos; el botón **Menú** es la puerta a todo,
  con buscador por texto y voz. "Nueva venta", "Lo que me deben" y "Mi negocio" agrupan lo que estaba suelto;
  Seguridad (alertas, bitácora, PIN, papelera) dentro de Ajustes. **Modo Fácil** (letras grandes).
- **Tienda**: se arma en el servidor y se renueva cada 2 min (carga rápida), datos para Google, se puede "instalar"
  en el celular, pago con Yape/Plin en el pedido.
- **DNI/RUC con APISPERU**: nombres y apellidos por separado, nombre comercial, ubicación; **aviso si el RUC está
  de baja o no habido** y pregunta antes de guardar; caché (DNI 180 días, RUC 15), límites por persona/empresa y
  contador; el token nunca sale del servidor ni aparece en registros.
- **Producción**: auditoría de seguridad entre empresas (0 fugas en 50 tablas), `/api/health` para página de estado,
  ayuda por WhatsApp con contexto, documentos de privacidad/términos, operación y costos.

Nada se borró: lo que cambió de lugar está en `docs/MAPA_DE_FUNCIONES.md`.

## Archivos modificados / nuevos
**Base de datos (nuevas, en orden):** `backend/supabase/migrations/20261113_v3_totales_importador.sql`,
`20261114_v3_rendimiento_rls.sql`, `20261115_v3_rubros.sql`, `20261116_v3_voz_documentos.sql`.

**Servidor (Next.js):** nuevos `src/lib/xlsx.ts`, `src/lib/workbook-import.ts`, `src/lib/rubro-copilot.ts`,
`src/lib/tts.ts`, `src/lib/storeseo.ts`, `src/app/api/import/workbook/route.ts`, `src/app/api/tts/route.ts`,
`src/app/api/health/route.ts`, `src/app/tienda/[slug]/manifest.webmanifest/route.ts`. Modificados: `src/lib/groq.ts`
(streaming), `src/lib/assistant.ts`, `src/app/api/assistant/route.ts`, `src/lib/doclookup.ts`,
`src/app/api/lookup/route.ts`, `src/lib/fx.ts`, `src/app/api/fiscal/emit/route.ts` (no reenvía importados/anulados),
`src/lib/publicdata.ts`, `src/components/public/StoreCart.tsx`, `src/app/tienda/[slug]/page.tsx`,
`src/app/tienda/[slug]/p/[id]/page.tsx`, `.env.example`. Pruebas: `tests/v3.test.ts`, `tests/workbook.test.ts`,
`tests/doclookup.test.ts`, `tests/copilot-v3.test.ts`, `tests/fixtures/*`.

**App (Flutter):** nuevos `lib/rubros.dart`, `lib/services/{workbook_import,rubro_repo,rubro_apply,voice}.dart`,
`lib/screens/{workbook_import,rubro_tools,rubro_picker,menu,inicio,hubs_v3}.dart`. Modificados: `access.dart`,
`app_state.dart`, `main.dart`, `config.dart`, `models.dart`, `models_v2.dart`, `reports.dart`, `finance.dart`,
`growth.dart`, `services/{pro_api,repo,v2_repo,v2_api}.dart`, `screens/{assistant,shell,catalog,home,profit,
business_setup,settings_v2,clients_hub,payments_card,new_invoice,invoice_detail,import_screen}.dart`,
`pubspec.yaml` (versión 3.0.0+5, `audioplayers`). Pruebas: `test/sales_rule_v3_test.dart`, `test/rubros_v3_test.dart`.

**Documentos:** `docs/RUBROS.md`, `docs/PLANES.md`, `docs/MAPA_DE_FUNCIONES.md`, `docs/COSTOS_Y_ESCALA.md`,
`docs/HOJA_DE_RUTA.md`, `docs/IMPORTADOR.md`, `docs/RENDIMIENTO.md`, `docs/GUIA_PRUEBAS_RUBROS.md`,
`docs/PRIVACIDAD_Y_TERMINOS.md`, `docs/OPERACION_PRODUCCION.md`, `backend/supabase/tests/LEEME.md`.

## SQL a ejecutar (en este orden, en Supabase → SQL Editor)
1. `20261113_v3_totales_importador.sql`
2. `20261114_v3_rendimiento_rls.sql`
3. `20261115_v3_rubros.sql`
4. `20261116_v3_voz_documentos.sql`

Todas son aditivas e idempotentes (se pueden correr dos veces; probado). No borran tablas ni columnas: solo
agregan, y cambian condiciones de políticas existentes con `ALTER POLICY` (mismas reglas, más rápidas).
La 20261116 crea el bucket privado `tts-cache`; si tu proyecto no lo permite por SQL, créalo a mano en Storage
(privado).

## Variables de entorno
Ya cargadas por ti: `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `DOC_API_TOKEN` (no se escribieron en ningún archivo).

**No hace falta crear `DOC_API_DNI_URL` ni `DOC_API_RUC_URL`**: el código ya trae por defecto
`https://dniruc.apisperu.com/api/v1/dni/{n}?token={token}` y `https://dniruc.apisperu.com/api/v1/ruc/{n}?token={token}`.
Si igual quieres dejarlas explícitas en Vercel (Production, Preview, Development), créalas EXACTAMENTE así:
- `DOC_API_DNI_URL` = `https://dniruc.apisperu.com/api/v1/dni/{n}?token={token}`
- `DOC_API_RUC_URL` = `https://dniruc.apisperu.com/api/v1/ruc/{n}?token={token}`

Opcionales nuevas: `ELEVENLABS_MODEL_ID` (por defecto `eleven_flash_v2_5`), `TTS_GLOBAL_DAILY_CHARS` (por defecto
600), `COPILOT_MODEL` (por defecto el más rápido). App (al compilar): `--dart-define=SUPPORT_WHATSAPP=9xxxxxxxx`,
`TERMS_URL`, `APP_VERSION=3.0.0`.

Cambio de comportamiento: `FX_API_TOKEN` ya **no** reutiliza `DOC_API_TOKEN` (para no mandar el token de APISPERU a
otro proveedor). Si usabas tipo de cambio automático, crea `FX_API_TOKEN`.

## Pruebas (lo que se ejecutó aquí)
| Suite | Resultado |
|---|---|
| Servidor (9 suites: copiloto/voz, DNI/RUC simulado, importador 1 500, SUNAT, correo, etc.) | **107 pasan, 0 fallan** |
| Importador xlsx sintético 1 500 (lectura) | conteos exactos: 250 / 1 500 (1 168 F, 274 B, 58 NC) / 3 738 / 14; neto PEN 621 469,52 · USD 9 343,51 |
| Importación en Postgres 16 | guardado = esperado en todo; idempotente; deshacer limpio; 1,9 s |
| SQL v3 (import, rubros, voz, auditoría RLS) | pasan; **0 fugas entre empresas en 50 tablas** |
| SQL anteriores (crm, fase0, licencias, módulos 1–2, roles, SUNAT) | **mismos resultados que antes** (0 diferencias) |
| Migraciones dos veces / modo estricto | OK |
| Dart: sintaxis de 126 archivos + revisión de importaciones | OK |
| Rendimiento con 10 000 comprobantes | ver `docs/RENDIMIENTO.md` |

Pruebas Flutter nuevas (corren con `flutter test`, no se pudieron ejecutar aquí): regla única de ventas, 9 rubros
(barra, Inicio, Menú, estrella, núcleo app = base, cambio de rubro sin pérdida, cuenta dividida, reposición).

## Lo que NO se pudo verificar aquí
- **Compilar y correr la app** (no hay SDK de Flutter ni teléfono): falta `flutter pub get` (nuevo paquete
  `audioplayers`), `flutter analyze` y `flutter test`. Pueden aparecer avisos menores del analizador.
- **El archivo real** `facturas_clientes_migracion_1500.xlsx` no llegó adjunto: se probó con uno sintético de la
  misma estructura. Los nombres de columnas reales pueden variar: el importador acepta sinónimos y avisa lo que no reconoce.
- **Llamadas reales** a Groq, ElevenLabs y APISPERU (aquí no hay red hacia ellos ni claves): se probaron con
  respuestas simuladas. Los límites gratuitos de APISPERU no están publicados.
- Build de Next.js (`next build`): solo se verificaron tipos de los archivos del servidor.

## Lo que tienes que hacer
1. Ejecutar las 4 migraciones SQL en orden.
2. Reemplazar `app/`, `backend/` y `docs/` en tu carpeta, `git push` (Vercel redespliega).
3. En `app/`: `flutter pub get`, `flutter analyze`, `flutter test`, compilar.
4. Seguir `docs/GUIA_PRUEBAS_RUBROS.md` (3 min por rubro) e importar tu Excel real en una empresa de prueba.
5. Antes de cobrar: Vercel Pro, Supabase Pro, Groq Developer, ElevenLabs Starter (licencia comercial) — ver
   `docs/COSTOS_Y_ESCALA.md`; publicar privacidad/términos e inscribir bancos de datos — `docs/PRIVACIDAD_Y_TERMINOS.md`.
6. **Rotar `CRON_SECRET`** (se compartió en un chat anterior) — `docs/OPERACION_PRODUCCION.md`.
7. Lanzar un piloto con un solo rubro (recomendado: Servicios técnicos) — `docs/HOJA_DE_RUTA.md`.
