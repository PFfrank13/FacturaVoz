# Voice-to-Invoice — puesta en marcha (coste 0)

1. `npx create-next-app@15 voice-invoice --typescript --tailwind --app --src-dir --eslint --import-alias "@/*"`
2. `cd voice-invoice && npm i @supabase/supabase-js @supabase/ssr @react-pdf/renderer zod@3 next-safe-action@7`
3. Copia de este kit a tu proyecto (sobrescribiendo): `src/`, `CLAUDE.md`, `.claude/`, `supabase/`, `.env.example`.
4. Supabase (free): crea proyecto, SQL Editor, pega `supabase/schema.sql` y Run.
   Auth > Email Templates > "Magic Link": cambia el cuerpo para incluir el código, por ejemplo
   `<p>Tu código: {{ .Token }}</p>`. (El login usa código de 6 dígitos.)
   Auth > URL Configuration: pon tu URL de Vercel como Site URL cuando la tengas.
   Aviso: el correo integrado de Supabase free permite muy pocos envíos por hora; para muchas pruebas configura un SMTP propio gratuito (p. ej. Resend free).
5. Groq (free): crea una API key en console.groq.com.
6. `cp .env.example .env.local` y rellena las 3 variables.
7. `npm run dev` y abre http://localhost:3000 (el micrófono funciona en localhost y HTTPS).
8. Despliegue: GitHub, luego importa en Vercel (Hobby) con las mismas variables.

Si algo falla, usa `/review` en Claude Code.

## Despliegue paso a paso (Vercel + Supabase)
1. GitHub: crea un repositorio **privado**. Comprueba que `.env.local` no está en `git status`. `git add . && git commit -m "init" && git push`.
2. Supabase: proyecto nuevo (guarda la contraseña de la DB en un gestor). SQL Editor, pega `supabase/schema.sql`, Run. Después abre Database > Advisors y revisa que no haya errores de seguridad.
3. Supabase > Project Settings > API: copia *Project URL* y la clave *anon public* (NUNCA la service_role).
4. Groq: crea API key en console.groq.com.
5. Vercel: Add New > Project > importa el repo. En Environment Variables añade `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` y `GROQ_API_KEY` (esta última como Sensitive). Deploy.
6. Supabase > Auth > URL Configuration: Site URL = tu URL de Vercel. Edita la plantilla de correo para incluir `{{ .Token }}`.
7. Sigue la sección E de `SECURITY.md` (pruebas manuales) y la B (configuración).
