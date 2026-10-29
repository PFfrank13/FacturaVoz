# 4. Poner en marcha y operar

## 4.1 Probar en tu computadora (5 minutos)

Requisito: **Node.js 22.13 o superior** (o 24 LTS). En Windows, dentro de WSL (Ubuntu):

```bash
node --version          # debe decir v22.13 o mayor
cd ~/SOLVEX/solvex-plataforma/hub
npm test                # ~40 pruebas, todas en verde
npm run demo            # crea datos de demostración e imprime usuario, contraseña y clave 2FA
npm run dev             # abre http://localhost:8080/panel/
```

No hay `npm install`: el Hub no usa paquetes externos.

Para ver la web: en otra terminal, `cd ../sitio && python3 -m http.server 5500` y abre `http://localhost:5500`. El formulario y "Pagar mi servicio" hablan con el Hub local.

Para la cuenta demo, agrega la clave 2FA que imprime `npm run demo` en Google Authenticator ("Ingresar clave de configuración").

## 4.2 Servidor de producción

Recomendado: VPS con Ubuntu 24.04, 1 vCPU / 1 GB basta para empezar (el Hub puede compartir servidor con la barbería, pero es mejor uno aparte).

```bash
# 1) Usuario sin privilegios y Node 22
sudo adduser --system --group --home /opt/solvex solvex
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs caddy ufw

# 2) Código
sudo -u solvex git clone <tu-repo> /opt/solvex/plataforma
cd /opt/solvex/plataforma/hub
sudo -u solvex npm test

# 3) Secretos (UNA sola vez) y primer usuario
sudo -u solvex npm run setup        # crea .env con llaves nuevas (permiso 600)
sudo -u solvex nano .env            # PUBLIC_URL, SITE_ORIGINS, Culqi, correo
sudo -u solvex npm run crear-admin -- frank@solvex.pe "Frank Pineda"
```

**Guarda una copia del `.env` en un gestor de contraseñas.** Sin `DATA_KEYS` no se pueden leer los datos; sin `BACKUP_KEY` no se abren los respaldos.

Servicio con systemd (`/etc/systemd/system/solvex-hub.service`):

```ini
[Unit]
Description=Solvex Hub
After=network-online.target

[Service]
User=solvex
WorkingDirectory=/opt/solvex/plataforma/hub
ExecStart=/usr/bin/node --disable-warning=ExperimentalWarning src/server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production
# Endurecimiento
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/solvex/plataforma/hub/data /opt/solvex/plataforma/hub/backups
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
MemoryMax=512M

[Install]
WantedBy=multi-user.target
```

```bash
sudo -u solvex mkdir -p /opt/solvex/plataforma/hub/{data,backups}
sudo systemctl daemon-reload && sudo systemctl enable --now solvex-hub
sudo systemctl status solvex-hub
```

HTTPS con Caddy (`/etc/caddy/Caddyfile`), certificado automático:

```
hub.solvex.pe {
    encode gzip
    reverse_proxy 127.0.0.1:8080
}
```

Firewall: `sudo ufw allow OpenSSH && sudo ufw allow 80,443/tcp && sudo ufw enable`. SSH solo con llave (`PasswordAuthentication no`).

`.env` de producción: `TRUST_PROXY=1` (solo Caddy delante). Si además usas Cloudflare como proxy: `TRUST_PROXY=2`.

### Proteger el panel con Cloudflare Access (recomendado, gratis)

Con el dominio en Cloudflare: Zero Trust → Access → Applications → Self-hosted → `hub.solvex.pe/panel*` y `hub.solvex.pe/api/admin*` → política "correos de @solvex.pe" con código por correo. Así nadie fuera del equipo ve siquiera la pantalla de inicio de sesión. **No** protejas `/p/*`, `/v1/*`, `/webhooks/*` ni `/.well-known/*` (los usan clientes y sistemas).

## 4.3 Culqi y correo

1. Culqi: usa primero llaves de **prueba**. En el panel de Culqi registra el webhook `https://hub.solvex.pe/webhooks/culqi/<CULQI_WEBHOOK_SECRET>` (eventos de cargos y reembolsos). Habilita Yape si tu comercio lo tiene.
2. Correo: crea una cuenta en Resend o Brevo, verifica el dominio (SPF, DKIM, DMARC) y pon `EMAIL_PROVIDER`, `EMAIL_API_KEY`, `EMAIL_FROM`.
3. WhatsApp (opcional): cuenta de WhatsApp Business Cloud API, aprueba las plantillas de `03-integracion-productos.md`, y pon `WA_TOKEN` y `WA_PHONE_ID`.

Reinicia (`sudo systemctl restart solvex-hub`) y revisa **Configuración → Sistema**: no debe quedar ningún aviso amarillo.

