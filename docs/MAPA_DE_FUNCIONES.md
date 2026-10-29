# Mapa de funciones de FacturaVoz v3

**Nada se borró.** Todo lo que existía sigue ahí; en v3 se **reubicó** para que cada rubro vea primero lo suyo.
La única puerta a TODAS las funciones es el botón **Menú** (Inicio, arriba a la derecha; también en el avatar),
con buscador por texto y por voz. Lo que no es de tu rubro está en Menú → **Otras funciones**.

## Cambios de lugar (función → antes → ahora → cómo se llega)

| Función | Antes (v2) | Ahora (v3) | Cómo se llega |
|---|---|---|---|
| Barra de abajo | 5 destinos fijos (modo simple/completo) | **4 destinos de tu rubro** + micrófono | Siempre visible (ver `docs/RUBROS.md`) |
| Lista de comprobantes (búsqueda, filtros, "por cobrar") | Pestaña Inicio | **Menú → Vender → Comprobantes** | Menú · buscador ("boletas") |
| Inicio | Lista + tarjetas + resumen | **Inicio limpio**: saludo, hoy, meta del mes, 1–2 sugerencias del Copiloto, 3–4 accesos del rubro | Pestaña Inicio |
| Todas las funciones | Avatar → Todas las funciones | **Menú** (por áreas del rubro, con candados del plan). La lista antigua sigue en Ajustes → Todas las funciones | Inicio → Menú · Avatar → Menú |
| Facturar por voz / Caja rápida / Cuaderno / Cotización | Botones separados | **Nueva venta** (una puerta con las 4 formas) | Inicio → Nueva venta · micrófono |
| Cobranza + Fiados + Avisos Yape/Plin | 3 pantallas | **Lo que me deben** (pestañas) | Barra "Cobrar"/"Cobranza"/"Pensiones" · Menú |
| Mi negocio + ¿Cuánto me queda? + Reportes + Comisiones | 4 pantallas | **Mi negocio** (pestañas) | Barra "Negocio" · Menú → Mi negocio (todo junto) |
| Alertas, Bitácora, PIN, Papelera, Huella | Repartidos | **Ajustes → Seguridad** | Ajustes → Seguridad · Menú → Ajustes |
| Escanear comprobante de proveedor | Cobrar y pagar | **Dentro de Gastos** (botón escanear) y en Menú | Menú → Plata → Gastos |
| Tipo de negocio | Ajustes → Tu negocio | **Rubro** con vista previa | Ajustes → Rubro · Menú → Ajustes → Cambiar de rubro |
| "Otro / personalizado" | Plantilla | **Eliminado de las opciones**: se pide elegir rubro (datos intactos) | Aparece solo una vez al dueño |
| Modo simple | Ajustes | Solo para empresas sin rubro. Nuevo **Modo Fácil** (letras grandes, por persona) | Ajustes → Modo Fácil · presentación |
| Presentación inicial | Ajustes → Tipo de negocio | Ajustes → Menú → *Ver la presentación otra vez* | Menú → Ajustes |
| Importar Excel/CSV de facturas | Mi negocio → Importar | Igual; **si el Excel tiene varias hojas** se abre el **importador de libro** (clientes + comprobantes + detalle + catálogo) | Menú → Mi negocio → Importar datos · historial con "Deshacer" |
| Ayuda | — | **Ajustes → Ayuda por WhatsApp** (con versión, rubro y plan) | Ajustes |

## Funciones nuevas en v3

| Función | Rubro principal | Dónde |
|---|---|---|
| Reposición inteligente | Bodega | Inicio · Menú → Tu bodega |
| Cuentas y costo por plato (cuenta dividida, propina, margen) | Restaurante | Inicio · Menú → Tu local |
| Mensualidades y corte por mora | Servicios técnicos | Inicio · Menú → Tu servicio |
| Paquetes y sesiones (no-shows) | Salón, consultorio, academia | Inicio · Menú |
| Historial privado del paciente | Consultorio | Inicio · Menú → Tu consulta |
| Les toca volver (recordatorios) | Taller, salón, consultorio | Menú |
| Buscar por placa | Taller | Inicio · Menú → Tu taller |
| Crédito por cliente | Mayorista | Inicio · Menú → Tu distribuidora |
| Pensiones pendientes por grupo | Academia | Inicio · Menú → Tu academia |
| Margen por obra (+ gastos por obra) | Construcción | Inicio · Menú → Tus obras |
| Importador de libro Excel con "Deshacer" | Todos | Menú → Importar datos |
| Voz premium del Copiloto | Pro/Empresa | Copiloto → "Escuchar" o preguntar hablando |
| Datos de práctica del rubro | Todos | Ajustes → Datos de práctica |
| Tienda: pago con Yape/Plin, ficha para Google, "instalar" en el celular | Todos con tienda | `/tienda/<slug>` |

