# Despliegue paso a paso

## 1. Supabase
1. SQL Editor: si es proyecto nuevo, ejecuta `backend/supabase/schema.sql`. Luego, EN ORDEN, `backend/supabase/migrations/20261023_mobile_prod.sql`
   y `20261024_fiscal_sunat.sql` y `20261025_credit_notes.sql` (todas idempotentes). Copia la clave `service_role` (Project Settings → API) solo para Vercel.
2. Authentication → Email Templates: en **Confirm signup** y en **Magic Link** el cuerpo debe incluir
   `<p>Tu código: {{ .Token }}</p>` (la app solo usa código; sin esto los usuarios nuevos no pueden entrar).
3. Authentication → Providers → Email: caducidad del OTP 600 s. Activa CAPTCHA (Turnstile).
   Configura SMTP propio (el correo integrado permite muy pocos envíos/hora).
4. Database → Advisors → Security: debe salir sin errores.
5. Cuenta para revisores de las tiendas: Authentication → Users → Add user (correo + contraseña, "Auto confirm").
   La app tiene "Entrar con contraseña" solo para estas cuentas.

## 2. Backend (Vercel)
Variables en el proyecto: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `GROQ_API_KEY` (Sensitive),
`SUPABASE_SERVICE_ROLE_KEY` (Sensitive; solo módulo fiscal), `LYCET_URL` y `LYCET_API_KEY` (los da `infra/lycet/bootstrap.sh`),
`ALLOWED_ORIGINS` = URL del Flutter web (p. ej. `https://facturavoz-web.vercel.app`, sin barra final).
Sube `backend/`, redepliega. Prueba:
```
curl -i -X POST https://TU-API/api/parse            # 403 (sin sesión ni origen)
curl -i -X POST -H "Authorization: Bearer a.b.c" https://TU-API/api/parse   # 401
```

## 3. App Flutter (necesitas Flutter ≥ 3.35)
```
cd app
flutter create --org TU.DOMINIO.INVERSO --project-name facturavoz --platforms=android,ios,web .
dart run tool/post_create.dart       # permisos de micrófono/Internet, minSdk, nombre, sin backups
flutter pub get
flutter analyze && flutter test
```
`--org` define el ID de la app (p. ej. `pe.tuempresa.facturavoz`) y **no se puede cambiar** después de publicar.
Ejecutar en desarrollo (los valores NO son secretos, pero no pongas aquí service_role ni claves de Groq):
```
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=eyJ... \
            --dart-define=API_BASE_URL=https://TU-API.vercel.app \
            --dart-define=PRIVACY_URL=https://tu-sitio/privacidad
```
Compilar:
- **Web**: `flutter build web --release` + las mismas `--dart-define`; sube `build/web` a hosting estático
  copiando `web_hosting/vercel.json` dentro (cambia `TU-API`). La CSP va en modo *Report-Only*: abre la app,
  revisa la consola, y si no hay violaciones cambia la clave a `Content-Security-Policy`.
- **Android**: crea un keystore (`keytool -genkey -v -keystore upload.jks ...`, guárdalo fuera del repo), configura
  `android/key.properties` y firma; `flutter build appbundle --release --dart-define=...`. Play Console (pago único 25 USD).
- **iOS**: requiere Mac con Xcode y cuenta Apple Developer (99 USD/año): `flutter build ipa --release --dart-define=...`.

Tiendas: política de privacidad pública (URL), formulario de seguridad de datos / etiquetas de privacidad
(audio, correo, datos de clientes), eliminación de cuenta (ya está en Ajustes), credenciales de revisor (paso 1.5).

## 4. Verificación manual antes de vender
1. Dos usuarios A y B: B no ve las facturas de A (lista y consola).
2. 6 dictados en un minuto → el 6.º da "Demasiados dictados".
3. Factura emitida: no se puede editar/eliminar; "Eliminar mi cuenta" borra todo.
4. PDF: totales = pantalla; acentos y símbolo de moneda correctos.
5. https://securityheaders.com sobre API y web.

## 5. Facturación electrónica SUNAT
1. Instala Lycet en tu VPS de Oracle: `infra/lycet/INSTALACION.md`.
2. Pasa `infra/lycet/smoke-beta.sh` (SUNAT beta). 3. En la app: Datos del negocio (RUC, ubigeo, dirección, series) → Ajustes → Facturación electrónica.
4. Prueba factura, boleta y exonerada en beta. Detalles, límites y pendientes: `docs/FISCAL.md`.
