# Lycet en tu VPS de Oracle (SUNAT)

> Para probar desde tu PC sin servidor: `docs/LOCAL_DOCKER.md`.

Lycet recibe el JSON de la factura, genera el XML UBL 2.1, lo firma con el certificado digital y lo envía a SUNAT.
Aquí corre detrás de Caddy (HTTPS automático): **solo Caddy es público** y exige usuario/clave larga.

## 0. Antes de empezar
- Un nombre de dominio (o subdominio) con registro **A** hacia la IP pública del VPS. Sin dominio, sirve
  `IP-con-guiones.sslip.io` (ej. `129-146-10-20.sslip.io`).
- Ubuntu 22.04/24.04. Funciona en x86 y en Ampere (ARM); si el *build* falla en ARM, usa una instancia x86 (AMD) gratuita.

## 1. Red de Oracle (consola OCI)
Networking → VCN → Security List (o NSG): permite entrada TCP **80 y 443** desde 0.0.0.0/0 y **22 solo desde tu IP**.
En Ubuntu de Oracle además hay reglas locales:
```
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80  -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```
## 2. Docker
```
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER   # vuelve a entrar por SSH
```
## 3. Instalar
```
git clone <tu-repo> && cd <tu-repo>/infra/lycet      # o copia esta carpeta con scp
./bootstrap.sh            # crea .env con secretos aleatorios y te muestra LYCET_URL y LYCET_API_KEY
docker compose up -d --build
curl https://TU-DOMINIO/health            # → ok
```
Copia `LYCET_URL` y `LYCET_API_KEY` a Vercel (Environment Variables, *Sensitive*) junto con
`SUPABASE_SERVICE_ROLE_KEY` y redepliega el backend.

## 4. Prueba contra SUNAT BETA (obligatoria antes de cualquier cliente real)
```
LYCET_URL=https://TU-DOMINIO LYCET_API_KEY=... ./smoke-beta.sh
```
Debe imprimir `success: True` y `CDR code '0'`. Si falla, no sigas: revisa `docker compose logs lycet`.
Cuando pase, prueba también **boleta**, una **nota de crédito** (ruta `/api/v1/note/send`, ya permitida en Caddy) (tipoDoc 03, serie B001) y una **exonerada** desde la app en modo *beta*.

## 5. Cada cliente (empresa) que emite
En SUNAT Operaciones en Línea (SOL), con su Clave SOL, el titular debe (confirma los pasos vigentes en el portal de SUNAT o con su contador):
1. Afiliarse a comprobantes electrónicos con el sistema **«SEE – Del contribuyente»**.
2. Tener un **certificado digital** vigente (.pfx) registrado/aceptado por SUNAT.
3. Crear un **usuario SOL secundario** con permiso de emisión electrónica (NO usar la clave SOL principal).
4. Registrar las **series** que usará (F001, B001…) — deben coincidir con las de Ajustes en la app.

En la app: Ajustes → *Facturación electrónica SUNAT* → RUC, usuario SOL secundario, su clave y el .pfx.
Los secretos viajan por HTTPS directo a tu VPS y **no se guardan en Supabase**.

## 6. Pasar de beta a producción
La app registra a cada empresa con su entorno (`beta`/`prod`). Una empresa en `prod` envía a
`e-factura.sunat.gob.pe`. Para cambiarla, repite el registro en la app con «Producción». Mantén
tu propia cuenta de pruebas en beta.

## 7. Operación y seguridad
- **Respaldos** (contienen certificados y claves SOL): `echo "frase-larga" | sudo tee /root/.lycet-backup-pass && sudo chmod 600 /root/.lycet-backup-pass`
  y en cron: `15 3 * * * /ruta/infra/lycet/backup.sh`. Copia los `.enc` fuera del VPS (p. ej. Oracle Object Storage con rclone). Prueba restaurar una vez.
- **Acceso**: SSH solo con llave y desde tu IP; sin contraseña; `unattended-upgrades` activo. Quien entre al VPS puede leer los certificados.
- **Disco**: activa cifrado del volumen en OCI si tu plan lo permite.
- **Imagen**: la imagen oficial de Lycet usa PHP 8.1/Alpine 3.17 (fuera de soporte). El riesgo se reduce porque no es público y Caddy filtra rutas,
  pero planifica migrar a PHP 8.3 (el código de Greenter genera XML correctamente en 8.3; ver `docs/FISCAL.md`) y reconstruir tras probar en beta.
- **Actualizar Lycet**: cambia el hash del commit en `docker-compose.yml`, `docker compose up -d --build`, repite `smoke-beta.sh`.
- **Si sospechas filtración**: rota `.env` (borra y ejecuta `bootstrap.sh`), cambia `LYCET_API_KEY` en Vercel y pide a los clientes cambiar su clave SOL secundaria y renovar el certificado.
- **Conservación**: la ley exige conservar XML y CDR (hoy se guardan en la tabla `fiscal_documents`); respalda Supabase.