---

# Referencia v2 (se mantiene; los lugares cambiados están en la tabla de arriba)


Dónde está cada cosa en la app, qué plan la incluye y quién la ve. **Nada se borró**: lo que antes estaba en otro
lugar sigue existiendo y se puede abrir desde **Todas las funciones** (avatar → Todas las funciones) o desde el
**buscador** (lupa arriba a la derecha, también por voz).

## La barra de abajo (máximo 5 + micrófono)

| Modo | Botones | Micrófono |
|---|---|---|
| **Completo** | Inicio · Vender · 🎙 · Clientes · Cobrar · Negocio | Toque: vender por voz · Mantener: Copiloto |
| **Simple** (recomendado para empezar) | Vender · Clientes · 🎙 · Cobrar · Ajustes | igual |
| **Técnico** (rol) | Mis trabajos · Agenda · 🎙 · Clientes · Ajustes | Copiloto |

- El modo se elige en la presentación inicial o en **Ajustes → Tu negocio → Modo simple**.
- Si el rol no puede vender o cobrar, esos botones no aparecen. Si no puede ver dinero, "Negocio" se cambia por "Ajustes".
- **Avatar** (círculo con tu inicial): Ajustes, SUNAT, Datos del negocio, Equipo, Mi plan, Empresas, Todas las funciones, Cerrar sesión.
- **Lupa**: busca clientes (nombre, DNI/RUC, celular), comprobantes (número, cliente), productos y funciones. Botón 🎙 para buscar hablando.
- **Atajos del ícono** (mantener presionado el ícono de la app en Android/iPhone): Vender por voz, Buscar, Fiados, Copiloto.

## Funciones, ubicación, plan y rol

Columna *Plan*: B = Básico, P = Pro, E = Empresa (propuesta en `docs/facturavoz-planes.json`). Columna *Rol*:
quién la ve (Dueño y Administrador ven todo).

### Vender
| Función | Dónde | Plan | Rol |
|---|---|---|---|
| Facturar/boletear por voz (dictado multiproducto, DNI/RUC en la voz) | Micrófono · Vender | B P E | Cajero, Vendedor, Finanzas |
| Venta rápida (caja/POS, código de barras, promos, cupón) | Vender → Venta rápida | B P E | Cajero, Vendedor |
| Cotizaciones y pedidos web (antes pestaña "Cotizar") | Vender → Cotizaciones y pedidos | B P E | Vendedor, Cajero |
| Del cuaderno a la factura (foto → venta) | Vender | P E | Cajero, Vendedor |
| Facturación recurrente | Vender | P E | Finanzas |
| Productos e inventario (foto, código de barras, por mayor) | Vender · Ajustes | B P E | Todos ven; editan Finanzas/Admin |
| Tienda en línea (carrito, categorías, WhatsApp, página por producto) | Vender · Ajustes | P E | Admin |
| Carta QR y comandas (pedidos por mesa en vivo) | Vender | P E | Todos |
| Precios y promociones, cupones | Vender | P E | Admin, Finanzas |
| Puntos y fidelización, cumpleaños | Vender | P E | Todos |

### Clientes y trabajos
| Función | Dónde | Plan | Rol |
|---|---|---|---|
| Clientes con Ficha 360 (mapa, deuda, puntaje de pago, historial, cotizaciones, trabajos, equipos, notas, fotos) | Clientes | B P E | Todos (técnico: solo sus clientes) |
| Botones Facturar · Cotizar · Cobrar · Agendar · WhatsApp | Ficha del cliente | según función | según rol |
| Recordatorios inteligentes ("Para hoy": visitas, atrasados, cumpleaños, fiados vencidos, clientes que no vuelven) | Clientes · Inicio | B P E | Todos |
| Trabajos (tablero por pasos, arrastrar, técnico asignado, fotos antes/después, materiales, hitos de obra) | Clientes → Trabajos | P E | Técnico: solo los suyos |
| Agenda y citas, reservas en línea | Clientes → Agenda | P E | Todos |
| Encuestas de satisfacción | Clientes · comprobante → Encuesta | P E | Admin |
| Análisis de clientes (Clientes 360 anterior) | Clientes · Negocio | B P E | Finanzas |