### Comprobantes electrónicos e impuestos

Sigue `06-impuestos-y-comprobantes.md`, sección 6.8: régimen e inscripción de exportador (Configuración → Impuestos), `EINVOICE_PROVIDER=nubefact` con la ruta y token de DEMO, set de prueba y luego producción. Si usas un Merchant of Record, pon su secreto (`PADDLE_WEBHOOK_SECRET` o `LEMONSQUEEZY_WEBHOOK_SECRET`) y registra `https://hub.solvex.pe/webhooks/mor/paddle` (o `/lemonsqueezy`) en su panel. No protejas `/webhooks/*` con Cloudflare Access.

## 4.4 Respaldos

```bash
sudo -u solvex crontab -e
# cada día 03:15: respaldo cifrado y verificación de la auditoría
15 3 * * * cd /opt/solvex/plataforma/hub && /usr/bin/npm run respaldo >> backups/respaldo.log 2>&1
```

Copia `backups/` **fuera del servidor** (otro proveedor), por ejemplo con rclone a Cloudflare R2 o Backblaze B2:

```
30 3 * * * rclone copy /opt/solvex/plataforma/hub/backups r2:solvex-respaldos --include "*.db.enc"
```

Simulacro de restauración (hazlo una vez al mes):

```bash
npm run restaurar -- backups/hub-20261019-031500.db.enc /tmp/prueba.db
```
Debe decir `integridad: ok`. Para restaurar de verdad: detén el servicio, reemplaza `data/hub.db` por el restaurado (y borra `hub.db-wal`/`-shm`), inicia.

## 4.5 Rotación de llaves

| Llave | Cuándo | Cómo |
|---|---|---|
| Clave de API / secreto de webhook de una instancia | Si se filtra o al cambiar de equipo | Panel → Integraciones → Rotar secretos; actualizar el `.env` del producto. |
| Clave de un producto instalable | Si se filtra | Panel → licencia → Regenerar clave (desactiva todos los equipos). |
| Llave de datos (`DATA_KEYS`) | Cada año o si se sospecha filtración | Agregar `k2`, `DATA_KEY_ACTIVE=k2`, reiniciar, `npm run rotar-llave-datos`, quitar `k1`, reiniciar. |
| Llave de firma de licencias | Cada 1–2 años o si se filtra | Generar par nuevo; poner la pública en `LICENSE_EXTRA_PUBLIC_KEYS` y en `SOLVEX_PUBLIC_KEY_NEXT` de cada producto; cuando todos la tengan, cambiar `LICENSE_SIGNING_KEY`. |
| Contraseñas del equipo | Al salir alguien | Equipo → desactivar (cierra sus sesiones al instante). |

## 4.6 Si pasa algo (respuesta a incidentes)

1. **Contener**: desactiva usuarios sospechosos, rota la clave de la instancia afectada, activa Cloudflare Access si no lo tenías.
2. **Evaluar**: Auditoría → Verificar integridad; revisa accesos (`login.*`), pagos aprobados y licencias extendidas en las últimas horas.
3. **Preservar**: copia `data/hub.db` y los respaldos antes de tocar nada.
4. **Avisar**: si hubo datos personales comprometidos, la ley peruana exige comunicar a la Autoridad Nacional de Protección de Datos Personales y a los afectados en el plazo del reglamento (48 h para la autoridad). Prepara el texto con tu abogado.
5. **Corregir y documentar**: qué pasó, qué se cambió, cómo se evita.

## 4.7 Publicar la web

La carpeta `sitio/` es estática. En Cloudflare Pages o Netlify: sube la carpeta (el archivo `_headers` aplica las cabeceras de seguridad). Antes:

- En `sitio/js/config.js` completa `DIRECCION`, `WHATSAPP`, `CORREO` y `PRECIOS` (Culqi revisa que estén visibles). Si luego crean una empresa, cambia ahí `RAZON_SOCIAL` y `RUC`: se actualizan solos el pie, la privacidad, los términos, los reembolsos y el Libro de Reclamaciones.
- Si el Hub no está en `hub.solvex.pe`, cambia esa dirección en `config.js` **y** en la etiqueta `Content-Security-Policy` de `index.html`, `privacidad.html` y `reclamaciones.html`.
- En el `.env` del Hub, `SITE_ORIGINS` debe incluir la dirección exacta de la web.

## 4.8 Actualizaciones

```bash
cd /opt/solvex/plataforma && sudo -u solvex git pull
cd hub && sudo -u solvex npm test && sudo -u solvex npm run respaldo && sudo systemctl restart solvex-hub
```
Las migraciones de la base se aplican solas al iniciar.
