# Publicar FacturaVoz en Google Play (lista de verificación)

Antes de publicar, resuelve esto **en orden**. Nada de esto se puede cambiar después sin costo.

## 0. Requisito de Google para cuentas personales nuevas
Según la ayuda oficial de Play Console, una cuenta de desarrollador **personal nueva** debe hacer una **prueba cerrada con al menos 12 testers que se mantengan inscritos 14 días seguidos** antes de pedir acceso a producción (si la creas como organización con verificación, revisa en Play Console si te aplica). Plan realista: consigue 12 correos de Gmail (amigos, clientes), súbelos a la prueba cerrada y espera 14 días. Fuente: https://support.google.com/googleplay/android-developer/answer/14151465

## 1. Identidad de la app (no se cambia luego)
- **ID de la app** (`applicationId`): hoy es `pe.tuempresa.facturavoz`. Debe ser uno tuyo y definitivo (por ejemplo `pe.tunegocio.facturavoz`). Se fija al crear el proyecto con `flutter create --org`; si aún no publicaste, puedes regenerar `android/` con otro `--org`.
- **Nombre visible**, **ícono** y **pantalla de inicio**: usa tu logo real (no el de ejemplo).

## 2. Firma de la versión de producción
1. Crea tu llave **una sola vez** y guárdala fuera del repositorio (y con copia de respaldo; si la pierdes no puedes actualizar la app):
   ```
   keytool -genkey -v -keystore facturavoz-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Crea `android/key.properties` (NO lo subas a GitHub; ya está ignorado si usas el `.gitignore` del proyecto):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=C:/ruta/segura/facturavoz-upload.jks
   ```
3. Configura `android/app/build.gradle` para usar esa firma en `release` y compila un paquete para la tienda:
   ```
   flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=...
   ```
   (Google Play pide `.aab`, no `.apk`.)

## 3. Versionado
En `pubspec.yaml`: `version: 1.0.0+1`. El número después de `+` (versionCode) **debe subir en cada subida** a Play (`+2`, `+3`...).

## 4. Ficha de la tienda
- **Política de privacidad pública** (URL): obligatoria. Debe decir que se usa el micrófono para dictar, que el audio se envía a un servicio de transcripción y no se guarda en el teléfono, qué datos se guardan (correo, datos del negocio, facturas) y cómo borrar la cuenta (Ajustes → Eliminar cuenta). Pásala con `--dart-define=PRIVACY_URL=https://...`.
- **Formulario "Seguridad de los datos"**: declara correo, datos financieros/facturas, audio de voz (procesado, no vendido) y que se pueden eliminar.
- **Permisos**: solo micrófono (dictado) e internet.
- **Cuenta de prueba para revisores**: crea un usuario con contraseña en Supabase (Authentication → Users → Add user, con *Auto Confirm User*) y entrégalo en "Acceso a la app". La app permite entrar con contraseña.
- **Capturas** (mínimo 2 de teléfono) y descripción corta/larga en español.

## 5. Antes de dar "Enviar a revisión"
- [ ] Ejecutadas las migraciones SQL 26 a 30 en Supabase de producción.
- [ ] `GROQ_API_KEY` rotada y guardada solo en Vercel (nunca en la app ni en GitHub).
- [ ] SMTP propio en Supabase (el correo gratuito de Supabase limita los envíos por hora) y `RESEND_API_KEY` si usas copias por correo.
- [ ] Prueba beta de SUNAT completa (factura, boleta y nota de crédito aceptadas).
- [ ] Probado en un teléfono real con `--release`, sin conexión y con conexión lenta.
- [ ] Sin claves en el repositorio (`git log -p | grep -i "service_role\|gsk_\|re_"` no debe devolver nada).

## 6. Después de publicar
- Monitorea errores en Vercel (Logs) y en Supabase (Logs → API/Auth).
- Plan gratuito de Vercel (Hobby) guarda solo 1 hora de logs: si vendes el producto, considera un plan que retenga más.
