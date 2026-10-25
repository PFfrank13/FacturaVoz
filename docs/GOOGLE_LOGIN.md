# Inicio de sesión con Google (sin paquetes nativos)

Usa el flujo OAuth de Supabase en el navegador y vuelve a la app por un enlace profundo.

1. Google Cloud Console → APIs y servicios → Credenciales → **ID de cliente de OAuth** tipo **Aplicación web**.
   - URI de redireccionamiento autorizado: `https://<TU-PROYECTO>.supabase.co/auth/v1/callback`
   - Copia el Client ID y el Client secret.
2. Supabase → Authentication → Providers → **Google**: actívalo y pega Client ID y secret.
3. Supabase → Authentication → URL Configuration → **Redirect URLs**: agrega `com.facturavoz.app://login-callback`
   (para la versión web agrega también la URL de tu web).
4. En `app/`: `dart run tool/post_create.dart` (agrega el enlace profundo al Android/iOS) y compila con
   `--dart-define=GOOGLE_LOGIN=true` además de los defines habituales.
5. Si el correo de Google coincide con uno ya registrado por código/contraseña, Supabase enlaza ambas cuentas.

Apple Sign-In requiere cuenta de Apple Developer de pago; se agrega igual cuando publiques en iOS.
