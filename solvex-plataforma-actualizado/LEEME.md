# Solvex · Plataforma v3

Todo lo que necesita Solvex para vender, cobrar y controlar las licencias de **todos** sus sistemas (barbería, restaurante, a medida, instalables), con corte y reactivación automáticos.

```
solvex-plataforma/
├── hub/                       Solvex Hub: servidor de licencias + cobros + panel de administración (ERP)
│   ├── src/                   código del servidor (Node 22+, sin paquetes externos)
│   ├── panel/                 panel del equipo (se abre en https://TU-HUB/panel/)
│   ├── scripts/               setup, crear-admin, demo, respaldo, restaurar, verificar-auditoria, rotar-llave-datos
│   └── test/                  48 pruebas automáticas (npm test)
├── sitio/                     página web pública (estática), separada del panel
├── integraciones/
│   ├── laravel-barberia/      kit listo para conectar la barbería (Laravel 13) — ver su LEEME.md
│   └── node/                  cliente de licencias para productos en Node
└── docs/
    ├── 01-analisis-seguridad.md   hallazgos del sistema anterior (críticos, altos, medios) y cómo se resolvieron
    ├── 02-arquitectura.md         piezas, datos, estados de licencia, reglas de dinero, seguridad por capas
    ├── 03-integracion-productos.md cómo conectar cualquier producto (tokens, webhooks, API, plantillas WhatsApp)
    ├── 04-operacion.md            instalar en servidor, HTTPS, respaldos, rotación de llaves, incidentes, publicar la web
    ├── 05-casos-limite.md         qué hace el sistema en cada situación posible (y "imposible")
    └── 06-impuestos-y-comprobantes.md  IGV, exportación, boletas/facturas electrónicas y Merchant of Record
```

## Probar ahora mismo

Requisito: Node.js 22.13+ (en Windows, dentro de WSL).

```bash
cd hub
npm test        # todas las pruebas en verde
npm run demo    # datos de demostración; imprime usuario, contraseña y clave 2FA
npm run dev     # http://localhost:8080/panel/
```

## Lo más importante que cambió

1. **El panel ya no vive dentro de la web pública.** Antes cualquiera podía entrar desde la consola del navegador y leer o cambiar clientes y licencias. Ahora el acceso se valida en el servidor, con doble factor obligatorio.
2. **Una sola fuente de verdad.** Ya no hay que exportar JSON ni usar `curl`: el Hub corta, avisa y reactiva solo, y le avisa al sistema del cliente en segundos con un mensaje firmado.
3. **Multi-producto.** Cada sistema nuevo es un producto con sus planes; se agrega desde el panel sin programar.
4. **Datos cifrados y auditoría a prueba de manipulación.**
5. **Impuestos y comprobantes.** IGV 18 % para el Perú, exportación de servicios al 0 % para el extranjero, boleta o factura electrónica por cada pago (Nubefact) y webhooks de Paddle/Lemon Squeezy para vender en otros países.

Empieza por `docs/01-analisis-seguridad.md` y luego `docs/04-operacion.md`.

## Pendiente de tu lado

- Completar en `sitio/js/config.js` la dirección fiscal, el WhatsApp, el correo y los precios (titular y RUC ya están). La web ya tiene términos y condiciones y política de cancelación y reembolsos, que Culqi revisa.
- Llaves de Culqi (primero de prueba), proveedor de correo y, si quieres, WhatsApp Business.
- Revisión legal: política de privacidad, contrato de encargo de tratamiento con cada barbería, Libro de Reclamaciones, inscripción del banco de datos ante la ANPD.
- Comprobantes electrónicos: cuenta en Nubefact (ruta y token) y afiliación como emisor electrónico. Ver `docs/06-impuestos-y-comprobantes.md`, sección 6.8.
- Con tu contador: régimen tributario e inscripción en el Registro de Exportadores de Servicios (Configuración → Impuestos).
- Prueba de penetración externa antes de crecer.
