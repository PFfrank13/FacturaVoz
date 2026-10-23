# Auditoría de seguridad — Voice-to-Invoice

Alcance: código del kit, esquema Supabase, despliegue en Vercel, terceros (Groq). Revisión estática; no sustituye un pentest sobre la app desplegada.

## A. Corregido en el código
| # | Riesgo | Severidad | Corrección |
|---|--------|-----------|------------|
| 1 | Abuso de /api/parse por usuarios registrados: agota la cuota gratuita de Groq (DoS económico) | Alta | Rate limit por usuario (5/min, 100/día) con tabla `api_usage` + RLS |
| 2 | Auth solo en middleware (cf. CVE-2025-29927, bypass de middleware en Next) | Alta | Re-verificación de sesión en página, Server Action y API; RLS como última barrera |
| 3 | Políticas UPDATE de `invoices`/`invoice_items` no verificaban propiedad de `client_id`/`invoice_id` | Media | `WITH CHECK` con `EXISTS` |
| 4 | Facturas emitidas borrables | Media (fiscal) | DELETE solo en `status='draft'` |
| 5 | Mensajes de error internos podían llegar al cliente | Media | `SafeError`; resto → "Error inesperado" |
| 6 | Sin cabeceras de seguridad (XSS/clickjacking/MIME sniffing) | Media | CSP, HSTS, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy en `next.config.ts` |
| 7 | CSRF en endpoint con cookies | Baja | Comprobación de Origin + cookies SameSite |
| 8 | Subida de audio sin validar tipo/tamaño | Baja | Tipo MIME y 4 MB máx. |
| 9 | Comodines LIKE en búsqueda de cliente | Baja | Escapado de `%` `_` `\` |
| 10 | Importes con errores de coma flotante en documento fiscal | Baja | Redondeo a céntimos |
| 11 | Condición de carrera en numeración de facturas | Baja | Reintento ante `unique` violada |
| 12 | Función SECURITY DEFINER invocable | Media | `REVOKE EXECUTE`, schema `private`, `search_path=''` |
| 13 | Rol `anon` con privilegios por defecto en `public` | Baja | `REVOKE ALL ... FROM anon` |
| 14 | Login por enlace falla/filtrable entre navegadores | Baja | Código OTP de 6 dígitos |

## B. Configuración que debes hacer tú (críticos primero)
1. **Secretos**: `GROQ_API_KEY` solo en Vercel (marcar *Sensitive*), nunca con prefijo `NEXT_PUBLIC_`. Nunca uses la clave `service_role` en este proyecto. Verifica que `.env.local` no se sube a GitHub (`git status` antes del primer commit). Si una clave se filtra: rotarla de inmediato.
2. **2FA** en GitHub, Vercel, Supabase y Groq.
3. **Supabase > Auth**: activar CAPTCHA (Cloudflare Turnstile, gratis) contra registros masivos y envío de códigos a terceros; OTP caduca en 600 s; Site URL y Redirect URLs exactas (sin comodines); desactivar proveedores que no uses.
4. **Supabase > Database > Advisors > Security**: ejecutar tras el SQL; debe salir sin errores de RLS.
5. **Supabase > API settings**: solo `public` expuesto; mantén "Automatically enable RLS" activo.
6. **Vercel**: Preview Deployments comparten variables → o bien variables solo en *Production* y proyecto Supabase separado para pruebas, o activa *Deployment Protection*. Activa *Attack Challenge Mode*/Firewall si sufres tráfico anómalo.
7. **GitHub**: repo privado, Dependabot y secret scanning activados, protección de la rama `main`.
8. **Dependencias**: `npm audit` antes de cada despliegue; mantén `package-lock.json` en el repo; actualiza Next 15 a la última 15.x.

## C. Riesgos de negocio, legales y de privacidad
- **Vercel Hobby es solo para uso personal/no comercial.** Cobrar a clientes exige plan Pro. El "coste cero" vale hasta tener ingresos.
- **Supabase free**: pausa el proyecto tras ~1 semana sin actividad y no tiene backups con restauración puntual. Haz copias periódicas (`pg_dump`) antes de tener clientes de pago.
- **Datos personales (RGPD/leyes locales)**: el audio se envía a Groq (EE. UU.) y se guardan transcripciones y datos de clientes. Necesitas política de privacidad, aviso de uso del micrófono, contratos de encargado de tratamiento con Groq/Supabase/Vercel y confirmar sus políticas de retención. Si no necesitas la transcripción, elimina la columna `transcript`.
- **Validez fiscal**: un PDF generado así no es automáticamente una factura legal. Según el país (España: Verifactu; Perú: SUNAT; México: CFDI...) se exige software homologado/facturación electrónica. Consulta a un asesor antes de emitir facturas reales. Moneda (EUR) e IVA (21 %) están fijados por defecto: ajústalos a tu mercado.
- **Prompt injection**: lo dictado pasa por un LLM. Mitigado por validación Zod y porque solo afecta a la factura del propio usuario; el usuario revisa antes de guardar.
- **Derecho al olvido**: borrar el usuario en Supabase elimina sus datos en cascada; falta una pantalla para que lo haga él mismo.

## D. Pendiente / mejoras recomendadas
Límite global (no solo por usuario) frente a los 20 req/min de Groq; logs de auditoría; MFA opcional; portal de cliente con enlaces firmados y caducidad (cuando lo construyamos, es la superficie de ataque más sensible); tests de RLS con dos usuarios de prueba; pentest externo antes de cobrar.

## E. Prueba manual obligatoria tras desplegar
1. Crea dos usuarios A y B. Crea una factura con A. Con B: no debe verla en la lista.
2. Consola del navegador con sesión de B: `supabase.from('invoices').select()` solo devuelve lo de B.
3. Sin sesión, `curl -X POST https://TU-APP/api/parse` → redirige/401.
4. Haz 6 dictados en un minuto → el 6.º devuelve 429.
5. https://securityheaders.com sobre tu URL → nota A o superior.
6. Descarga el PDF y comprueba que los totales coinciden con la pantalla.
