# 1. Análisis del sistema anterior (panel + solvex-billing)

Revisión hecha sobre `solvex_4.zip` (página `index.html` con el panel incrustado en `#admin` y el backend `solvex-billing`) y sobre la especificación `Proyecto_Barberia_v2.docx`. Cada hallazgo indica **qué podía pasar** y **cómo queda resuelto** en Solvex Hub v3.

Escala: **Crítico** = cualquiera desde internet compromete datos o dinero. **Alto** = daño serio con poco esfuerzo o errores de dinero. **Medio** = debilita las defensas o la operación. **Bajo** = mejora recomendada.

## Resumen

| Gravedad | Cantidad | Estado en v3 |
|---|---|---|
| Crítico | 6 | Todos corregidos |
| Alto | 10 | Todos corregidos |
| Medio | 10 | 9 corregidos, 1 mitigado |
| Bajo | 5 | Corregidos |

## Críticos

| # | Hallazgo | Qué podía pasar | Corrección en v3 |
|---|---|---|---|
| C1 | **El "login" del panel se validaba en el navegador.** El usuario (`frank`) y el hash de la contraseña estaban en el código de la página pública; la sesión era un número en `sessionStorage`. | Cualquiera abría la consola del navegador, escribía `sessionStorage.setItem('slx_sess', Date.now())`, entraba a `#admin` y tenía el panel completo. El hash publicado además permitía probar contraseñas sin límite fuera de línea. | El panel ya no está en la web pública. Lo sirve el Hub; el acceso se valida en el servidor (contraseña con scrypt + **doble factor obligatorio**), sesión en cookie `HttpOnly`, `Secure`, `SameSite=Strict`, con token CSRF. Pruebas: `02-auth.test.js`. |
| C2 | **Visitantes y panel compartían la misma base de datos** (`window.claude.use('db')`): el formulario de contacto público escribía ahí y el panel leía y escribía clientes, licencias y pagos en el mismo almacén. | Un visitante podía leer todos los clientes (RUC, celulares, correos) y **modificar licencias o marcar pagos como aprobados** desde la consola. | Base de datos solo en el servidor. El sitio público solo puede llamar a 4 rutas públicas muy acotadas (solicitud, catálogo, pedir enlace de pago, libro de reclamaciones), con límite de envíos. |
| C3 | **Credenciales por defecto publicadas** (`Frank`/`Frank` en el LEEME) y la contraseña nueva se guardaba en `localStorage` de ESE navegador. | En cualquier otro navegador o en modo incógnito seguía funcionando `Frank`/`Frank`. | No hay credenciales por defecto. El primer usuario se crea en la consola del servidor con contraseña temporal aleatoria; al entrar debe cambiarla y activar 2FA. |
| C4 | **Los permisos por rol se calculaban en el navegador** y si la persona no estaba en "Equipo", `can()` devolvía `true` para todo. | Cualquier sesión tenía todos los permisos; un rol "Soporte" podía aprobar pagos o suspender licencias modificando una variable. | Permisos verificados en cada ruta del servidor (`requireUser({perm})`), 6 roles fijos, acciones delicadas con **confirmación 2FA** (sudo de 10 min). |
| C5 | **Dos fuentes de verdad sincronizadas a mano**: el panel exportaba un JSON y había que subirlo con `curl` al backend de cobros. | El corte y la reactivación no eran automáticos de verdad: dependían de que alguien exportara. Un snapshot viejo podía reescribir claves y estados (`suspendido` con corte automático se convertía en `activo`). | Un solo sistema (el Hub) con una sola base. El estado se calcula en el momento a partir de las fechas; cortes, gracia y reactivaciones ocurren solos y se avisan al producto en segundos. |
| C6 | **Token de administración único y estático** (`ADMIN_TOKEN`) usado desde el navegador del panel, con CORS `*` si `PANEL_ORIGINS` estaba vacío. | Si se filtraba (equipo compartido, extensión del navegador, XSS), daba control total y no se sabía quién lo usó. | Cuentas personales; cada acción queda firmada en la auditoría con persona, IP y fecha. Sin CORS en la API del panel (mismo origen). |

