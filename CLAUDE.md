# Voice-to-Invoice (Micro-SaaS, coste cero)
Stack: Next.js 15 App Router, TypeScript estricto, Tailwind v4, Supabase (@supabase/ssr), Zod 3 + next-safe-action 7, @react-pdf/renderer, Groq (whisper-large-v3-turbo + llama-3.3-70b-versatile).

## Reglas inviolables
1. Coste cero: no sugerir servicios sin free tier funcional.
2. `await cookies()` / `await headers()` siempre.
3. Toda tabla con RLS; políticas con `(select auth.uid()) = user_id`, `TO authenticated`, índice en cada FK usada.
4. `@react-pdf/renderer` solo vía `next/dynamic` con `ssr: false`.
5. Server Actions: validar con Zod antes de tocar la DB, re-comprobar sesión, devolver `{success:true,data}` o `{success:false,error}`; nunca lanzar excepciones al cliente.
6. Funciones SECURITY DEFINER solo en schema `private` con `SET search_path = ''`.
7. Nunca exponer GROQ_API_KEY al cliente.