### Cobrar y pagar
| Función | Dónde | Plan | Rol |
|---|---|---|---|
| Cobranza (por cobrar, recordatorios, enlace de cobro) | Cobrar | B P E | Cajero, Finanzas |
| Libreta de fiados | Cobrar | B P E | Cajero, Finanzas |
| Caja y cierre del día (reporte por correo) | Cobrar | B P E | Cajero, Finanzas |
| Avisos de Yape/Plin (pegar notificación → cobro) | Cobrar | B P E | Cajero |
| Conciliación bancaria (Excel/CSV del banco) | Cobrar · Negocio | E | Finanzas |
| Gastos y escanear comprobante de proveedor | Cobrar | B P E | Finanzas |

### Mi negocio
| Función | Dónde | Plan | Rol |
|---|---|---|---|
| Ganancia, flujo de caja, IGV, radar de stock | Negocio | B P E | Finanzas |
| ¿Cuánto me queda? (impuestos estimados por régimen) | Negocio · Inicio | B P E | Finanzas |
| Reportes y Excel | Negocio | B P E | Finanzas |
| Ventas por vendedor y comisiones | Negocio | P E | Admin/Finanzas (vendedor ve las suyas) |
| Importar datos (.xlsx/.csv) | Ajustes → Importar | B P E | Finanzas, Admin |

### Control del dueño (antifraude)
| Función | Dónde | Plan | Rol |
|---|---|---|---|
| Alertas en vivo (anulaciones, descuentos ≥ 20 %, caja que no cuadra, cobros borrados, PIN fallido) | Ajustes → Dueño a distancia | E | Dueño, Admin |
| Bitácora encadenada (verificable) | Alertas → Bitácora | E | Dueño, Admin |
| PIN del dueño para anular/borrar cobros | Alertas → PIN | E | Dueño, Admin |
| Papelera 30 días + "Deshacer" | Ajustes → Papelera · aviso tras borrar | todos | Finanzas/Admin (cada uno ve lo que borró) |

### Ajustes
| Función | Dónde |
|---|---|
| Tipo de negocio, modo simple, presentación otra vez | Ajustes → Tu negocio |
| Funciones a la vista (ocultar/mostrar, nada se borra) | Ajustes → Tu negocio |
| Pasos de los trabajos y datos extra del cliente | Ajustes → Tu negocio |
| Animaciones (automático / reducidas / completas) | Ajustes → Tu negocio |
| Equipo y permisos (invitar por correo, roles, comisiones) | Ajustes · Empresas |
| Mi plan (prueba de 3 días por RUC, pagar) | Ajustes · Avatar |
| Logo, diseño del PDF (clásico, moderno, minimal), color, ancho de ticket | Ajustes → Logo y comprobantes |
| Impresora de tickets (Bluetooth, red, PDF de rollo) | Ajustes → Impresora |
| Reporte del día por correo | Ajustes → Tu negocio |
| API y webhooks | Todas las funciones → API y webhooks (Empresa) |
| SUNAT, datos del negocio (con autocompletar por RUC), medios de cobro, seguridad, apariencia | Ajustes |

## En el comprobante (detalle de factura/boleta)
Ver PDF · Compartir · Correo · Duplicar · **Ticket** (58/80 mm) · **Enlace** (portal del cliente) · **Encuesta** ·
Cobros · Enlace de cobro · Facturar cada mes · Emitir a SUNAT · Anular con nota de crédito (pide PIN si está activo).

## Páginas públicas (sin cuenta, enlaces privados)
- `/portal/<token>`: el cliente ve sus comprobantes e historial.
- `/comprobante/<token>`: representación impresa A4 o ticket (`?f=80` o `?f=58`), con QR y valor resumen; descarga XML/CDR.
- `/tienda/<slug>` y `/tienda/<slug>/p/<id>`: tienda/carta (con `?mesa=N`).
- `/reservar/<slug>`: reservas en línea. · `/encuesta/<token>`: encuesta 1–5 estrellas.