## Altos

| # | Hallazgo | Qué podía pasar | Corrección en v3 |
|---|---|---|---|
| A1 | Claves de licencia generadas con `Math.random()` (predecible) y guardadas en claro. | Adivinar o filtrar claves válidas. | Claves con `crypto.randomBytes`; en la base solo su hash. Se muestran una vez; si se pierden, se regeneran. |
| A2 | La clave viajaba en la URL (`GET /api/license/CLAVE`). | Queda en logs de proxies, CDN y servidores. | Las instancias se autentican con clave de API en la cabecera `Authorization`; la clave del producto instalable va en el cuerpo de un POST. |
| A3 | La firma de la licencia cubría solo estado y fecha, sin destinatario, y se aceptaba hasta 48 h. | Una respuesta "activa" capturada servía 48 h aunque ya estuviera cortada; un proxy podía cambiar campos no firmados. | Token JWS Ed25519 que firma **todo** el contenido, con destinatario (`aud`), id único y vencimiento corto que **nunca supera la fecha de corte**. Verificado en PHP y Node. |
| A4 | Cortes calculados con la fecha UTC. | En Lima el servicio se cortaba a las 19:00 del día anterior (5 horas antes de lo pagado). | Cada licencia tiene zona horaria (por defecto `America/Lima`); vence a las 23:59:59 locales. |
| A5 | Ciclos de 30/365 días, pagos insuficientes "perdidos" (`floor`), máximo 12 periodos, reembolso parcial tratado como total. | Fechas que se corren cada mes, dinero cobrado que no extendía nada, reclamos. | Meses calendario con día ancla; pagos parciales acumulan; excedente pasa a **saldo a favor** que se aplica solo; reversos exactos. |
| A6 | El enlace de pago usaba el código secuencial (`/pagar?ref=SLX-0001`). | Recorriendo códigos se veían nombre del cliente y montos de todos. | Enlace por cobro con secreto de 256 bits (`/p/<token>`), imposible de adivinar. Pedir el enlace en la web exige código + RUC/DNI y **se envía solo a los contactos registrados**, con la misma respuesta exista o no. |
| A7 | Datos personales en claro (navegador y SQLite). | Robo del archivo o del navegador = filtración completa. | Documento, correo, celular, dirección, notas, solicitudes y reclamos cifrados con AES-256-GCM, atados a su fila; búsqueda por índice ciego. Prueba: el archivo de la base no contiene ningún dato personal legible. |
| A8 | Auditoría editable/borrable (en el navegador) o tabla sin protección. | Borrar el rastro de un fraude. | Bitácora encadenada con HMAC y triggers de solo inserción; la verificación detecta ediciones y borrados aunque se salten los triggers. |
| A9 | Pagos manuales aprobables por cualquiera con el panel abierto, sin motivo ni control. | Fraude interno o error sin responsable. | Aprobación solo con permiso de Finanzas, control de **cuatro ojos** opcional, motivo obligatorio para rechazar/anular/extender, recibos correlativos, pagos cerrados inmodificables (trigger). |
| A10 | La revisión de vencimientos corría en el navegador al abrir el panel. | Si nadie abría el panel, nada se marcaba ni se avisaba. | Programador en el servidor cada minuto + estado calculado en cada consulta. |

## Medios

| # | Hallazgo | Corrección |
|---|---|---|
| M1 | Bloqueos de intentos solo en memoria y por IP. | Bloqueo por cuenta guardado en la base (5 fallos → 15 min, crece) + límite por IP. |
| M2 | HTTPS dependía de configurar bien `TRUST_PROXY`. | En producción el Hub escucha solo en `127.0.0.1` detrás de Caddy/Nginx y rechaza lo que llegó por http. HSTS con preload. |
| M3 | 3 dependencias npm (una nativa) = superficie de cadena de suministro. | **Cero dependencias**: solo módulos de Node (http, sqlite, crypto). |
| M4 | Scripts en línea y CSP débil en la web y en `/pagar`. | CSP estricta sin `unsafe-inline` para scripts en el panel, la página de pago y la web. |
| M5 | Faltaban Libro de Reclamaciones y política de privacidad; el formulario no pedía consentimiento. | Agregados (con plazos en días hábiles y respuesta inmutable) y casilla de autorización. **Revisar textos con un abogado.** |
| M6 | Sin respaldos ni restauración probada. | `npm run respaldo` (cifrado, rotación de 30 copias) y `npm run restaurar`; procedimiento en `04-operacion.md`. |
| M7 | Sin rotación de llaves. | Rotación de llave de datos, de firma (anuncio previo por `kid`), de claves de instancia y de secretos de webhook. |
| M8 | Avisos de WhatsApp sin plantillas aprobadas. | Plantillas definidas (`slx_*`) para aprobar en Meta; correo como canal principal. |
| M9 | Sin aviso de pago "tardío" ni de pagos dobles. | Pago sobre cobro pagado o anulado → saldo a favor + alerta en el panel. |
| M10 | Límite de envíos del formulario solo en el navegador. | Límite en servidor, trampa para robots y opción de Cloudflare Turnstile. **Mitigado** (un atacante con muchas IPs aún puede enviar spam; Turnstile lo reduce). |

## Bajos

| # | Hallazgo | Corrección |
|---|---|---|
| B1 | Menú inaccesible en celular (los enlaces se ocultaban sin botón). | Menú hamburguesa accesible. |
| B2 | El panel cargaba fuentes de Google (filtra uso del panel a terceros). | El panel no carga nada externo. |
| B3 | Mensajes de error con detalles internos en algunos casos. | Errores uniformes con código de seguimiento. |
| B4 | Sin protección contra caracteres de control invisibles en textos. | Se eliminan (incluye control bidireccional que permite textos engañosos). |
| B5 | Sin `robots`/`noindex` en enlaces de pago. | `noindex` y `Referrer-Policy: no-referrer`. |

## Lo que NO es posible (y cómo se maneja)

- **"Impenetrable" no existe.** Lo que sí existe es *defensa en capas*: aunque una capa falle, la siguiente frena. Antes de cobrar a gran escala conviene una **prueba de penetración externa**.
- **Software instalado en la computadora del cliente**: quien controla esa máquina puede intentar modificar el programa. La firma impide *falsificar* licencias, no impide *parchar* el programa. Por eso la barbería es SaaS (la controlas tú) y en productos instalables la lógica valiosa debe vivir en el servidor.
- **Verificar Yape o transferencias automáticamente** sin la API del banco no se puede. Opciones: cobrar con Culqi (Yape incluido, automático) o verificar el número de operación a mano (con cuatro ojos).
- **Corte exacto si el producto no recibe el aviso**: el token ya trae la fecha de corte, así que el producto corta a tiempo aunque no llegue el webhook. La **reactivación** sí necesita contacto con el Hub (webhook o consulta cada 5 min).
- **Si alguien obtiene el servidor completo y el `.env`**, puede leer los datos. Mitigaciones: disco cifrado del proveedor, acceso SSH solo con llave, Cloudflare Access delante del panel, respaldos fuera del servidor y el anclaje externo de la cabeza de la auditoría.

## Riesgos residuales y siguientes pasos

1. Prueba de penetración externa antes de pasar de ~50 clientes.
2. Validar con abogado: política de privacidad, contrato de encargo de tratamiento con cada barbería, Libro de Reclamaciones, inscripción del banco de datos ante la ANPD.
3. Comprobantes electrónicos SUNAT: integrar un proveedor OSE/PSE (Nubefact, Facturador SUNAT u otro) a partir de los pagos aprobados.
4. Cloudflare Access (gratis hasta 50 usuarios) delante de `/panel` y `/api/admin`.
5. Monitoreo externo de `/health` y alerta si el respaldo diario no se generó.
